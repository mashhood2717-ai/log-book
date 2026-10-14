import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../models.dart';
import '../widgets/brand.dart';

/// Push alerts to admins when a driver starts or ends a trip (Android).
///
/// The admin's phone registers its Firebase token in `device_tokens`; the
/// database trigger + `trip-alerts` Edge Function do the sending.
class TripAlerts {
  static const _prefKey = 'trip_alerts_enabled';
  static const channelId = 'trip_alerts'; // must match the Edge Function

  static final enabled = ValueNotifier<bool>(true);

  /// What happened the last time this phone tried to register – shown in
  /// ⋮ → Reminders so problems are visible instead of silent.
  static final status = ValueNotifier<String>('Not checked yet');
  static bool _firebaseReady = false;
  static String? _registeredToken;

  /// Push needs Android here: iPhone push requires a paid Apple account.
  static bool get available =>
      Platform.isAndroid && AppConfig.firebaseAppId.isNotEmpty;

  static SupabaseClient get _db => Supabase.instance.client;
  static final _local = FlutterLocalNotificationsPlugin();

  static Future<void> _initFirebase() async {
    if (_firebaseReady) return;
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: AppConfig.firebaseApiKey,
        appId: AppConfig.firebaseAppId,
        messagingSenderId: AppConfig.firebaseSenderId,
        projectId: AppConfig.firebaseProjectId,
      ),
    );
    // Channel the alerts arrive on (high importance = heads-up banner).
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
          channelId,
          'Driver trip alerts',
          description: 'When a driver starts or ends a trip (admins)',
          importance: Importance.high,
        ));
    // Android only shows pushes by itself when the app is in the background;
    // show them ourselves while it's open.
    FirebaseMessaging.onMessage.listen((m) {
      final n = m.notification;
      if (n == null) return;
      _local.show(
        id: m.messageId.hashCode,
        title: n.title,
        body: n.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(channelId, 'Driver trip alerts',
              importance: Importance.high,
              priority: Priority.high,
              icon: 'ic_stat_reminder',
              color: Brand.blue),
        ),
      );
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((t) => _register(t));
    _firebaseReady = true;
  }

  static Future<void> _register(String token) async {
    await _db.rpc('register_device_token',
        params: {'p_token': token, 'p_platform': 'android'});
    _registeredToken = token;
    status.value = 'This phone is registered ✓';
  }

  /// Called after Home loads: registers an admin's phone, or removes it.
  static Future<void> sync(Profile me) async {
    if (!available) {
      status.value = 'Not available on this phone';
      return;
    }
    status.value = 'Registering…';
    try {
      final saved = (await SharedPreferences.getInstance()).getBool(_prefKey);
      enabled.value = saved ?? true;
      await _initFirebase();
      if (!me.isAdmin) {
        status.value = 'Only for admins';
        await unregister();
      } else if (!enabled.value) {
        status.value = 'Switched off';
        await unregister();
      } else {
        final token = await FirebaseMessaging.instance.getToken();
        if (token == null) {
          status.value = 'Could not register: no push token from Google';
        } else {
          await _register(token);
        }
      }
    } catch (e) {
      debugPrint('Trip alerts unavailable: $e');
      status.value = 'Could not register: ${_short(e)}';
    }
  }

  static String _short(Object e) {
    final s = e.toString().replaceAll(RegExp(r'\s+'), ' ');
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  /// Stop alerts on this phone (switch off, or before signing out).
  static Future<void> unregister() async {
    if (!available || !_firebaseReady) return;
    try {
      final token =
          _registeredToken ?? await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await _db.rpc('unregister_device_token', params: {'p_token': token});
      }
      _registeredToken = null;
    } catch (e) {
      debugPrint('Could not unregister trip alerts: $e');
    }
  }

  static Future<void> setEnabled(bool on, Profile me) async {
    enabled.value = on;
    try {
      await (await SharedPreferences.getInstance()).setBool(_prefKey, on);
    } catch (_) {}
    await sync(me);
  }

  /// Switch + status shown in the ⋮ → Reminders dialog (Android).
  static Widget settingsTile(Profile me) => ListenableBuilder(
        listenable: Listenable.merge([enabled, status]),
        builder: (context, _) {
          final ok = status.value.endsWith('✓');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled.value && me.isAdmin,
                onChanged: me.isAdmin ? (v) => setEnabled(v, me) : null,
                title: const Text('Driver trip alerts'),
                subtitle: const Text('When a driver starts or ends a trip'),
              ),
              Row(children: [
                Icon(ok ? Icons.check_circle : Icons.info_outline,
                    size: 18,
                    color: ok ? Colors.green : context.colors.amberText),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(status.value,
                      style: TextStyle(
                          fontSize: 13, color: context.colors.muted)),
                ),
                if (me.isAdmin && !ok)
                  TextButton(
                      onPressed: () => sync(me),
                      child: const Text('Try again')),
              ]),
            ],
          );
        },
      );
}
