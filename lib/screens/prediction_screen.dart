import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../constants/colors.dart';
import '../models/match.dart';
import '../models/prediction.dart';
import '../providers/auth_provider.dart';
import '../providers/prediction_providers.dart';
import '../services/prediction_service.dart';
import '../services/lck_api_service.dart';
import '../utils/team_utils.dart';
import 'schedule_screen.dart' show scheduleProvider;

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
      final result = await LckApiService.instance.getSchedule();
      final completed = result.matches.where((m) => m.isCompleted).toList();
      await PredictionService.instance.resolveCompleted(completed);
      await PredictionService.instance.syncUserStats();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('승부예측', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: AppColors.accent,
          indicatorWeight: 2,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.textLow,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [Tab(text: '예측'), Tab(text: '리더보드')],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [_PredictionTab(), _LeaderboardTab()],
      ),
    );
  }
}

// ── 예측 탭 ──────────────────────────────────────────────────────────────────
class _PredictionTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PredictionTab> createState() => _PredictionTabState();
}

class _PredictionTabState extends ConsumerState<_PredictionTab> {
  List<String> _blocks = [];
  int _blockIdx = 0;
  int _activeBlockIdx = 0; // 예측 가능한 주차
  bool _initialized = false;

  void _initBlocks(List<LckMatch> lckMatches) {
    if (_initialized) return;

    final blockFirst = <String, DateTime>{};
    final blockLast = <String, DateTime>{};
    for (final m in lckMatches) {
      if (!blockFirst.containsKey(m.blockName) ||
          m.startTime.isBefore(blockFirst[m.blockName]!)) {
        blockFirst[m.blockName] = m.startTime;
      }
      if (!blockLast.containsKey(m.blockName) ||
          m.startTime.isAfter(blockLast[m.blockName]!)) {
        blockLast[m.blockName] = m.startTime;
      }
    }

    final sorted = blockFirst.keys.toList()
      ..sort((a, b) => blockFirst[a]!.compareTo(blockFirst[b]!));

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 오늘 날짜 기준 활성 주차: 마지막 경기일이 오늘 이후인 첫 번째 주차
    int activeIdx = sorted.isEmpty ? 0 : sorted.length - 1;
    for (int i = 0; i < sorted.length; i++) {
      final last = blockLast[sorted[i]]!;
      final lastDay = DateTime(last.year, last.month, last.day);
      if (!lastDay.isBefore(today)) {
        activeIdx = i;
        break;
      }
    }

    _initialized = true;
    _blocks = sorted;
    _blockIdx = activeIdx;
    _activeBlockIdx = activeIdx;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sports_score_outlined, size: 48, color: AppColors.textLow),
            const SizedBox(height: 12),
            const Text('로그인 후 승부예측에 참여할 수 있습니다.',
                style: TextStyle(color: AppColors.textMid, fontSize: 13)),
          ],
        ),
      );
    }

    final scheduleAsync = ref.watch(scheduleProvider);
    final predsAsync = ref.watch(myPredictionsProvider);

    return scheduleAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (scheduleState) {
        // 2026 LCK 정규시즌만 (4/1 이후, LCK Cup 제외)
        final seasonStart = DateTime.utc(2026, 4, 1);
        final lckMatches = scheduleState.matches
            .where((m) => m.leagueSlug == 'lck' && !m.startTime.isBefore(seasonStart))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        _initBlocks(lckMatches);

        if (_blocks.isEmpty) {
          return const Center(
            child: Text('경기 데이터가 없습니다.',
                style: TextStyle(color: AppColors.textMid)),
          );
        }

        final currentBlock = _blocks[_blockIdx];
        final weekMatches =
            lckMatches.where((m) => m.blockName == currentBlock).toList();

        return predsAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.accent)),
          error: (e, _) => Center(child: Text('오류: $e')),
          data: (preds) {
            final predMap = {for (final p in preds) p.matchId: p};
            final allDone = weekMatches.isNotEmpty &&
                weekMatches.every((m) => m.isCompleted);

            int participated = 0, correct = 0;
            if (allDone) {
              for (final m in weekMatches) {
                final pred = predMap[m.id];
                if (pred != null) {
                  participated++;
                  final winner =
                      m.team1.outcome == 'win' ? m.team1.code : m.team2.code;
                  if (pred.predictedTeamCode == winner) correct++;
                }
              }
            }

            return Column(
              children: [
                _WeekNavigator(
                  blockName: currentBlock,
                  canPrev: _blockIdx > 0,
                  canNext: _blockIdx < _activeBlockIdx,
                  onPrev: () => setState(() => _blockIdx--),
                  onNext: () => setState(() => _blockIdx++),
                ),
                Expanded(
                  child: weekMatches.isEmpty
                      ? const _EmptyWeek()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          itemCount: weekMatches.length + (allDone ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (allDone && i == 0) {
                              return _WeekSummaryCard(
                                total: weekMatches.length,
                                participated: participated,
                                correct: correct,
                              );
                            }
                            final m = weekMatches[allDone ? i - 1 : i];
                            return _WeekMatchCard(
                              match: m,
                              existingPrediction: predMap[m.id],
                              allowPrediction: _blockIdx == _activeBlockIdx,
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ── 주차 네비게이터 ────────────────────────────────────────────────────────────
class _WeekNavigator extends StatelessWidget {
  final String blockName;
  final bool canPrev;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _WeekNavigator({
    required this.blockName,
    required this.canPrev,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: canPrev ? onPrev : null,
            color: canPrev ? AppColors.textHigh : AppColors.border,
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          const SizedBox(width: 8),
          Text(
            blockName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.textHigh,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: canNext ? onNext : null,
            color: canNext ? AppColors.textHigh : AppColors.border,
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }
}

// ── 주차 요약 카드 (모든 경기 완료 시) ──────────────────────────────────────────
class _WeekSummaryCard extends StatelessWidget {
  final int total;
  final int participated;
  final int correct;

  const _WeekSummaryCard({
    required this.total,
    required this.participated,
    required this.correct,
  });

  @override
  Widget build(BuildContext context) {
    final accuracy = participated > 0 ? correct / participated : 0.0;
    final accuracyPct =
        participated > 0 ? '${(accuracy * 100).round()}%' : '-';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '이번 주 예측 종료',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textHigh),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SummaryItem(label: '참여', value: '$participated / $total'),
              _vDivider(),
              _SummaryItem(
                label: '적중',
                value: '$correct',
                color: participated > 0 ? AppColors.win : AppColors.textMid,
              ),
              _vDivider(),
              _SummaryItem(
                label: '적중률',
                value: accuracyPct,
                color: accuracy >= 0.5 && participated > 0
                    ? AppColors.win
                    : AppColors.textMid,
              ),
            ],
          ),
          if (participated > 0) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 4,
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
                      child: Container(color: AppColors.border),
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

  Widget _vDivider() => Container(width: 1, height: 36, color: AppColors.border);
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _SummaryItem({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color ?? AppColors.textHigh),
        ),
        const SizedBox(height: 3),
        Text(label,
            style: const TextStyle(color: AppColors.textLow, fontSize: 11)),
      ],
    );
  }
}

// ── 경기 없는 주 빈 상태 ──────────────────────────────────────────────────────
class _EmptyWeek extends StatelessWidget {
  const _EmptyWeek();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_outlined, size: 40, color: AppColors.textLow),
          const SizedBox(height: 12),
          const Text('이번 주 경기가 없습니다.',
              style: TextStyle(color: AppColors.textMid, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('일정이 나오면 알려드릴게요.',
              style: TextStyle(color: AppColors.textLow, fontSize: 12)),
        ],
      ),
    );
  }
}

// ── 경기 예측 카드 ────────────────────────────────────────────────────────────
class _WeekMatchCard extends StatefulWidget {
  final LckMatch match;
  final Prediction? existingPrediction;
  final bool allowPrediction;

  const _WeekMatchCard({
    required this.match,
    this.existingPrediction,
    this.allowPrediction = true,
  });

  @override
  State<_WeekMatchCard> createState() => _WeekMatchCardState();
}

class _WeekMatchCardState extends State<_WeekMatchCard> {
  String? _selectedCode;
  bool _submitting = false;
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.existingPrediction?.predictedTeamCode;
    if (widget.match.isUpcoming) _startTimer();
  }

  @override
  void didUpdateWidget(_WeekMatchCard old) {
    super.didUpdateWidget(old);
    if (old.existingPrediction?.predictedTeamCode !=
        widget.existingPrediction?.predictedTeamCode) {
      setState(() => _selectedCode = widget.existingPrediction?.predictedTeamCode);
    }
  }

  void _startTimer() {
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateRemaining();
    });
  }

  void _updateRemaining() {
    final diff = widget.match.startTime.difference(DateTime.now());
    setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
  }

  String _fmtRemaining() {
    if (_remaining <= Duration.zero) return '';
    final d = _remaining.inDays;
    final h = (_remaining.inHours % 24).toString().padLeft(2, '0');
    final m = (_remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    if (d > 0) return '${d}일 $h:$m:$s';
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedCode == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      if (widget.existingPrediction == null) {
        await PredictionService.instance.submitPrediction(
          match: widget.match,
          predictedTeamCode: _selectedCode!,
        );
      } else {
        await PredictionService.instance.updatePrediction(
          matchId: widget.match.id,
          newTeamCode: _selectedCode!,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$_selectedCode 예측 완료!'),
          backgroundColor: AppColors.accent,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final pred = widget.existingPrediction;
    final isLive = match.isLive;
    final isDone = match.isCompleted;
    final submittedCode = pred?.predictedTeamCode;
    final hasChanged = submittedCode != null && _selectedCode != submittedCode;
    final isNew = submittedCode == null;
    final t1 = match.team1;
    final t2 = match.team2;

    Widget statusWidget;
    if (isDone) {
      final winner = t1.outcome == 'win' ? t1.code : t2.code;
      statusWidget = _ResultRow(
        t1: t1,
        t2: t2,
        myPick: pred?.predictedTeamCode,
        correct: pred != null && pred.predictedTeamCode == winner,
      );
    } else if (isLive) {
      statusWidget = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.live.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.live.withValues(alpha: 0.4)),
            ),
            child: const Text('● LIVE',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.live)),
          ),
          if (submittedCode != null) ...[
            const SizedBox(width: 8),
            Text('내 예측: $submittedCode',
                style:
                    const TextStyle(color: AppColors.textMid, fontSize: 12)),
          ],
        ],
      );
    } else if (!widget.allowPrediction) {
      // 예측 기간 아닌 주차 (미래 주차)
      statusWidget = Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.border.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 13, color: AppColors.textLow),
            SizedBox(width: 6),
            Text('이전 주차 종료 후 오픈',
                style: TextStyle(color: AppColors.textLow, fontSize: 12)),
          ],
        ),
      );
    } else {
      statusWidget = Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _PickButton(
                  team: t1,
                  selected: _selectedCode == t1.code,
                  confirmed: submittedCode == t1.code,
                  onTap: () => setState(() => _selectedCode = t1.code),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PickButton(
                  team: t2,
                  selected: _selectedCode == t2.code,
                  confirmed: submittedCode == t2.code,
                  onTap: () => setState(() => _selectedCode = t2.code),
                ),
              ),
            ],
          ),
          if (isNew || hasChanged) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton(
                onPressed: _selectedCode == null || _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      hasChanged ? const Color(0xFFD97706) : AppColors.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.border,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(hasChanged ? '변경 확정' : '예측 확정',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ] else if (!isNew) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
              ),
              child: const Center(
                child: Text('✅ 예측 완료  |  다른 팀을 눌러 변경',
                    style: TextStyle(color: AppColors.textMid, fontSize: 12)),
              ),
            ),
          ],
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF111528),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLive
              ? AppColors.live.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                DateFormat('M.d (E) HH:mm', 'ko').format(match.startTime),
                style: const TextStyle(color: AppColors.textLow, fontSize: 11),
              ),
              const Spacer(),
              if (match.isUpcoming && _fmtRemaining().isNotEmpty)
                Text(
                  '예측 종료 ${_fmtRemaining()}',
                  style: const TextStyle(color: AppColors.textLow, fontSize: 10),
                ),
            ],
          ),
          const SizedBox(height: 10),
          statusWidget,
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  final MatchTeam team;
  final bool selected;
  final bool confirmed;
  final VoidCallback onTap;

  const _PickButton({
    required this.team,
    required this.selected,
    required this.confirmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = teamColor(team.code);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.12) : const Color(0xFF161B30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? c : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Center(
          child: Text(team.code,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: selected ? c : AppColors.textMid)),
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final MatchTeam t1;
  final MatchTeam t2;
  final String? myPick;
  final bool correct;

  const _ResultRow({
    required this.t1,
    required this.t2,
    this.myPick,
    required this.correct,
  });

  @override
  Widget build(BuildContext context) {
    final win1 = t1.outcome == 'win';
    final win2 = t2.outcome == 'win';
    final c1 = teamColor(t1.code);
    final c2 = teamColor(t2.code);
    final notParticipated = myPick == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(t1.code,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: win1 ? c1 : AppColors.textLow)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${t1.gameWins} - ${t2.gameWins}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textHigh),
              ),
            ),
            Expanded(
              child: Text(t2.code,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: win2 ? c2 : AppColors.textLow)),
            ),
            if (!notParticipated)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(correct ? '✅' : '❌',
                    style: const TextStyle(fontSize: 14)),
              ),
          ],
        ),
        if (notParticipated) ...[
          const SizedBox(height: 6),
          const Text('참여하지 않았어요',
              style: TextStyle(color: AppColors.textLow, fontSize: 11)),
        ],
      ],
    );
  }
}

// ── 리더보드 탭 ───────────────────────────────────────────────────────────────
class _LeaderboardTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(authStateProvider).valueOrNull?.uid;
    final board = ref.watch(leaderboardProvider);

    return board.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (entries) {
        if (entries.isEmpty) {
          return const Center(
            child: Text('아직 예측 참여자가 없습니다.',
                style: TextStyle(color: AppColors.textMid)),
          );
        }
        final myIdx =
            myUid != null ? entries.indexWhere((e) => e.uid == myUid) : -1;

        return Column(
          children: [
            Expanded(
              child: RefreshIndicator(
                color: AppColors.accent,
                onRefresh: () async => ref.invalidate(leaderboardProvider),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF111528),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          const _LeaderboardHeader(),
                          const Divider(height: 1, color: AppColors.border),
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
                              style: TextStyle(
                                  color: AppColors.textLow, fontSize: 12)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (myIdx >= 0) _MyRankBar(rank: myIdx + 1, entry: entries[myIdx]),
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
        color: AppColors.accent,
        letterSpacing: 0.3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: const Row(
        children: [
          SizedBox(
              width: 36,
              child: Text('순위', style: style, textAlign: TextAlign.center)),
          SizedBox(width: 10),
          Expanded(child: Text('사용자', style: style)),
          SizedBox(
              width: 44,
              child: Text('적중', style: style, textAlign: TextAlign.center)),
          SizedBox(
              width: 50,
              child: Text('적중률', style: style, textAlign: TextAlign.center)),
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

  const _LeaderboardRow({
    required this.rank,
    required this.entry,
    required this.isMe,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final isTop3 = rank <= 3;
    final rankColor = switch (rank) {
      1 => const Color(0xFFD97706),
      2 => const Color(0xFF64748B),
      3 => const Color(0xFF92400E),
      _ => AppColors.textLow,
    };

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isMe
                ? AppColors.accent.withValues(alpha: 0.10)
                : rank.isEven
                    ? const Color(0xFF161B30)
                    : const Color(0xFF111528),
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
                    color: isMe ? AppColors.accent : AppColors.textHigh,
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
                      color: AppColors.accent),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text(
                  '${(entry.accuracy * 100).toStringAsFixed(0)}%',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: entry.accuracy >= 0.5
                        ? AppColors.win
                        : AppColors.textLow,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(
              height: 1, indent: 14, endIndent: 14, color: AppColors.border),
      ],
    );
  }

  String _medal(int rank) => rank == 1 ? '🥇' : rank == 2 ? '🥈' : '🥉';
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
        color: Color(0xFF0D1225),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person, size: 16, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(
            '내 순위  $rank위',
            style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.bold,
                fontSize: 13),
          ),
          const Spacer(),
          Text(
            '적중 ${entry.correctPredictions}',
            style: const TextStyle(color: AppColors.textMid, fontSize: 12),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: entry.accuracy >= 0.5
                  ? AppColors.win.withValues(alpha: 0.12)
                  : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${(entry.accuracy * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: entry.accuracy >= 0.5 ? AppColors.win : AppColors.textLow,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
