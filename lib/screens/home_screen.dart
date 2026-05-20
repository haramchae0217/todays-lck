import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'schedule_screen.dart';
import 'standings_screen.dart';
import 'prediction_screen.dart';
import 'community_screen.dart';
import 'profile_screen.dart';

final homeNavIndexProvider = StateProvider<int>((ref) => 0);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const List<Widget> _screens = [
    ScheduleScreen(),
    StandingsScreen(),
    PredictionScreen(),
    CommunityScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(homeNavIndexProvider);

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: _screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 1,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.transparent, Color(0xFF0891B2), Colors.transparent],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
          NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: (i) =>
                ref.read(homeNavIndexProvider.notifier).state = i,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.calendar_today_outlined),
                selectedIcon: Icon(Icons.calendar_today),
                label: '일정',
              ),
              NavigationDestination(
                icon: Icon(Icons.leaderboard_outlined),
                selectedIcon: Icon(Icons.leaderboard),
                label: '순위',
              ),
              NavigationDestination(
                icon: Icon(Icons.sports_score_outlined),
                selectedIcon: Icon(Icons.sports_score),
                label: '예측',
              ),
              NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum),
                label: '커뮤니티',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: '설정',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
