import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../constants/colors.dart';
import '../models/match.dart';
import '../models/prediction.dart';
import '../providers/auth_provider.dart';
import '../providers/prediction_providers.dart';
import '../models/standing.dart';
import 'match_detail_screen.dart';
import 'schedule_screen.dart' show scheduleProvider;
import 'standings_screen.dart' show standingsProvider, StandingsScreen;
import 'home_screen.dart' show homeNavIndexProvider;

class HomeTab extends ConsumerWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final scheduleAsync = ref.watch(scheduleProvider);
    final leaderboardAsync = ref.watch(leaderboardProvider);
    final predictionsAsync = user != null ? ref.watch(myPredictionsProvider) : null;

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () async {
            ref.invalidate(scheduleProvider);
            ref.invalidate(standingsProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 헤더 ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('M월 d일 (E)', 'ko').format(now),
                            style: const TextStyle(
                                color: AppColors.textMid, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '오늘의 LCK',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textHigh,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      if (user == null)
                        Text('로그인 해주세요',
                            style: const TextStyle(
                                color: AppColors.textMid, fontSize: 12)),
                    ],
                  ),
                ),

                // ── 오늘의 경기 ──
                _SectionHeader(
                  title: '오늘의 경기',
                  onMore: () =>
                      ref.read(homeNavIndexProvider.notifier).state = 1,
                ),
                scheduleAsync.when(
                  loading: () => const _LoadingRow(),
                  error: (e, _) => _ErrorRow('일정 로딩 오류'),
                  data: (state) {
                    final today = state.matches.where((m) {
                      return DateFormat('yyyy-MM-dd').format(m.startTime) ==
                          todayStr;
                    }).toList();

                    if (today.isEmpty) {
                      // 오늘 경기 없으면 다음 예정 경기
                      final upcoming = state.matches
                          .where((m) =>
                              m.isUpcoming &&
                              m.startTime.isAfter(now))
                          .toList()
                        ..sort((a, b) => a.startTime.compareTo(b.startTime));
                      if (upcoming.isEmpty) {
                        return const _EmptyRow('오늘 경기가 없습니다');
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                            child: Text(
                              '다음 예정 경기',
                              style: TextStyle(
                                  color: AppColors.textLow, fontSize: 11),
                            ),
                          ),
                          ...upcoming
                              .take(3)
                              .map((m) => _HomeMatchCard(match: m)),
                        ],
                      );
                    }
                    return Column(
                      children:
                          today.take(5).map((m) => _HomeMatchCard(match: m)).toList(),
                    );
                  },
                ),

                const SizedBox(height: 8),

                // ── 내 예측 현황 (로그인 시) ──
                if (user != null) ...[
                  _SectionHeader(
                    title: '내 예측 현황',
                    onMore: () =>
                        ref.read(homeNavIndexProvider.notifier).state = 2,
                  ),
                  predictionsAsync!.when(
                    loading: () => const _LoadingRow(),
                    error: (e, _) => _ErrorRow('예측 로딩 오류'),
                    data: (list) => _MyPredictionSummary(list: list),
                  ),
                  const SizedBox(height: 8),
                ],

                // ── 리더보드 TOP 3 ──
                _SectionHeader(
                  title: '리더보드 TOP 3',
                  onMore: () =>
                      ref.read(homeNavIndexProvider.notifier).state = 2,
                ),
                leaderboardAsync.when(
                  loading: () => const _LoadingRow(),
                  error: (e, _) => _ErrorRow('리더보드 로딩 오류'),
                  data: (entries) => _LeaderboardPreview(
                      entries: entries.take(3).toList(),
                      myUid: user?.uid),
                ),

                const SizedBox(height: 8),

                // ── 순위 바로가기 ──
                _SectionHeader(title: 'LCK 순위'),
                Consumer(
                  builder: (context, ref, _) {
                    final st = ref.watch(standingsProvider);
                    return st.when(
                      loading: () => const _LoadingRow(),
                      error: (e, _) => const _ErrorRow('순위 로딩 오류'),
                      data: (standings) => _StandingsPreview(
                        standings: standings.take(5).toList(),
                        onMoreTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const StandingsScreen()),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 섹션 헤더 ────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;
  const _SectionHeader({required this.title, this.onMore});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textHigh,
            ),
          ),
          const Spacer(),
          if (onMore != null)
            GestureDetector(
              onTap: onMore,
              child: const Row(
                children: [
                  Text('더 보기',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.accent)),
                  Icon(Icons.chevron_right, size: 16, color: AppColors.accent),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── 홈 경기 카드 ──────────────────────────────────────────────────────────────
class _HomeMatchCard extends StatelessWidget {
  final LckMatch match;
  const _HomeMatchCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final isLive = match.isLive;
    final isDone = match.isCompleted;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MatchDetailScreen(match: match)),
      ),
      child: Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLive
              ? AppColors.live.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          // 팀1
          Expanded(
            child: Text(
              match.team1.code,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDone && match.team1.outcome == 'win'
                    ? AppColors.textHigh
                    : isDone
                        ? AppColors.textLow
                        : AppColors.textHigh,
              ),
            ),
          ),
          // 스코어/시간
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isLive
                  ? AppColors.live.withValues(alpha: 0.1)
                  : AppColors.cardAlt,
              borderRadius: BorderRadius.circular(8),
            ),
            child: isLive
                ? const Text(
                    'LIVE',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.live,
                        letterSpacing: 1),
                  )
                : isDone
                    ? Text(
                        '${match.team1.gameWins} : ${match.team2.gameWins}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textHigh,
                            letterSpacing: 2),
                      )
                    : Text(
                        DateFormat('HH:mm').format(match.startTime),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMid),
                      ),
          ),
          // 팀2
          Expanded(
            child: Text(
              match.team2.code,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDone && match.team2.outcome == 'win'
                    ? AppColors.textHigh
                    : isDone
                        ? AppColors.textLow
                        : AppColors.textHigh,
              ),
            ),
          ),
          // 리그
          Text(
            match.leagueSlug == 'lck' ? 'LCK' : match.leagueName,
            style: const TextStyle(fontSize: 10, color: AppColors.textLow),
          ),
        ],
      ),
    ),
    );
  }
}

// ── 내 예측 요약 카드 ──────────────────────────────────────────────────────────
class _MyPredictionSummary extends StatelessWidget {
  final List<Prediction> list;
  const _MyPredictionSummary({required this.list});

  @override
  Widget build(BuildContext context) {
    final completed = list.where((p) => p.isCorrect != null).toList();
    final correct = completed.where((p) => p.isCorrect == true).length;
    final pending = list.where((p) => p.isCorrect == null).length;
    final accuracy = completed.isNotEmpty ? correct / completed.length : 0.0;

    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: _EmptyCard('아직 예측한 경기가 없습니다.\n경기를 탭해 첫 예측을 해보세요!'),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.08),
            const Color(0xFF091A2E),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _MiniStat(
              value: '${list.length}',
              label: '총 예측',
              color: AppColors.textHigh),
          _vDivider(),
          _MiniStat(
              value: '$correct',
              label: '적중',
              color: AppColors.accent),
          _vDivider(),
          _MiniStat(
              value: completed.isNotEmpty
                  ? '${(accuracy * 100).toStringAsFixed(0)}%'
                  : '-',
              label: '적중률',
              color: accuracy >= 0.5 ? AppColors.win : AppColors.textMid),
          _vDivider(),
          _MiniStat(
              value: '$pending',
              label: '진행중',
              color: AppColors.textMid),
        ],
      ),
    );
  }

  Widget _vDivider() =>
      Container(width: 1, height: 32, color: AppColors.border);
}

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _MiniStat(
      {required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textLow)),
      ],
    );
  }
}

// ── 리더보드 미리보기 ──────────────────────────────────────────────────────────
class _LeaderboardPreview extends StatelessWidget {
  final List<LeaderboardEntry> entries;
  final String? myUid;
  const _LeaderboardPreview({required this.entries, this.myUid});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: _EmptyCard('아직 리더보드가 없습니다.'),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: entries.asMap().entries.map((e) {
          final rank = e.key + 1;
          final entry = e.value;
          final isMe = entry.uid == myUid;
          final isLast = e.key == entries.length - 1;
          final medal = rank == 1 ? '🥇' : rank == 2 ? '🥈' : '🥉';

          return Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isMe
                      ? AppColors.accent.withValues(alpha: 0.08)
                      : rank.isOdd
                          ? AppColors.card
                          : AppColors.cardAlt,
                  borderRadius: isLast
                      ? const BorderRadius.vertical(bottom: Radius.circular(14))
                      : BorderRadius.zero,
                ),
                child: Row(
                  children: [
                    Text(medal,
                        style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        entry.displayName + (isMe ? '  (나)' : ''),
                        style: TextStyle(
                          fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                          fontSize: 13,
                          color:
                              isMe ? AppColors.accent : AppColors.textHigh,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${entry.correctPredictions}적중',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.accent,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(entry.accuracy * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: entry.accuracy >= 0.5
                            ? AppColors.win
                            : AppColors.textLow,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(
                    height: 1, indent: 16, endIndent: 16, color: AppColors.border),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── 순위 미리보기 ──────────────────────────────────────────────────────────────
class _StandingsPreview extends StatelessWidget {
  final List<Standing> standings;
  final VoidCallback onMoreTap;
  const _StandingsPreview({required this.standings, required this.onMoreTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          ...standings.asMap().entries.map((e) {
            final s = e.value;
            final isLast = e.key == standings.length - 1;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${s.rank}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.textMid),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s.teamCode,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textHigh)),
                      ),
                      Text('${s.wins}승 ${s.losses}패',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMid)),
                    ],
                  ),
                ),
                if (!isLast)
                  const Divider(
                      height: 1, indent: 16, endIndent: 16, color: AppColors.border),
              ],
            );
          }),
          InkWell(
            onTap: onMoreTap,
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.cardAlt,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(14)),
                border: const Border(top: BorderSide(color: AppColors.border)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('전체 순위 보기',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.accent)),
                  Icon(Icons.chevron_right, size: 16, color: AppColors.accent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 유틸 위젯 ─────────────────────────────────────────────────────────────────
class _LoadingRow extends StatelessWidget {
  const _LoadingRow();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Center(
          child: CircularProgressIndicator(
              color: AppColors.accent, strokeWidth: 2)),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  final String message;
  const _ErrorRow(this.message);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(message,
          style: const TextStyle(color: AppColors.textLow, fontSize: 12)),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  final String message;
  const _EmptyRow(this.message);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Text(message,
          style: const TextStyle(color: AppColors.textLow, fontSize: 12)),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard(this.message);
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textLow, fontSize: 13),
        textAlign: TextAlign.center,
      ),
    );
  }
}
