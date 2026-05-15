import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/lck_api_service.dart';
import '../models/match.dart';
import '../widgets/match_card.dart';

final scheduleProvider = FutureProvider<List<LckMatch>>((ref) async {
  return LckApiService.instance.getSchedule();
});

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(scheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LCK 일정', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: schedule.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (matches) {
          if (matches.isEmpty) {
            return const Center(child: Text('경기 일정이 없습니다'));
          }
          return RefreshIndicator(
            onRefresh: () => ref.refresh(scheduleProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: matches.length,
              itemBuilder: (_, i) => MatchCard(match: matches[i]),
            ),
          );
        },
      ),
    );
  }
}
