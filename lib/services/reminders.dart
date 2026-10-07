import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';
import '../widgets/brand.dart';
import '../widgets/trip_widgets.dart';

/// One daily reminder: when it fires (Pakistan time) and what it says.
class ReminderSlot {
  final int id, hour, minute;
  const ReminderSlot(this.id, this.hour, this.minute);
  String get label {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:${minute.toString().padLeft(2, '0')} ${hour < 12 ? 'AM' : 'PM'}';
  }
}

/// Daily "remember to log your trip" notifications at 11 AM and 5 PM PKT.
///
/// Scheduled on the phone itself (no server), repeat every day, and survive
/// restarts. The text is refreshed whenever the app loads, so it can mention
/// a trip that is still open.
class Reminders {
  static const slots = [ReminderSlot(1100, 11, 0), ReminderSlot(1700, 17, 0)];
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
      channelDescription: 'Daily reminders to log your trips',
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

  /// Next [hour]:[minute] in Pakistan time, strictly after [now].
  static tz.TZDateTime nextPkt(int hour, int minute, {DateTime? now}) {
    final n = tz.TZDateTime.from(now ?? DateTime.now(), pkt);
    var t = tz.TZDateTime(pkt, n.year, n.month, n.day, hour, minute);
    if (!t.isAfter(n)) t = t.add(const Duration(days: 1));
    return t;
  }

  /// Title and text for a reminder, depending on whether a trip is open.
  static (String, String) message(ReminderSlot slot, Trip? openTrip) {
    final morning = slot.hour < 12;
    if (openTrip != null) {
      final where = '${openTrip.vehicleRegNo} → ${openTrip.destination}';
      return morning
          ? ('Trip still open',
              '$where has been open since ${dateTimeFmt.format(openTrip.startTime)}. End it when you are back.')
          : ('Back yet?', 'Your trip $where is still open. Tap to end it.');
    }
    return morning
        ? ('Going out today?',
            'Start your trip in Trip Logbook before you leave.')
        : ('Logged today\'s trips?',
            'If you drove today, make sure every trip is in Trip Logbook.');
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
  static Future<bool?> checkPermission() async {
    if (!_ready) return null;
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
      for (final s in slots) {
        await _plugin.cancel(id: s.id);
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
          scheduledDate: nextPkt(s.hour, s.minute),
          notificationDetails: _details,
          androidScheduleMode: mode,
          matchDateTimeComponents: DateTimeComponents.time, // every day
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
      body: 'Reminders are working. You will get them at '
          '${slots.map((s) => s.label).join(' and ')} (Pakistan time).',
      notificationDetails: _details,
    );
    return true;
  }

  /// Settings dialog: on/off switch and a test button.
  static Future<void> showSettings(BuildContext context, {Trip? openTrip}) =>
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
                  title: const Text('Daily reminders'),
                  subtitle: Text(
                      '${slots.map((s) => s.label).join(' and ')} Pakistan time'),
                ),
                const SizedBox(height: 4),
                Text(
                  'A reminder to start your trip before you leave, and to '
                  'check every trip is logged at the end of the day.',
                  style: TextStyle(color: c.colors.muted),
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
