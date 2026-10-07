import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light / dark / follow-the-phone setting, remembered on this device.
class ThemeSettings {
  static const _key = 'theme_mode';
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Call once before runApp so the first frame uses the saved choice.
  static Future<void> load() async {
    try {
      final saved = (await SharedPreferences.getInstance()).getString(_key);
      mode.value = ThemeMode.values.firstWhere((m) => m.name == saved,
          orElse: () => ThemeMode.system);
    } catch (_) {
      // Storage unavailable – just follow the phone.
    }
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      await (await SharedPreferences.getInstance()).setString(_key, m.name);
    } catch (_) {}
  }

  static String label(ThemeMode m) => switch (m) {
        ThemeMode.system => 'Same as phone',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  static IconData icon(ThemeMode m) => switch (m) {
        ThemeMode.system => Icons.brightness_auto_outlined,
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
      };

  /// Small dialog to pick the appearance.
  static Future<void> showPicker(BuildContext context) => showDialog(
        context: context,
        builder: (c) => SimpleDialog(
          title: const Text('Appearance'),
          children: [
            for (final m in ThemeMode.values)
              ValueListenableBuilder(
                valueListenable: mode,
                builder: (_, current, __) => ListTile(
                  leading: Icon(icon(m)),
                  title: Text(label(m)),
                  trailing: current == m
                      ? Icon(Icons.check_circle,
                          color: Theme.of(c).colorScheme.primary)
                      : null,
                  onTap: () {
                    set(m);
                    Navigator.pop(c);
                  },
                ),
              ),
          ],
        ),
      );
}
