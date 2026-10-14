import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';
import '../widgets/brand.dart';
import '../widgets/trip_widgets.dart';

/// One daily reminder: when it fires (Pakistan time) and what it says.
class ReminderSlot {
  final int weekday; // DateTime.monday (1) … DateTime.sunday (7)
  final int hour; // 24h, Pakistan time
  final bool lastOfDay; // the "have you logged today's trips?" one
  const ReminderSlot(this.weekday, this.hour, {this.lastOfDay = false});

  /// Stable id per weekday + hour, e.g. Monday 9 AM = 109.
  int get id => weekday * 100 + hour;

  String get label => hourLabel(hour);
  static String hourLabel(int hour) =>
      '${hour % 12 == 0 ? 12 : hour % 12} ${hour < 12 ? 'AM' : 'PM'}';
}

/// "Remember to log your trip" notifications, Pakistan time:
/// Monday–Friday every hour 9 AM–6 PM, Saturday–Sunday 11 AM and 5 PM.
///
/// Scheduled on the phone itself (no server), each repeating weekly, and
/// they survive restarts. The text is refreshed whenever the app loads, so
/// it can mention a trip that is still open.
class Reminders {
  static const officeStart = 9, officeEnd = 18; // weekdays, inclusive
  static const weekendHours = [11, 17];

  static final List<ReminderSlot> slots = [
    for (var d = DateTime.monday; d <= DateTime.friday; d++)
      for (var h = officeStart; h <= officeEnd; h++)
        ReminderSlot(d, h, lastOfDay: h == officeEnd),
    for (final d in [DateTime.saturday, DateTime.sunday])
      for (final h in weekendHours)
        ReminderSlot(d, h, lastOfDay: h == weekendHours.last),
  ];

  /// Shown in settings and the test notification.
  static String get scheduleText =>
      'Mon–Fri every hour, ${ReminderSlot.hourLabel(officeStart)}–${ReminderSlot.hourLabel(officeEnd)} · '
      'Sat–Sun ${weekendHours.map(ReminderSlot.hourLabel).join(' & ')} (Pakistan time)';

  /// Ids used by the first version (daily 11 AM / 5 PM) – cancelled on update.
  static const _legacyIds = [1100, 1700];
  static const _prefKey = 'reminders_enabled';
  static const _testId = 9999;

  static final enabled = ValueNotifier<bool>(true);

  /// Whether the phone allows this app's notifications (null = not known yet).
  /// Drives the "notifications are off" bar on the Home screen.
  static final permission = ValueNotifier<bool?>(null);
  static final _plugin = FlutterLocalNotificationsPlugin();
  static tz.Location? _pkt;
  static bool _ready = false;

  static tz.Location get pkt {
    if (_pkt == null) {
      tzdata.initializeTimeZones();
      _pkt = tz.getLocation('Asia/Karachi');
    }
    return _pkt!;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'trip_reminders',
      'Trip reminders',
      channelDescription: 'Reminders to log your trips',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_reminder',
      color: Brand.blue,
    ),
    iOS: DarwinNotificationDetails(),
  );

  /// Call once at startup. Never throws – reminders are a nice-to-have.
  static Future<void> init() async {
    try {
      pkt; // load time zones
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_reminder'),
          // Permission is asked when reminders are first scheduled, not at launch.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      final saved = (await SharedPreferences.getInstance()).getBool(_prefKey);
      enabled.value = saved ?? true;
      _ready = true;
    } catch (e) {
      debugPrint('Reminders unavailable: $e');
    }
  }

  /// Next [weekday] at [hour]:00 in Pakistan time, strictly after [now].
  static tz.TZDateTime nextPkt(int weekday, int hour, {DateTime? now}) {
    RangeError.checkValueInInterval(weekday, DateTime.monday, DateTime.sunday, 'weekday');
    RangeError.checkValueInInterval(hour, 0, 23, 'hour');
    final n = tz.TZDateTime.from(now ?? DateTime.now(), pkt);
    var t = tz.TZDateTime(pkt, n.year, n.month, n.day, hour);
    while (t.weekday != weekday || !t.isAfter(n)) {
      t = tz.TZDateTime(pkt, t.year, t.month, t.day + 1, hour);
    }
    return t;
  }

  /// Title and text for a reminder, depending on whether a trip is open.
  static (String, String) message(ReminderSlot slot, Trip? openTrip) {
    if (openTrip != null) {
      final where = '${openTrip.vehicleRegNo} → ${openTrip.destination}';
      return (
        slot.lastOfDay ? 'Trip still open' : 'Back yet?',
        '$where is still open (since ${dateTimeFmt.format(openTrip.startTime)}). '
            'End it when you\'re back.'
      );
    }
    if (slot.lastOfDay) {
      return ('Logged today\'s trips?',
          'If you drove today, make sure every trip is in Trip Logbook.');
    }
    return ('Going out?', 'Start your trip in Trip Logbook before you leave.');
  }

  /// Shows the system "Allow notifications?" prompt (only appears if the
  /// person hasn't answered yet), then records the result.
  static Future<bool> _askPermission() async {
    bool? ok;
    try {
      if (Platform.isAndroid) {
        ok = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        ok = await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {}
    await checkPermission();
    return (ok ?? false) || permission.value == true;
  }

  /// Reads the current permission without prompting. Call when the app
  /// comes back to the foreground (the person may have changed Settings).
  /// Works even if [init] failed, so the bar can still warn people.
  static Future<bool?> checkPermission() async {
    try {
      bool? on;
      if (Platform.isAndroid) {
        on = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled();
      } else if (Platform.isIOS) {
        final opts = await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.checkPermissions();
        on = opts == null ? null : (opts.isEnabled || opts.isProvisionalEnabled);
      }
      permission.value = on;
      return on;
    } catch (_) {
      return null;
    }
  }

  /// "Allow" on the notifications-off bar: ask again, and if the phone won't
  /// show the prompt any more (refused before), open the app's settings page.
  static Future<void> requestOrOpenSettings({Trip? openTrip}) async {
    if (await _askPermission()) {
      await sync(openTrip: openTrip);
    } else {
      await Geolocator.openAppSettings();
    }
  }

  /// (Re)schedule both daily reminders. Called after every Home load.
  static Future<void> sync({Trip? openTrip}) async {
    if (!_ready) return;
    try {
      for (final id in [..._legacyIds, ...slots.map((s) => s.id)]) {
        await _plugin.cancel(id: id);
      }
      if (!enabled.value) return;
      await _askPermission();
      for (final s in slots) {
        await _schedule(s, openTrip);
      }
    } catch (e) {
      debugPrint('Could not schedule reminders: $e');
    }
  }

  static Future<void> _schedule(ReminderSlot s, Trip? openTrip) async {
    final (title, body) = message(s, openTrip);
    Future<void> go(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id: s.id,
          title: title,
          body: body,
          scheduledDate: nextPkt(s.weekday, s.hour),
          notificationDetails: _details,
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime, // weekly
        );
    try {
      // On time, even when the phone is idle.
      await go(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException {
      // Exact alarms not allowed on this phone: Android may deliver a bit late.
      await go(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  /// Stop all reminders (on sign out).
  static Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  static Future<void> setEnabled(bool on, {Trip? openTrip}) async {
    enabled.value = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_prefKey, on);
    } catch (_) {}
    await sync(openTrip: openTrip);
  }

  /// Shows a reminder right now, so people can check notifications work.
  static Future<bool> sendTest() async {
    if (!_ready) return false;
    final allowed = await _askPermission();
    if (!allowed) return false;
    await _plugin.show(
      id: _testId,
      title: 'Test reminder',
      body: 'Reminders are working. Schedule: $scheduleText.',
      notificationDetails: _details,
    );
    return true;
  }

  /// Settings dialog: on/off switch and a test button.
  /// [extra] adds more switches (e.g. admin trip alerts) under the reminders.
  static Future<void> showSettings(BuildContext context,
          {Trip? openTrip, List<Widget> extra = const []}) =>
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Trip reminders'),
          content: ValueListenableBuilder<bool>(
            valueListenable: enabled,
            builder: (_, on, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: on,
                  onChanged: (v) => setEnabled(v, openTrip: openTrip),
                  title: const Text('Trip reminders'),
                  subtitle: Text(scheduleText),
                ),
                const SizedBox(height: 4),
                Text(
                  'A reminder to start your trip before you leave, and to '
                  'check every trip is logged at the end of the day.',
                  style: TextStyle(color: c.colors.muted),
                ),
                if (extra.isNotEmpty) ...[
                  const Divider(height: 24),
                  ...extra,
                ],
                const SizedBox(height: 12),
                // Which version is installed – handy when reporting problems.
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (_, snap) => Text(
                    snap.hasData
                        ? 'App version ${snap.data!.version} (${snap.data!.buildNumber})'
                        : '',
                    style: TextStyle(fontSize: 12, color: c.colors.faint),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Send a test'),
              onPressed: () async {
                final ok = await sendTest();
                if (!c.mounted) return;
                ScaffoldMessenger.of(c).showSnackBar(SnackBar(
                    content: Text(ok
                        ? 'Test reminder sent – check your notifications.'
                        : 'Notifications are blocked. Allow them in the phone\'s Settings → Apps → Trip Logbook.')));
              },
            ),
            FilledButton(
                onPressed: () => Navigator.pop(c), child: const Text('Done')),
          ],
        ),
      );
}
