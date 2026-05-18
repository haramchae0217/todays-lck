import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/colors.dart';
import '../models/match.dart';
import '../models/match_detail.dart';
import '../models/standing.dart';
import '../providers/auth_provider.dart';
import '../services/lck_api_service.dart';
import '../services/prediction_service.dart';
import '../utils/team_utils.dart';
import 'schedule_screen.dart' show scheduleProvider;
import 'standings_screen.dart' show standingsProvider;

class MatchDetailScreen extends ConsumerStatefulWidget {
  final LckMatch match;
  const MatchDetailScreen({super.key, required this.match});

  @override
  ConsumerState<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends ConsumerState<MatchDetailScreen> {
  // 예측 상태
  String? _submittedPick;
  String? _myPick;
  ({int team1Count, int team2Count})? _stats;
  bool _loadingPrediction = true;
  bool _submitting = false;

  // 완료 경기 세트별 상세
  MatchDetail? _detail;

  // 카운트다운 타이머
  Timer? _timer;
  Duration _remaining = Duration.zero;

  bool get _isNew => _submittedPick == null;

  @override
  void initState() {
    super.initState();
    // Clear cached event details so updated winner parsing applies
    if (widget.match.isCompleted) {
      LckApiService.instance.clearCache('getEventDetails?hl=ko-KR&id=${widget.match.id}');
    }
    _loadData();
    if (widget.match.isUpcoming) _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateRemaining();
    });
  }

  void _updateRemaining() {
    final diff = widget.match.startTime.difference(DateTime.now());
    setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
  }

  Future<void> _loadData() async {
    final match = widget.match;
    final user = ref.read(authStateProvider).valueOrNull;

    try {
      final futures = <Future>[];
      if (user != null) futures.add(PredictionService.instance.getMyPrediction(match.id));
      futures.add(PredictionService.instance.getMatchStats(
        matchId: match.id,
        team1Code: match.team1.code,
        team2Code: match.team2.code,
      ));
      if (match.isCompleted) futures.add(LckApiService.instance.getEventDetails(match.id));

      final results = await Future.wait(futures);
      if (!mounted) return;

      int idx = 0;
      String? pick;
      ({int team1Count, int team2Count})? stats;
      MatchDetail? detail;

      if (user != null) {
        pick = results[idx] as String?;
        idx++;
      }
      stats = results[idx++] as ({int team1Count, int team2Count});
      if (match.isCompleted && idx < results.length) {
        detail = results[idx] as MatchDetail;
      }

      // 완료 경기는 게임 window 스탯도 병렬 로드
      if (detail != null) {
        detail = await LckApiService.instance.enrichWithWindowData(detail, match);
      }

      if (!mounted) return;
      setState(() {
        _submittedPick = pick;
        _myPick = pick;
        _stats = stats;
        _detail = detail;
        _loadingPrediction = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPrediction = false);
    }
  }

  void _select(String code) {
    if (_submitting) return;
    setState(() => _myPick = code);
  }

  Future<void> _confirm() async {
    if (_myPick == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      if (_isNew) {
        await PredictionService.instance.submitPrediction(
          match: widget.match,
          predictedTeamCode: _myPick!,
        );
      } else {
        await PredictionService.instance.updatePrediction(
          matchId: widget.match.id,
          newTeamCode: _myPick!,
        );
      }
      if (!mounted) return;
      // 이전 pick을 먼저 저장해야 stats 계산이 정확함
      final prevPick = _submittedPick;
      setState(() {
        _submittedPick = _myPick;
        _submitting = false;
        if (_stats != null) {
          final t1 = widget.match.team1.code;
          var t1c = _stats!.team1Count;
          var t2c = _stats!.team2Count;
          if (prevPick == t1) t1c--;
          else if (prevPick != null) t2c--;
          if (_myPick == t1) t1c++;
          else t2c++;
          _stats = (team1Count: t1c, team2Count: t2c);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_isNew ? '${_myPick!} 예측 완료!' : '${_myPick!}로 변경 완료!'),
          backgroundColor: AppColors.accent,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final user = ref.watch(authStateProvider).valueOrNull;
    final standings = ref.watch(standingsProvider).valueOrNull ?? [];
    final scheduleState = ref.watch(scheduleProvider).valueOrNull;

    final title = match.isCompleted
        ? 'Post Game Breakdown'
        : match.isLive
            ? '경기 진행 중'
            : 'Match Preview';

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 상단 매치 카드 ──
            _MatchHeader(match: match),

            // ── 예측 % 바 + 상태 라벨 ──
            if (_stats != null)
              _PredictionBar(
                match: match,
                stats: _stats!,
                myPick: _submittedPick,
              ),

            const SizedBox(height: 8),

            // ── 상태별 콘텐츠 ──
            if (match.isUpcoming) ...[
              // 예측 UI (로그인 시)
              if (user != null) _PredictSection(
                match: match,
                myPick: _myPick,
                submittedPick: _submittedPick,
                loading: _loadingPrediction,
                submitting: _submitting,
                remaining: _remaining,
                onSelect: _select,
                onConfirm: _confirm,
              ),
              // 팀 비교 (순위 + 최근 폼)
              _TeamCompareCard(
                match: match,
                standings: standings,
                allMatches: scheduleState?.matches ?? [],
              ),
            ] else if (match.isLive) ...[
              // 나의 예측 (읽기 전용)
              if (_submittedPick != null)
                _MyPickBadge(teamCode: _submittedPick!, match: match),
              // 라이브 안내
              const _LiveBanner(),
            ] else ...[
              // 나의 예측 결과
              if (!_loadingPrediction)
                _MyResultCard(match: match, myPick: _submittedPick),
              // 세트별 결과
              if (_detail != null) _GameByGameCard(match: match, detail: _detail!),
              // VOD 버튼 (없으면 준비중 표시)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SizedBox(
                  width: double.infinity,
                  child: match.hasVod
                      ? OutlinedButton.icon(
                          onPressed: _openVod,
                          icon: const Icon(Icons.play_circle_outline, size: 20),
                          label: const Text('VOD 보기', style: TextStyle(fontSize: 14)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: const BorderSide(color: AppColors.accent),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.hourglass_empty, size: 18),
                          label: const Text('VOD 준비중', style: TextStyle(fontSize: 14)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textLow,
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openVod() async {
    final url = Uri.parse('https://lolesports.com/vod/${widget.match.id}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

// ── 상단 매치 헤더 카드 ────────────────────────────────────────────────────────
class _MatchHeader extends StatelessWidget {
  final LckMatch match;
  const _MatchHeader({required this.match});

  @override
  Widget build(BuildContext context) {
    final t1 = match.team1;
    final t2 = match.team2;
    final isLive = match.isLive;
    final isDone = match.isCompleted;
    final winner1 = isDone && t1.outcome == 'win';
    final winner2 = isDone && t2.outcome == 'win';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            teamColor(t1.code).withValues(alpha: 0.12),
            const Color(0xFF111528),
            teamColor(t2.code).withValues(alpha: 0.12),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLive
              ? AppColors.live.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          // 날짜 + 리그
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                DateFormat('yyyy년 M월 d일 EEEE', 'ko').format(match.startTime),
                style: const TextStyle(color: AppColors.textLow, fontSize: 11),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  match.leagueName,
                  style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 팀1 | 스코어/시간 | 팀2
          Row(
            children: [
              // 팀1
              Expanded(
                child: Column(
                  children: [
                    _TeamLogo(imageUrl: t1.imageUrl, size: 40),
                    const SizedBox(height: 4),
                    Text(
                      t1.code,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: winner1
                            ? AppColors.textHigh
                            : isDone
                                ? AppColors.textLow
                                : teamColor(t1.code),
                      ),
                    ),
                    if (isDone && winner1)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.win.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '승',
                          style: TextStyle(
                              color: AppColors.win,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
              // 중앙 스코어/시간
              Expanded(
                child: Column(
                  children: [
                    if (isLive) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('${t1.gameWins}',
                              style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textHigh)),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(':',
                                style: TextStyle(
                                    fontSize: 22,
                                    color: AppColors.textMid)),
                          ),
                          Text('${t2.gameWins}',
                              style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textHigh)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.live.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: AppColors.live.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          '● LIVE',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppColors.live,
                              letterSpacing: 0.5),
                        ),
                      ),
                    ] else if (isDone) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${t1.gameWins}',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: winner1 ? AppColors.textHigh : AppColors.textMid,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '${t2.gameWins}',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              color: winner2 ? AppColors.textHigh : AppColors.textMid,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Best of ${match.bestOf}',
                        style: const TextStyle(
                            color: AppColors.textLow, fontSize: 10),
                      ),
                    ] else ...[
                      Text(
                        DateFormat('HH:mm').format(match.startTime),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textHigh,
                          letterSpacing: -1,
                        ),
                      ),
                      Text(
                        match.blockName,
                        style: const TextStyle(
                            color: AppColors.textLow, fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              // 팀2
              Expanded(
                child: Column(
                  children: [
                    _TeamLogo(imageUrl: t2.imageUrl, size: 40),
                    const SizedBox(height: 4),
                    Text(
                      t2.code,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: winner2
                            ? AppColors.textHigh
                            : isDone
                                ? AppColors.textLow
                                : teamColor(t2.code),
                      ),
                    ),
                    if (isDone && winner2)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.win.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '승',
                          style: TextStyle(
                              color: AppColors.win,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 예측 % 바 ─────────────────────────────────────────────────────────────────
class _PredictionBar extends StatelessWidget {
  final LckMatch match;
  final ({int team1Count, int team2Count}) stats;
  final String? myPick;

  const _PredictionBar({
    required this.match,
    required this.stats,
    this.myPick,
  });

  @override
  Widget build(BuildContext context) {
    final total = stats.team1Count + stats.team2Count;
    if (total == 0) return const SizedBox.shrink();

    final t1Pct = stats.team1Count / total;
    final t2Pct = 1.0 - t1Pct;
    final c1 = teamColor(match.team1.code);
    final c2 = teamColor(match.team2.code);
    final label = match.isCompleted
        ? '예측 종료'
        : match.isLive
            ? '예측 마감'
            : '승부 예측';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          // 팀1 %
          Text(
            '${(t1Pct * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: c1,
            ),
          ),
          const Spacer(),
          // 중앙 라벨 + 바
          Expanded(
            flex: 4,
            child: Column(
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.textLow, fontSize: 11)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        if (stats.team1Count > 0)
                          Expanded(
                            flex: stats.team1Count,
                            child: Container(color: c1),
                          ),
                        if (stats.team2Count > 0)
                          Expanded(
                            flex: stats.team2Count,
                            child: Container(color: c2),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '총 $total명 참여',
                  style: const TextStyle(
                      color: AppColors.textLow, fontSize: 10),
                ),
              ],
            ),
          ),
          const Spacer(),
          // 팀2 %
          Text(
            '${(t2Pct * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: c2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 예측 UI (예정 경기) ───────────────────────────────────────────────────────
class _PredictSection extends StatelessWidget {
  final LckMatch match;
  final String? myPick;
  final String? submittedPick;
  final bool loading;
  final bool submitting;
  final Duration remaining;
  final ValueChanged<String> onSelect;
  final VoidCallback onConfirm;

  const _PredictSection({
    required this.match,
    this.myPick,
    this.submittedPick,
    required this.loading,
    required this.submitting,
    required this.remaining,
    required this.onSelect,
    required this.onConfirm,
  });

  String _fmt(Duration r) {
    if (r <= Duration.zero) return '';
    final d = r.inDays;
    final h = (r.inHours % 24).toString().padLeft(2, '0');
    final m = (r.inMinutes % 60).toString().padLeft(2, '0');
    final s = (r.inSeconds % 60).toString().padLeft(2, '0');
    if (d > 0) return '${d}일 $h:$m:$s';
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isNew = submittedPick == null;
    final hasChanged = submittedPick != null && myPick != submittedPick;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: loading
          ? const Center(
              child: Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(
                  color: AppColors.accent, strokeWidth: 2),
            ))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isNew)
                  Row(
                    children: [
                      const Text(
                        '어느 팀이 이길까요?',
                        style: TextStyle(color: AppColors.textMid, fontSize: 13),
                      ),
                      const Spacer(),
                      if (_fmt(remaining).isNotEmpty)
                        Text(
                          _fmt(remaining),
                          style: const TextStyle(
                            color: AppColors.textLow,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                        child: _TeamPick(
                      team: match.team1,
                      selected: myPick == match.team1.code,
                      confirmed: submittedPick == match.team1.code,
                      onTap: () => onSelect(match.team1.code),
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _TeamPick(
                      team: match.team2,
                      selected: myPick == match.team2.code,
                      confirmed: submittedPick == match.team2.code,
                      onTap: () => onSelect(match.team2.code),
                    )),
                  ],
                ),
                const SizedBox(height: 8),
                if (isNew || hasChanged)
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: ElevatedButton(
                      onPressed: myPick == null || submitting ? null : onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: hasChanged
                            ? const Color(0xFFD97706)
                            : AppColors.accent,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.border,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              hasChanged ? '변경 확정' : '예측 확정',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.2)),
                    ),
                    child: const Center(
                      child: Text(
                        '✅ 예측 완료  |  다른 팀을 눌러 변경',
                        style: TextStyle(
                            color: AppColors.textMid, fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TeamPick extends StatelessWidget {
  final MatchTeam team;
  final bool selected;
  final bool confirmed;
  final VoidCallback onTap;

  const _TeamPick({
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
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.12) : const Color(0xFF161B30),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? c : AppColors.border,
              width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            _TeamLogo(imageUrl: team.imageUrl, size: 30),
            const SizedBox(height: 6),
            Text(team.code,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: selected ? c : AppColors.textMid)),
            if (selected) ...[
              const SizedBox(height: 6),
              Icon(
                confirmed ? Icons.check_circle : Icons.radio_button_checked,
                color: c,
                size: 16,
              ),
            ],
          ],
        ),
      ),
    );
  }
}


// ── 팀 비교 카드 (예정 경기) ───────────────────────────────────────────────────
class _TeamCompareCard extends StatelessWidget {
  final LckMatch match;
  final List<Standing> standings;
  final List<LckMatch> allMatches;

  const _TeamCompareCard({
    required this.match,
    required this.standings,
    required this.allMatches,
  });

  List<bool> _recentForm(String teamCode) {
    final completed = allMatches
        .where((m) =>
            m.isCompleted &&
            m.leagueSlug == 'lck' &&
            (m.team1.code == teamCode || m.team2.code == teamCode))
        .toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    return completed.take(5).map((m) {
      if (m.team1.code == teamCode) return m.team1.outcome == 'win';
      return m.team2.outcome == 'win';
    }).toList();
  }

  // 게임 단위 승률 (매치 W/L이 아닌 게임 수 기반)
  double _gameWinRate(String teamCode) {
    final completed = allMatches.where((m) =>
        m.isCompleted &&
        m.leagueSlug == 'lck' &&
        (m.team1.code == teamCode || m.team2.code == teamCode));
    int gWins = 0, gTotal = 0;
    for (final m in completed) {
      if (m.team1.code == teamCode) {
        gWins += m.team1.gameWins;
        gTotal += m.team1.gameWins + m.team2.gameWins;
      } else {
        gWins += m.team2.gameWins;
        gTotal += m.team1.gameWins + m.team2.gameWins;
      }
    }
    return gTotal > 0 ? gWins / gTotal : 0.0;
  }

  // 연속 승패 스트릭
  String _streak(String teamCode) {
    final form = _recentForm(teamCode);
    if (form.isEmpty) return '';
    int count = 1;
    final first = form[0];
    for (int i = 1; i < form.length; i++) {
      if (form[i] == first) count++;
      else break;
    }
    return first ? '${count}연승' : '${count}연패';
  }

  @override
  Widget build(BuildContext context) {
    if (standings.isEmpty) return const SizedBox.shrink();

    final t1 = match.team1;
    final t2 = match.team2;
    final s1 = standings.firstWhere((s) => s.teamCode == t1.code,
        orElse: () => Standing(
            rank: 0, teamName: t1.name, teamCode: t1.code,
            imageUrl: '', wins: t1.wins, losses: t1.losses));
    final s2 = standings.firstWhere((s) => s.teamCode == t2.code,
        orElse: () => Standing(
            rank: 0, teamName: t2.name, teamCode: t2.code,
            imageUrl: '', wins: t2.wins, losses: t2.losses));

    final form1 = _recentForm(t1.code);
    final form2 = _recentForm(t2.code);
    final wr1 = s1.wins + s1.losses > 0 ? s1.wins / (s1.wins + s1.losses) : 0.0;
    final wr2 = s2.wins + s2.losses > 0 ? s2.wins / (s2.wins + s2.losses) : 0.0;
    final gwr1 = _gameWinRate(t1.code);
    final gwr2 = _gameWinRate(t2.code);
    final streak1 = _streak(t1.code);
    final streak2 = _streak(t2.code);
    final c1 = teamColor(t1.code);
    final c2 = teamColor(t2.code);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                const Text('팀 미리보기',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textHigh)),
                const Spacer(),
                const Text('최근 5경기 기반',
                    style: TextStyle(color: AppColors.textLow, fontSize: 10)),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 16),
          // 팀 이름 + 순위 + W-L + 스트릭
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 팀1
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t1.code,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: c1)),
                      const SizedBox(height: 2),
                      Text(
                        s1.rank > 0
                            ? '${s1.rank}위  •  ${s1.wins}W-${s1.losses}L'
                            : '${s1.wins}W-${s1.losses}L',
                        style: const TextStyle(
                            color: AppColors.textMid, fontSize: 11),
                      ),
                      if (streak1.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(streak1,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: streak1.contains('승') ? AppColors.win : AppColors.lose,
                            )),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          for (int i = 0; i < form1.length; i++) ...[
                            if (i > 0) const SizedBox(width: 3),
                            _FormBadge(isWin: form1[i]),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // VS
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: SizedBox(
                    width: 48,
                    child: Center(
                      child: Text('VS',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: AppColors.textLow)),
                    ),
                  ),
                ),
                // 팀2
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(t2.code,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                              color: c2)),
                      const SizedBox(height: 2),
                      Text(
                        s2.rank > 0
                            ? '${s2.wins}W-${s2.losses}L  •  ${s2.rank}위'
                            : '${s2.wins}W-${s2.losses}L',
                        style: const TextStyle(
                            color: AppColors.textMid, fontSize: 11),
                      ),
                      if (streak2.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(streak2,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: streak2.contains('승') ? AppColors.win : AppColors.lose,
                            )),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (int i = 0; i < form2.length; i++) ...[
                            if (i > 0) const SizedBox(width: 3),
                            _FormBadge(isWin: form2[i]),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.border),
          // 매치 승률
          _StatBarRow(
            label: '매치 승률',
            leftVal: wr1 > 0 ? '${(wr1 * 100).round()}%' : '-',
            rightVal: wr2 > 0 ? '${(wr2 * 100).round()}%' : '-',
            leftFrac: (wr1 + wr2 > 0) ? wr1 / (wr1 + wr2) : 0.5,
            c1: c1,
            c2: c2,
            leftHigher: wr1 >= wr2,
          ),
          const SizedBox(height: 10),
          // 게임 승률
          if (gwr1 > 0 || gwr2 > 0)
            _StatBarRow(
              label: '게임 승률',
              leftVal: gwr1 > 0 ? '${(gwr1 * 100).round()}%' : '-',
              rightVal: gwr2 > 0 ? '${(gwr2 * 100).round()}%' : '-',
              leftFrac: (gwr1 + gwr2 > 0) ? gwr1 / (gwr1 + gwr2) : 0.5,
              c1: c1,
              c2: c2,
              leftHigher: gwr1 >= gwr2,
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// 수치 + 프로그레스 바 한 줄
class _StatBarRow extends StatelessWidget {
  final String label;
  final String leftVal;
  final String rightVal;
  final double leftFrac; // 0.0~1.0
  final Color c1;
  final Color c2;
  final bool leftHigher;

  const _StatBarRow({
    required this.label,
    required this.leftVal,
    required this.rightVal,
    required this.leftFrac,
    required this.c1,
    required this.c2,
    required this.leftHigher,
  });

  @override
  Widget build(BuildContext context) {
    final rightFrac = 1.0 - leftFrac;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Text(leftVal,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: leftHigher ? c1 : AppColors.textMid)),
              const Spacer(),
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textLow, fontSize: 11)),
              const Spacer(),
              Text(rightVal,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: !leftHigher ? c2 : AppColors.textMid)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 4,
              child: Row(
                children: [
                  Expanded(
                    flex: (leftFrac * 100).round().clamp(1, 99),
                    child: Container(color: c1.withValues(alpha: leftHigher ? 1.0 : 0.35)),
                  ),
                  Expanded(
                    flex: (rightFrac * 100).round().clamp(1, 99),
                    child: Container(color: c2.withValues(alpha: !leftHigher ? 1.0 : 0.35)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormBadge extends StatelessWidget {
  final bool isWin;
  const _FormBadge({required this.isWin});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: isWin
            ? AppColors.win.withValues(alpha: 0.15)
            : AppColors.lose.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: isWin
              ? AppColors.win.withValues(alpha: 0.4)
              : AppColors.lose.withValues(alpha: 0.4),
        ),
      ),
      child: Center(
        child: Text(
          isWin ? 'W' : 'L',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isWin ? AppColors.win : AppColors.lose,
          ),
        ),
      ),
    );
  }
}

// ── 라이브 배너 ───────────────────────────────────────────────────────────────
class _LiveBanner extends StatelessWidget {
  const _LiveBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.live.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.live.withValues(alpha: 0.3)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.circle, color: AppColors.live, size: 10),
          SizedBox(width: 8),
          Text(
            '경기가 진행 중입니다',
            style: TextStyle(
                color: AppColors.live,
                fontWeight: FontWeight.w600,
                fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ── 내 예측 표시 (라이브) ──────────────────────────────────────────────────────
class _MyPickBadge extends StatelessWidget {
  final String teamCode;
  final LckMatch match;
  const _MyPickBadge({required this.teamCode, required this.match});

  @override
  Widget build(BuildContext context) {
    final c = teamColor(teamCode);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.how_to_vote_outlined, size: 18, color: AppColors.textMid),
          const SizedBox(width: 8),
          const Text('내 예측: ', style: TextStyle(color: AppColors.textMid, fontSize: 13)),
          Text(teamCode,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }
}

// ── 결과 카드 ─────────────────────────────────────────────────────────────────
class _MyResultCard extends StatelessWidget {
  final LckMatch match;
  final String? myPick;
  const _MyResultCard({required this.match, this.myPick});

  @override
  Widget build(BuildContext context) {
    if (myPick == null) return const SizedBox.shrink();
    final winner = match.team1.outcome == 'win' ? match.team1.code : match.team2.code;
    final correct = myPick == winner;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: correct
            ? AppColors.win.withValues(alpha: 0.07)
            : AppColors.lose.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: correct
              ? AppColors.win.withValues(alpha: 0.3)
              : AppColors.lose.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(
            correct ? '✅' : '❌',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 10),
          Text(
            correct
                ? '적중! ($myPick 예측)'
                : '불일치  (예측: $myPick  /  실제: $winner)',
            style: TextStyle(
              color: correct ? AppColors.win : AppColors.lose,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 세트별 결과 (탭) ─────────────────────────────────────────────────────────
class _GameByGameCard extends StatefulWidget {
  final LckMatch match;
  final MatchDetail detail;
  const _GameByGameCard({required this.match, required this.detail});

  @override
  State<_GameByGameCard> createState() => _GameByGameCardState();
}

class _GameByGameCardState extends State<_GameByGameCard> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final games = widget.detail.games;
    if (games.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 탭 바 — 실제 진행된 세트만 표시
          Row(
            children: [
              for (int i = 0; i < games.length; i++)
                Expanded(
                  child: _SetTab(
                    label: '${games[i].number}세트',
                    active: _tab == i,
                    onTap: () => setState(() => _tab = i),
                  ),
                ),
            ],
          ),
          const Divider(height: 1, color: AppColors.border),
          _GameSetView(game: games[_tab.clamp(0, games.length - 1)], match: widget.match),
        ],
      ),
    );
  }
}

class _SetTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SetTab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? AppColors.accent : AppColors.textLow,
            ),
          ),
        ),
      ),
    );
  }
}

class _GameSetView extends StatelessWidget {
  final GameDetail game;
  final LckMatch match;
  const _GameSetView({required this.game, required this.match});

  String _fmtDuration(int secs) {
    final m = (secs ~/ 60).toString().padLeft(2, '0');
    final s = (secs % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _fmtGold(int g) {
    if (g >= 1000) return '${(g / 1000).toStringAsFixed(1)}K';
    return '$g';
  }

  @override
  Widget build(BuildContext context) {
    // 블루팀 왼쪽, 레드팀 오른쪽
    final team1IsBlue = game.team1IsBlue ?? true;
    final tL = team1IsBlue ? match.team1 : match.team2; // 왼쪽(블루)
    final tR = team1IsBlue ? match.team2 : match.team1; // 오른쪽(레드)
    final sL = team1IsBlue ? game.team1Stats : game.team2Stats;
    final sR = team1IsBlue ? game.team2Stats : game.team1Stats;
    final bansL = team1IsBlue ? game.team1Bans : game.team2Bans;
    final bansR = team1IsBlue ? game.team2Bans : game.team1Bans;
    // 하위 호환용 alias
    final t1 = tL; final t2 = tR;
    final isT1Win = game.winnerCode == tL.code;
    final isT2Win = game.winnerCode == tR.code;
    final c1 = teamColor(tL.code);
    final c2 = teamColor(tR.code);
    final s1 = sL;
    final s2 = sR;
    final hasStats = s1 != null && s2 != null;
    final patch = game.patchVersion;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더: 팀 + 킬 + 시간 ──
          Row(
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _TeamLogo(imageUrl: t1.imageUrl, size: 36),
                    const SizedBox(width: 6),
                    Text(t1.code, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isT1Win ? c1 : AppColors.textMid)),
                    if (isT1Win) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.win.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                        child: const Text('WIN', style: TextStyle(color: AppColors.win, fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasStats) ...[
                Text('${s1.kills}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 26, color: isT1Win ? c1 : AppColors.textHigh)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      const Icon(Icons.timer_outlined, size: 12, color: AppColors.textLow),
                      if (game.durationSeconds != null)
                        Text(_fmtDuration(game.durationSeconds!),
                            style: const TextStyle(color: AppColors.textMid, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Text('${s2.kills}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 26, color: isT2Win ? c2 : AppColors.textHigh)),
              ] else if (game.winnerCode != null) ...[
                Text(game.winnerCode!, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: teamColor(game.winnerCode!))),
              ] else ...[
                const Text('스탯 없음', style: TextStyle(color: AppColors.textLow, fontSize: 11)),
              ],
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (isT2Win) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.win.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(3)),
                        child: const Text('WIN', style: TextStyle(color: AppColors.win, fontSize: 8, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(t2.code, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isT2Win ? c2 : AppColors.textMid)),
                    const SizedBox(width: 6),
                    _TeamLogo(imageUrl: t2.imageUrl, size: 36),
                  ],
                ),
              ),
            ],
          ),

          if (hasStats) ...[
            // ── 밴 ──
            if (bansL.isNotEmpty || bansR.isNotEmpty) ...[
              const SizedBox(height: 12),
              _ChampionPickRow(picks1: bansL, picks2: bansR, patch: patch, label: 'Bans', banned: true),
            ],

            // ── 챔피언 픽 ──
            if (s1.picks.isNotEmpty || s2.picks.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ChampionPickRow(picks1: s1.picks, picks2: s2.picks, patch: patch, label: 'Picks'),
            ],

            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),

            // KDA
            _GsRow(
              label: 'KDA',
              left: '${s1.kills} / ${s1.deaths} / ${s1.assists}',
              right: '${s2.kills} / ${s2.deaths} / ${s2.assists}',
              c1: c1, c2: c2,
              leftHigher: (s1.kills + s1.assists) >= (s2.kills + s2.assists),
            ),
            const SizedBox(height: 10),

            // Gold
            _GsBar(
              label: 'Gold',
              left: _fmtGold(s1.gold), right: _fmtGold(s2.gold),
              frac: s1.gold + s2.gold > 0 ? s1.gold / (s1.gold + s2.gold) : 0.5,
              c1: c1, c2: c2,
            ),
            const SizedBox(height: 10),

            // Towers
            _TowerBar(l: s1.towers, r: s2.towers, c1: c1, c2: c2),
            const SizedBox(height: 8),

            // Void Grubs
            _GsRow(
              label: 'Void Grubs',
              left: s1.voidGrubs > 0 ? '${s1.voidGrubs}' : '-',
              right: s2.voidGrubs > 0 ? '${s2.voidGrubs}' : '-',
              c1: c1, c2: c2,
              leftHigher: s1.voidGrubs >= s2.voidGrubs,
            ),
            const SizedBox(height: 8),

            // Heralds
            _GsRow(
              label: 'Heralds',
              left: s1.heralds > 0 ? '${s1.heralds}' : '-',
              right: s2.heralds > 0 ? '${s2.heralds}' : '-',
              c1: c1, c2: c2,
              leftHigher: s1.heralds >= s2.heralds,
            ),
            const SizedBox(height: 8),

            // Dragons (type icons)
            _DragonRow(
              label: 'Dragons',
              left: s1.dragonTypes.where((d) => d != 'elder').toList(),
              right: s2.dragonTypes.where((d) => d != 'elder').toList(),
            ),
            const SizedBox(height: 8),

            // Elders
            _GsRow(
              label: 'Elders',
              left: s1.elders > 0 ? '${s1.elders}' : '-',
              right: s2.elders > 0 ? '${s2.elders}' : '-',
              c1: c1, c2: c2,
              leftHigher: s1.elders >= s2.elders,
            ),
            const SizedBox(height: 8),

            // Barons
            _GsRow(
              label: 'Barons',
              left: s1.barons > 0 ? '${s1.barons}' : '-',
              right: s2.barons > 0 ? '${s2.barons}' : '-',
              c1: c1, c2: c2,
              leftHigher: s1.barons >= s2.barons,
            ),
          ],
        ],
      ),
    );
  }
}

// 챔피언 픽/밴 줄
class _ChampionPickRow extends StatelessWidget {
  final List<String> picks1;
  final List<String> picks2;
  final String? patch;
  final String label;
  final bool banned;

  const _ChampionPickRow({
    required this.picks1, required this.picks2,
    this.patch, required this.label, this.banned = false,
  });

  String _url(String champion) {
    // patch like "16.9.771.8052" → DDragon needs "16.9.1"
    String v = '16.9.1';
    if (patch?.isNotEmpty == true) {
      final parts = patch!.trim().split('.');
      if (parts.length >= 2) {
        v = '${parts[0]}.${parts[1]}.1';
      }
    }
    return 'https://ddragon.leagueoflegends.com/cdn/$v/img/champion/$champion.png';
  }

  Widget _icon(String champ) {
    return Container(
      width: 26, height: 26,
      margin: const EdgeInsets.symmetric(horizontal: 1.0),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              _url(champ),
              width: 26, height: 26, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 26, height: 26,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.shield_outlined, size: 12, color: AppColors.textLow),
              ),
            ),
          ),
          if (banned)
            Positioned.fill(
              child: CustomPaint(painter: _BanXPainter()),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 팀1 픽 (왼쪽 정렬)
        Expanded(
          child: Row(
            children: picks1.take(5).map(_icon).toList(),
          ),
        ),
        SizedBox(
          width: 44,
          child: Center(
            child: Text(label, style: const TextStyle(color: AppColors.textLow, fontSize: 10)),
          ),
        ),
        // 팀2 픽 (오른쪽 정렬)
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: picks2.take(5).map(_icon).toList(),
          ),
        ),
      ],
    );
  }
}

class _BanXPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xCCFF3333)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(2, 2), Offset(size.width - 2, size.height - 2), paint);
    canvas.drawLine(Offset(size.width - 2, 2), Offset(2, size.height - 2), paint);
  }
  @override
  bool shouldRepaint(_) => false;
}

// 단순 좌/라벨/우 행
class _GsRow extends StatelessWidget {
  final String label;
  final String left;
  final String right;
  final Color c1;
  final Color c2;
  final bool leftHigher;

  const _GsRow({
    required this.label, required this.left, required this.right,
    required this.c1, required this.c2, required this.leftHigher,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(left,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                  color: leftHigher ? c1 : AppColors.textMid)),
        ),
        Expanded(child: Center(child: Text(label, style: const TextStyle(color: AppColors.textLow, fontSize: 11)))),
        SizedBox(
          width: 90,
          child: Text(right, textAlign: TextAlign.end,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13,
                  color: !leftHigher ? c2 : AppColors.textMid)),
        ),
      ],
    );
  }
}

// 프로그레스 바 행
class _GsBar extends StatelessWidget {
  final String label;
  final String left;
  final String right;
  final double frac;
  final Color c1;
  final Color c2;

  const _GsBar({
    required this.label, required this.left, required this.right,
    required this.frac, required this.c1, required this.c2,
  });

  @override
  Widget build(BuildContext context) {
    final rf = 1 - frac;
    return Column(
      children: [
        Row(
          children: [
            SizedBox(width: 90, child: Text(left, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textHigh))),
            Expanded(child: Center(child: Text(label, style: const TextStyle(color: AppColors.textLow, fontSize: 11)))),
            SizedBox(width: 90, child: Text(right, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textHigh))),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 4,
            child: Row(
              children: [
                Expanded(flex: (frac * 100).round().clamp(1, 99), child: Container(color: c1)),
                Expanded(flex: (rf * 100).round().clamp(1, 99), child: Container(color: c2)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// 타워 바 — 중앙에서 바깥쪽으로 채워지는 방식 (각 팀 최대 11칸, 총 22칸)
class _TowerBar extends StatelessWidget {
  final int l, r;
  final Color c1, c2;
  static const perSide = 11;
  static const total = perSide * 2;

  const _TowerBar({required this.l, required this.r, required this.c1, required this.c2});

  @override
  Widget build(BuildContext context) {
    final slots = List<Color>.filled(total, AppColors.border);
    // 팀1: 중앙(index 10)에서 왼쪽(0) 방향으로 채움
    for (int i = 0; i < l.clamp(0, perSide); i++) {
      slots[perSide - 1 - i] = c1;
    }
    // 팀2: 중앙(index 11)에서 오른쪽(21) 방향으로 채움
    for (int i = 0; i < r.clamp(0, perSide); i++) {
      slots[perSide + i] = c2;
    }

    return Row(
      children: [
        SizedBox(width: 90, child: Text('$l', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c1))),
        Expanded(
          child: Column(
            children: [
              const Text('Towers', style: TextStyle(color: AppColors.textLow, fontSize: 10)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < total; i++)
                    Container(
                      width: 5, height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 0.5),
                      decoration: BoxDecoration(color: slots[i], borderRadius: BorderRadius.circular(1)),
                    ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(width: 90, child: Text('$r', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: c2))),
      ],
    );
  }
}

// 드래곤 타입별 아이콘 표시
class _DragonRow extends StatelessWidget {
  final String label;
  final List<String> left;
  final List<String> right;

  const _DragonRow({required this.label, required this.left, required this.right});

  Color _color(String t) {
    switch (t) {
      case 'fire': case 'infernal': return const Color(0xFFFF6B35);
      case 'earth': case 'mountain': return const Color(0xFF9B7B5B);
      case 'water': case 'ocean': return const Color(0xFF4A9EDE);
      case 'wind': case 'air': case 'cloud': return const Color(0xFF6EC97A);
      case 'hextech': return const Color(0xFF00D4FF);
      case 'chemtech': return const Color(0xFF5AB55A);
      default: return AppColors.textLow;
    }
  }

  IconData _iconData(String t) {
    switch (t) {
      case 'fire': case 'infernal': return Icons.local_fire_department;
      case 'earth': case 'mountain': return Icons.terrain;
      case 'water': case 'ocean': return Icons.water_drop;
      case 'wind': case 'air': case 'cloud': return Icons.air;
      case 'hextech': return Icons.bolt;
      case 'chemtech': return Icons.science;
      default: return Icons.circle;
    }
  }

  Widget _icon(String t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: Icon(_iconData(t), size: 14, color: _color(t)),
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Row(children: [
            Text(left.isEmpty ? '-' : '${left.length}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: left.isNotEmpty ? _color(left.first) : AppColors.textMid)),
            const SizedBox(width: 4),
            ...left.take(4).map(_icon),
          ]),
        ),
        Expanded(child: Center(child: Text(label, style: const TextStyle(color: AppColors.textLow, fontSize: 11)))),
        SizedBox(
          width: 90,
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            ...right.take(4).map(_icon),
            const SizedBox(width: 4),
            Text(right.isEmpty ? '-' : '${right.length}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: right.isNotEmpty ? _color(right.first) : AppColors.textMid)),
          ]),
        ),
      ],
    );
  }
}

// ── 팀 로고 ───────────────────────────────────────────────────────────────────
class _TeamLogo extends StatelessWidget {
  final String imageUrl;
  final double size;
  const _TeamLogo({required this.imageUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return SizedBox(width: size, height: size);
    }
    return Image.network(
      imageUrl,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
    );
  }
}
