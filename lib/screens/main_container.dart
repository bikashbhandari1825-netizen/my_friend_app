// screens/main_container.dart
// Role अनुसार tab हरू सहितको मुख्य Shell + inDrive-style bottom bar.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../watchlist_screen.dart';
import '../worker_requests_page.dart';
import 'home_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';

class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final data = snapshot.data?.data() as Map<String, dynamic>? ?? {};
        final role = data['role'] ?? 'employer';
        final isWorker = role == 'worker';

        final screens = isWorker
            ? const [
                HomeScreen(),
                WorkerRequestsPage(),
                MessagesScreen(),
                ProfileScreen(),
              ]
            : const [
                HomeScreen(),
                WatchlistScreen(),
                MessagesScreen(),
                ProfileScreen(),
              ];

        final items = isWorker
            ? [
                _NavItem(Icons.home_rounded, S.navHome),
                _NavItem(Icons.assignment_rounded, S.navRequests),
                _NavItem(Icons.chat_bubble_rounded, S.navMessages),
                _NavItem(Icons.person_rounded, S.navProfile),
              ]
            : [
                _NavItem(Icons.home_rounded, S.navHome),
                _NavItem(Icons.bookmark_rounded, S.navWatchlist),
                _NavItem(Icons.chat_bubble_rounded, S.navMessages),
                _NavItem(Icons.person_rounded, S.navProfile),
              ];

        return Scaffold(
          body: IndexedStack(index: _currentIndex, children: screens),
          bottomNavigationBar: _BottomBar(
            items: items,
            currentIndex: _currentIndex,
            onTap: (i) => setState(() => _currentIndex = i),
          ),
        );
      },
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

class _BottomBar extends StatelessWidget {
  final List<_NavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomBar({
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = i == currentIndex;
              final item = items[i];
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 3,
                        width: selected ? 22 : 0,
                        decoration: BoxDecoration(
                          color: AppColors.lime,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Icon(item.icon,
                          size: 24,
                          color: selected
                              ? AppColors.lime
                              : theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? AppColors.lime
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
