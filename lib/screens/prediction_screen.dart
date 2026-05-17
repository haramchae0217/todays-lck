import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/prediction.dart';
import '../providers/auth_provider.dart';
import '../services/prediction_service.dart';
import '../services/lck_api_service.dart';

const _kAccent = Color(0xFF0891B2);
const _kWin = Color(0xFF059669);
const _kLose = Color(0xFFEF4444);
const _kTextHigh = Color(0xFF0F172A);
const _kTextMid = Color(0xFF64748B);
const _kTextLow = Color(0xFF94A3B8);
const _kBorder = Color(0xFFE2E8F0);

final _myPredictionsProvider = StreamProvider<List<Prediction>>((ref) {
  ref.watch(authStateProvider); // 계정 변경 시 스트림 재생성
  return PredictionService.instance.myPredictions();
});

final _leaderboardProvider = FutureProvider<List<LeaderboardEntry>>((ref) {
  ref.watch(authStateProvider);
  return PredictionService.instance.getLeaderboard();
});

class PredictionScreen extends ConsumerStatefulWidget {
  const PredictionScreen({super.key});

  @override
  ConsumerState<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends ConsumerState<PredictionScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _resolveOnLoad();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _resolveOnLoad() async {
    try {
      final matches = await LckApiService.instance.getSchedule();
      final completed = matches.where((m) => m.isCompleted).toList();
      await PredictionService.instance.resolveCompleted(completed);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('승부예측', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: _kAccent,
          indicatorWeight: 2,
          labelColor: _kAccent,
          unselectedLabelColor: _kTextLow,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [Tab(text: '내 예측'), Tab(text: '리더보드')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_MyPredictionsTab(), _LeaderboardTab()],
      ),
    );
  }
}

// ── 내 예측 탭 ─────────────────────────────────────────────────────────────────
class _MyPredictionsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_score_outlined, size: 48, color: _kTextLow),
            const SizedBox(height: 12),
            const Text('로그인 후 승부예측에 참여할 수 있습니다.',
                style: TextStyle(color: _kTextMid, fontSize: 13)),
          ],
        ),
      );
    }

    final preds = ref.watch(_myPredictionsProvider);
    return preds.when(
      loading: () => const Center(child: CircularProgressIndicator(color: _kAccent)),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (list) {
        final resolved = list.where((p) => p.isCorrect != null).toList();
        final correct = resolved.where((p) => p.isCorrect == true).length;
        final total = resolved.length;
        final accuracy = total > 0 ? correct / total : 0.0;
        final accuracyStr =
            total > 0 ? '${(accuracy * 100).toStringAsFixed(0)}%' : '-';

        return Column(
          children: [
            _StatsCard(
              total: list.length,
              correct: correct,
              accuracyStr: accuracyStr,
              accuracy: accuracy,
              resolved: total,
            ),
            if (list.isEmpty)
              const Expanded(
                child: Center(
                  child: Text('일정 탭에서 경기를 탭해 예측해보세요!',
                      style: TextStyle(color: _kTextLow, fontSize: 13)),
                ),
              )
            else
              Expanded(child: _PredictionList(list: list)),
          ],
        );
      },
    );
  }
}

// ── 스탯 카드 ─────────────────────────────────────────────────────────────────
class _StatsCard extends StatelessWidget {
  final int total;
  final int correct;
  final String accuracyStr;
  final double accuracy;
  final int resolved;

  const _StatsCard({
    required this.total,
    required this.correct,
    required this.accuracyStr,
    required this.accuracy,
    required this.resolved,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kAccent.withValues(alpha: 0.08),
            const Color(0xFFF0F9FF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAccent.withValues(alpha: 0.20)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatItem(
                  icon: Icons.receipt_long_outlined,
                  label: '총 예측',
                  value: '$total전'),
              _vDivider(),
              _StatItem(
                  icon: Icons.check_circle_outline,
                  label: '적중',
                  value: '${correct}승',
                  color: _kAccent),
              _vDivider(),
              _StatItem(
                  icon: Icons.percent,
                  label: '적중률',
                  value: accuracyStr,
                  color: accuracy >= 0.5 ? _kWin : _kTextMid),
            ],
          ),
          if (resolved > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 5,
                child: Row(
                  children: [
                    Expanded(
                      flex: (accuracy * 100).round().clamp(1, 99),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF0891B2), Color(0xFF059669)],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 100 - (accuracy * 100).round().clamp(1, 99),
                      child: Container(color: _kBorder),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _vDivider() => Container(width: 1, height: 40, color: _kBorder);
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _StatItem(
      {required this.icon, required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? _kTextHigh;
    return Column(
      children: [
        Icon(icon, size: 16, color: c.withValues(alpha: 0.7)),
        const SizedBox(height: 6),
        Text(value,
            style:
                TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: _kTextLow, fontSize: 11)),
      ],
    );
  }
}

// ── 예측 목록 ────────────────────────────────────────────────────────────────
class _PredictionList extends StatefulWidget {
  final List<Prediction> list;
  const _PredictionList({required this.list});

  @override
  State<_PredictionList> createState() => _PredictionListState();
}

class _PredictionListState extends State<_PredictionList> {
  static const _pageSize = 20;
  int _limit = _pageSize;

  @override
  Widget build(BuildContext context) {
    final pending = widget.list.where((p) => p.isCorrect == null).toList();
    final completed = widget.list.where((p) => p.isCorrect != null).toList();
    final shown = completed.take(_limit).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (pending.isNotEmpty) ...[
          _SectionLabel(title: '진행중', count: pending.length, color: _kAccent),
          const SizedBox(height: 6),
          ...pending.map((p) => _PredictionTile(pred: p)),
          const SizedBox(height: 8),
        ],
        if (completed.isNotEmpty) ...[
          _SectionLabel(title: '완료', count: completed.length, color: _kTextLow),
          const SizedBox(height: 6),
          ...shown.map((p) => _PredictionTile(pred: p)),
          if (completed.length > _limit)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton(
                onPressed: () => setState(() => _limit += _pageSize),
                child: Text(
                  '더 보기 (${completed.length - _limit}개)',
                  style: const TextStyle(color: _kTextMid, fontSize: 12),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  final int count;
  final Color color;
  const _SectionLabel(
      {required this.title, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          decoration:
              BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(width: 6),
        Text('$count건', style: const TextStyle(color: _kTextLow, fontSize: 11)),
      ],
    );
  }
}

// ── 예측 타일 ─────────────────────────────────────────────────────────────────
class _PredictionTile extends StatelessWidget {
  final Prediction pred;
  const _PredictionTile({required this.pred});

  @override
  Widget build(BuildContext context) {
    final isPending = pred.isCorrect == null;
    final isCorrect = pred.isCorrect == true;
    final accentColor = isPending ? _kAccent : isCorrect ? _kWin : _kLose;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPending ? _kBorder : accentColor.withValues(alpha: 0.25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  DateFormat('M.d (E) HH:mm', 'ko').format(pred.matchTime),
                  style: const TextStyle(color: _kTextLow, fontSize: 11),
                ),
                const SizedBox(width: 6),
                Text(pred.leagueName,
                    style: const TextStyle(color: _kTextLow, fontSize: 10)),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: accentColor.withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    isPending ? '예측중' : isCorrect ? '✓ 적중' : '✗ 불일치',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _TeamChip(
                    code: pred.team1Code,
                    isPicked: pred.predictedTeamCode == pred.team1Code,
                    isWinner: pred.actualWinnerCode == pred.team1Code,
                    isResolved: !isPending,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('vs',
                      style: TextStyle(
                          fontSize: 12,
                          color: _kTextLow,
                          fontWeight: FontWeight.w500)),
                ),
                Expanded(
                  child: _TeamChip(
                    code: pred.team2Code,
                    isPicked: pred.predictedTeamCode == pred.team2Code,
                    isWinner: pred.actualWinnerCode == pred.team2Code,
                    isResolved: !isPending,
                    alignRight: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TeamChip extends StatelessWidget {
  final String code;
  final bool isPicked;
  final bool isWinner;
  final bool isResolved;
  final bool alignRight;

  const _TeamChip({
    required this.code,
    required this.isPicked,
    required this.isWinner,
    required this.isResolved,
    this.alignRight = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color textColor;
    Color? border;

    if (!isResolved) {
      bg = isPicked
          ? _kAccent.withValues(alpha: 0.10)
          : const Color(0xFFF8FAFC);
      textColor = isPicked ? _kAccent : _kTextLow;
      border = isPicked ? _kAccent.withValues(alpha: 0.45) : null;
    } else {
      if (isWinner && isPicked) {
        bg = _kWin.withValues(alpha: 0.08);
        textColor = _kWin;
        border = _kWin.withValues(alpha: 0.35);
      } else if (isWinner) {
        bg = const Color(0xFFF8FAFC);
        textColor = _kTextMid;
        border = null;
      } else if (isPicked) {
        bg = _kLose.withValues(alpha: 0.08);
        textColor = _kLose;
        border = _kLose.withValues(alpha: 0.35);
      } else {
        bg = Colors.transparent;
        textColor = _kTextLow;
        border = null;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: Row(
        mainAxisAlignment:
            alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (isPicked && !alignRight) ...[
            Icon(Icons.arrow_right, size: 14, color: textColor),
            const SizedBox(width: 2),
          ],
          Text(code,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: textColor)),
          if (isPicked && alignRight) ...[
            const SizedBox(width: 2),
            Icon(Icons.arrow_left, size: 14, color: textColor),
          ],
        ],
      ),
    );
  }
}

// ── 리더보드 탭 ───────────────────────────────────────────────────────────────
class _LeaderboardTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(authStateProvider).valueOrNull?.uid;
    final board = ref.watch(_leaderboardProvider);

    return board.when(
      loading: () => const Center(child: CircularProgressIndicator(color: _kAccent)),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (entries) {
        if (entries.isEmpty) {
          return const Center(
            child: Text('아직 예측 참여자가 없습니다.',
                style: TextStyle(color: _kTextMid)),
          );
        }
        final myIdx =
            myUid != null ? entries.indexWhere((e) => e.uid == myUid) : -1;

        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: _kAccent,
                onRefresh: () => ref.refresh(_leaderboardProvider.future),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
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
                          const _LeaderboardHeader(),
                          const Divider(height: 1, color: _kBorder),
                          ...entries.asMap().entries.map((e) => _LeaderboardRow(
                                rank: e.key + 1,
                                entry: e.value,
                                isMe: e.value.uid == myUid,
                                isLast: e.key == entries.length - 1,
                              )),
                        ],
                      ),
                    ),
                    if (myIdx < 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Center(
                          child: Text('예측에 참여하면 순위에 올라갑니다.',
                              style:
                                  TextStyle(color: _kTextLow, fontSize: 12)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (myIdx >= 0)
              _MyRankBar(rank: myIdx + 1, entry: entries[myIdx]),
          ],
        );
      },
    );
  }
}

class _LeaderboardHeader extends StatelessWidget {
  const _LeaderboardHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: _kAccent,
        letterSpacing: 0.3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: const Row(
        children: [
          SizedBox(
              width: 36,
              child:
                  Text('순위', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 10),
          Expanded(child: Text('사용자', style: style)),
          SizedBox(
              width: 44,
              child: Text('적중', style: style, textAlign: TextAlign.center)),
          SizedBox(
              width: 50,
              child:
                  Text('적중률', style: style, textAlign: TextAlign.center)),
        ],
      ),
    );
  }
}

class _LeaderboardRow extends StatelessWidget {
  final int rank;
  final LeaderboardEntry entry;
  final bool isMe;
  final bool isLast;
  const _LeaderboardRow(
      {required this.rank,
      required this.entry,
      required this.isMe,
      this.isLast = false});

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;
    final rankColor = switch (rank) {
      1 => const Color(0xFFD97706),
      2 => const Color(0xFF64748B),
      3 => const Color(0xFF92400E),
      _ => _kTextLow,
    };

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isMe
                ? _kAccent.withValues(alpha: 0.06)
                : rank.isEven
                    ? const Color(0xFFF8FAFC)
                    : Colors.white,
            borderRadius: isLast
                ? const BorderRadius.vertical(bottom: Radius.circular(14))
                : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                child: Text(
                  isTop3 ? _medal(rank) : '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isTop3 ? 17 : 14,
                    fontWeight: FontWeight.bold,
                    color: rankColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  entry.displayName + (isMe ? '  (나)' : ''),
                  style: TextStyle(
                    fontWeight: isMe ? FontWeight.bold : FontWeight.w500,
                    fontSize: 13,
                    color: isMe ? _kAccent : _kTextHigh,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${entry.correctPredictions}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kAccent),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  '${(entry.accuracy * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: entry.accuracy >= 0.5 ? _kWin : _kTextLow,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
              height: 1, indent: 14, endIndent: 14, color: _kBorder),
      ],
    );
  }

  String _medal(int rank) =>
      rank == 1 ? '🥇' : rank == 2 ? '🥈' : '🥉';
}

class _MyRankBar extends StatelessWidget {
  final int rank;
  final LeaderboardEntry entry;
  const _MyRankBar({required this.rank, required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, size: 16, color: _kAccent),
          const SizedBox(width: 6),
          Text(
            '내 순위  $rank위',
            style: const TextStyle(
                color: _kAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13),
          ),
          const Spacer(),
          Text(
            '적중 ${entry.correctPredictions}',
            style: const TextStyle(color: _kTextMid, fontSize: 12),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: entry.accuracy >= 0.5
                  ? _kWin.withValues(alpha: 0.10)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${(entry.accuracy * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: entry.accuracy >= 0.5 ? _kWin : _kTextLow,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
