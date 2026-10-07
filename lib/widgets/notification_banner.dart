import 'package:flutter/material.dart';

import '../models.dart';
import '../services/reminders.dart';
import 'brand.dart';

/// Bar shown at the top of Home while reminders are switched on but the
/// phone is blocking this app's notifications. Disappears once allowed.
class NotificationBanner extends StatelessWidget {
  /// The driver's open trip, so re-scheduled reminders mention it.
  final Trip? openTrip;
  const NotificationBanner({super.key, this.openTrip});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([Reminders.enabled, Reminders.permission]),
      builder: (context, _) {
        final show =
            Reminders.enabled.value && Reminders.permission.value == false;
        return AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: show ? _bar(context) : const SizedBox(width: double.infinity),
        );
      },
    );
  }

  Widget _bar(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Brand.orange.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Brand.orange.withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        Icon(Icons.notifications_off_outlined, color: c.amberText),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notifications are off',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: c.amberText)),
              Text('You won\'t get the 11 AM and 5 PM trip reminders.',
                  style: TextStyle(color: c.ink, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(width: 6),
        FilledButton(
          onPressed: () => Reminders.requestOrOpenSettings(openTrip: openTrip),
          style: FilledButton.styleFrom(
            backgroundColor: c.amberText,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            minimumSize: const Size(0, 40),
            textStyle:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          child: const Text('Allow'),
        ),
      ]),
    );
  }
}
