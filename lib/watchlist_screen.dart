// watchlist_screen.dart
// inDrive-style: dark surface cards, lime icon badges.
import 'package:flutter/material.dart';

import 'l10n/strings.dart';
import 'widgets/app_ui.dart';
import 'screens/worker_list_screen.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  static const List<Map<String, dynamic>> _services = [
    {'name': 'Mechanic', 'icon': Icons.car_repair},
    {'name': 'Plumber', 'icon': Icons.plumbing},
    {'name': 'Carpenter', 'icon': Icons.carpenter},
    {'name': 'Painter', 'icon': Icons.format_paint},
    {'name': 'Cleaner', 'icon': Icons.cleaning_services},
    {'name': 'Driver', 'icon': Icons.drive_eta},
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(S.watchlistTitle)),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _services.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(S.watchlistHint,
                  style: theme.textTheme.bodySmall),
            );
          }
          final service = _services[index - 1];
          final name = service['name'] as String;
          return AppCard(
            padding: const EdgeInsets.all(14),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WorkerListScreen(serviceName: name),
              ),
            ),
            child: Row(
              children: [
                LimeIconBadge(service['icon'] as IconData),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    S.serviceName(name),
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: theme.colorScheme.onSurfaceVariant),
              ],
            ),
          );
        },
      ),
    );
  }
}
