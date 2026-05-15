import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/lck_api_service.dart';
import '../models/standing.dart';

final standingsProvider = FutureProvider<List<Standing>>((ref) async {
  return LckApiService.instance.getStandings();
});

class StandingsScreen extends ConsumerWidget {
  const StandingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standings = ref.watch(standingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LCK 순위', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: standings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(standingsProvider.future),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            itemBuilder: (_, i) => _StandingRow(standing: list[i], index: i),
          ),
        ),
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  final Standing standing;
  final int index;

  const _StandingRow({required this.standing, required this.index});

  @override
  Widget build(BuildContext context) {
    final isTop = standing.rank <= 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF141928),
        borderRadius: BorderRadius.circular(12),
        border: isTop
            ? Border.all(color: const Color(0xFF0BC4E3).withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${standing.rank}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isTop ? const Color(0xFF0BC4E3) : Colors.white70,
              ),
            ),
          ),
          const SizedBox(width: 12),
          CachedNetworkImage(
            imageUrl: standing.imageUrl,
            width: 36,
            height: 36,
            errorWidget: (_, __, ___) => const Icon(Icons.shield, size: 36),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(standing.teamName,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(standing.teamCode,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          Text(
            '${standing.wins}승 ${standing.losses}패',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 42,
            child: Text(
              '${(standing.winRate * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: standing.winRate >= 0.5 ? Colors.greenAccent : Colors.redAccent,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
