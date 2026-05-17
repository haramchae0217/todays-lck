import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/lck_api_service.dart';
import '../models/standing.dart';
import '../models/match.dart';
import '../models/team.dart';
import 'team_detail_screen.dart';
import 'teams_screen.dart' show teamsProvider;
import 'schedule_screen.dart' show scheduleProvider;
import '../utils/team_utils.dart';

const _kAccent = Color(0xFF0891B2);
const _kTextHigh = Color(0xFF0F172A);
const _kTextLow = Color(0xFF94A3B8);
const _kBorder = Color(0xFFE2E8F0);

const _headerStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: _kAccent,
  letterSpacing: 0.3,
);

final standingsProvider = FutureProvider<List<Standing>>((ref) async {
  final results = await Future.wait([
    LckApiService.instance.getStandings(),
    ref.watch(scheduleProvider.future),
  ]);

  final standings = results[0] as List<Standing>;
  final matches = results[1] as List<LckMatch>;

  final gameDiff = <String, int>{};
  for (final m in matches) {
    if (!m.isCompleted || m.leagueSlug != 'lck') continue;
    gameDiff[m.team1.code] = (gameDiff[m.team1.code] ?? 0) + m.team1.gameWins - m.team2.gameWins;
    gameDiff[m.team2.code] = (gameDiff[m.team2.code] ?? 0) + m.team2.gameWins - m.team1.gameWins;
  }

  final withDiff = standings
      .map((s) => s.copyWith(gameDiff: gameDiff[s.teamCode] ?? 0))
      .toList()
    ..sort((a, b) {
      final w = b.wins.compareTo(a.wins);
      if (w != 0) return w;
      final l = a.losses.compareTo(b.losses);
      if (l != 0) return l;
      return b.gameDiff.compareTo(a.gameDiff);
    });

  for (int i = 0; i < withDiff.length; i++) {
    withDiff[i] = withDiff[i].copyWith(rank: i + 1);
  }

  return withDiff;
});

class StandingsScreen extends ConsumerWidget {
  const StandingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standings = ref.watch(standingsProvider);
    final teams = ref.watch(teamsProvider).valueOrNull ?? [];
    final teamMap = {for (final t in teams) t.code: t};

    return Scaffold(
      appBar: AppBar(
        title: const Text('LCK 순위', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: standings.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _kAccent)),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (list) {
          return RefreshIndicator(
            color: _kAccent,
            onRefresh: () => ref.refresh(standingsProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _kBorder),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const _TableHeader(),
                      Divider(height: 1, thickness: 1, color: _kBorder),
                      ...list.asMap().entries.map((e) => _StandingRow(
                        standing: e.value,
                        index: e.key,
                        team: teamMap[e.value.teamCode],
                        isLast: e.key == list.length - 1,
                      )),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

const double _wRank = 28;
const double _wLogo = 36;
const double _wStat = 34;
const double _wDiff = 42;
const double _wRate = 46;

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: const Row(
        children: [
          SizedBox(width: _wRank, child: Text('#', style: _headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: 8),
          SizedBox(width: _wLogo),
          SizedBox(width: 10),
          Expanded(child: Text('팀', style: _headerStyle)),
          SizedBox(width: _wStat, child: Text('승', style: _headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: 6),
          SizedBox(width: _wStat, child: Text('패', style: _headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: 6),
          SizedBox(width: _wDiff, child: Text('득실차', style: _headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: 6),
          SizedBox(width: _wRate, child: Text('승률', style: _headerStyle, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

class _StandingRow extends StatelessWidget {
  final Standing standing;
  final int index;
  final Team? team;
  final bool isLast;

  const _StandingRow({required this.standing, required this.index, this.team, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final rankColor = switch (standing.rank) {
      1 => const Color(0xFFD97706), // amber-600
      2 => const Color(0xFF64748B), // slate-500
      3 => const Color(0xFF92400E), // amber-800 (bronze)
      _ => _kTextLow,
    };
    final diffColor = standing.gameDiff > 0
        ? const Color(0xFF059669)
        : standing.gameDiff < 0
            ? const Color(0xFFEF4444)
            : _kTextLow;

    return Column(
      children: [
        GestureDetector(
          onTap: team == null
              ? null
              : () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team!))),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: index.isEven ? Colors.white : const Color(0xFFF8FAFC),
              borderRadius: isLast
                  ? const BorderRadius.vertical(bottom: Radius.circular(14))
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: _wRank,
                  child: Text(
                    '${standing.rank}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: rankColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: _wLogo,
                  height: _wLogo,
                  decoration: BoxDecoration(
                    color: teamLogoBgColor(standing.teamCode),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Image.network(
                    standing.imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.shield, size: 24, color: _kTextLow),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    standing.teamCode,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: _kTextHigh,
                    ),
                  ),
                ),
                SizedBox(
                  width: _wStat,
                  child: Text(
                    '${standing.wins}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _kTextHigh),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: _wStat,
                  child: Text(
                    '${standing.losses}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: _kTextLow),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: _wDiff,
                  child: Text(
                    standing.gameDiff > 0 ? '+${standing.gameDiff}' : '${standing.gameDiff}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: diffColor),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: _wRate,
                  child: Text(
                    '${(standing.winRate * 100).toStringAsFixed(0)}%',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: standing.winRate >= 0.5
                          ? const Color(0xFF059669)
                          : const Color(0xFFEF4444),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          const Divider(height: 1, thickness: 1, indent: 14, endIndent: 14, color: _kBorder),
      ],
    );
  }
}
