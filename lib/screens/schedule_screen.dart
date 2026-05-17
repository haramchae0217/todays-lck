import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/lck_api_service.dart';
import '../services/prediction_service.dart';
import '../models/match.dart';
import '../providers/auth_provider.dart';
import '../widgets/match_card.dart';
import '../utils/team_utils.dart';

const _kAccent = Color(0xFF0891B2);
const _kLive = Color(0xFFEF4444);
const _kTextHigh = Color(0xFF0F172A);
const _kTextMid = Color(0xFF64748B);
const _kTextLow = Color(0xFF94A3B8);
const _kBorder = Color(0xFFE2E8F0);

final scheduleProvider = FutureProvider<List<LckMatch>>((ref) async {
  return LckApiService.instance.getSchedule();
});

abstract class _Item {}

class _DateHeader extends _Item {
  final DateTime date;
  final bool isToday;
  final bool isScrollTarget;
  _DateHeader(this.date, {required this.isToday, this.isScrollTarget = false});
}

class _MatchItem extends _Item {
  final LckMatch match;
  _MatchItem(this.match);
}

List<_Item> _buildItems(List<LckMatch> matches) {
  final sorted = [...matches]..sort((a, b) => a.startTime.compareTo(b.startTime));
  final now = DateTime.now();
  final todayStr = DateFormat('yyyy-MM-dd').format(now);
  final items = <_Item>[];
  String? lastDate;

  for (final match in sorted) {
    final dateKey = DateFormat('yyyy-MM-dd').format(match.startTime);
    if (dateKey != lastDate) {
      items.add(_DateHeader(match.startTime, isToday: dateKey == todayStr));
      lastDate = dateKey;
    }
    items.add(_MatchItem(match));
  }

  final hasToday = items.any((e) => e is _DateHeader && e.isToday);
  if (!hasToday) {
    final startOfToday = DateTime(now.year, now.month, now.day);
    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      if (item is _DateHeader && !item.date.isBefore(startOfToday)) {
        items[i] = _DateHeader(item.date, isToday: false, isScrollTarget: true);
        break;
      }
    }
  }

  return items;
}

class _LeagueTab {
  final String label;
  final String? slug;
  const _LeagueTab(this.label, this.slug);
}

const _leagueTabs = [
  _LeagueTab('전체', null),
  _LeagueTab('LCK', 'lck'),
  _LeagueTab('MSI', 'msi'),
  _LeagueTab('Worlds', 'worlds'),
  _LeagueTab('First Stand', 'first_stand'),
];

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  final _scrollController = ScrollController();
  final _targetKey = GlobalKey();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _selectedSlug;
  bool _scrolledToTarget = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTarget() {
    if (_scrolledToTarget) return;
    _scrolledToTarget = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _targetKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.1,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut);
      }
    });
  }

  void _resetScroll() {
    _scrolledToTarget = false;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  void _showPredictionSheet(BuildContext context, LckMatch match) {
    final user = ref.read(authStateProvider).valueOrNull;
    if (!match.isUpcoming && !match.isLive && !match.isCompleted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PredictionSheet(match: match, isLoggedIn: user != null),
    );
  }

  List<LckMatch> _filterMatches(List<LckMatch> matches) {
    return matches.where((m) {
      if (m.startTime.year != _selectedMonth.year ||
          m.startTime.month != _selectedMonth.month) return false;
      if (_selectedSlug != null) return m.leagueSlug == _selectedSlug;
      return true;
    }).toList();
  }

  void _changeMonth(int delta, List<DateTime> months) {
    final idx = months.indexWhere(
      (m) => m.year == _selectedMonth.year && m.month == _selectedMonth.month,
    );
    final next = idx + delta;
    if (next < 0 || next >= months.length) return;
    setState(() {
      _selectedMonth = months[next];
      _resetScroll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final schedule = ref.watch(scheduleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LCK 일정', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _resetScroll();
              ref.invalidate(scheduleProvider);
            },
          ),
        ],
      ),
      body: schedule.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _kAccent)),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (matches) {
          if (matches.isEmpty) return const Center(child: Text('경기 일정이 없습니다'));

          final monthSet = <String>{};
          final availableMonths = <DateTime>[];
          for (final m in matches) {
            final key = '${m.startTime.year}-${m.startTime.month}';
            if (monthSet.add(key)) {
              availableMonths.add(DateTime(m.startTime.year, m.startTime.month));
            }
          }
          availableMonths.sort((a, b) => a.compareTo(b));

          final hasSelected = availableMonths.any(
            (m) => m.year == _selectedMonth.year && m.month == _selectedMonth.month,
          );
          if (!hasSelected && availableMonths.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() => _selectedMonth = availableMonths.first);
            });
          }

          final selectedIdx = availableMonths.indexWhere(
            (m) => m.year == _selectedMonth.year && m.month == _selectedMonth.month,
          );
          final canGoPrev = selectedIdx > 0;
          final canGoNext = selectedIdx < availableMonths.length - 1;

          final filtered = _filterMatches(matches);
          final items = _buildItems(filtered);

          final hasTarget =
              items.any((e) => e is _DateHeader && (e.isToday || e.isScrollTarget));
          if (hasTarget) _scrollToTarget();

          return Column(
            children: [
              // ── 월 네비게이터 ──
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(bottom: BorderSide(color: _kBorder)),
                ),
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: canGoPrev
                              ? () => _changeMonth(-1, availableMonths)
                              : null,
                          icon: Icon(
                            Icons.chevron_left,
                            color: canGoPrev ? _kTextMid : _kBorder,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('yyyy년 M월', 'ko').format(_selectedMonth),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _kTextHigh,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          onPressed: canGoNext
                              ? () => _changeMonth(1, availableMonths)
                              : null,
                          icon: Icon(
                            Icons.chevron_right,
                            color: canGoNext ? _kTextMid : _kBorder,
                            size: 26,
                          ),
                        ),
                      ],
                    ),
                    // ── 리그 필터 탭 ──
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
                      child: Row(
                        children: _leagueTabs.map((tab) {
                          final isSelected = _selectedSlug == tab.slug;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _selectedSlug = tab.slug;
                                _resetScroll();
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _kAccent.withValues(alpha: 0.10)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected ? _kAccent : _kBorder,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  tab.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected ? _kAccent : _kTextMid,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              // ── 경기 리스트 ──
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          '이 달 경기 일정이 없습니다',
                          style: TextStyle(color: _kTextLow),
                        ),
                      )
                    : RefreshIndicator(
                        color: _kAccent,
                        onRefresh: () async {
                          _resetScroll();
                          return ref.refresh(scheduleProvider.future);
                        },
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: items.map((item) {
                              if (item is _DateHeader) {
                                final isTarget = item.isToday || item.isScrollTarget;
                                return _DateHeaderWidget(
                                  key: isTarget ? _targetKey : null,
                                  date: item.date,
                                  isToday: item.isToday,
                                );
                              }
                              final m = (item as _MatchItem).match;
                              return MatchCard(
                                match: m,
                                onTap: () => _showPredictionSheet(context, m),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── prediction bottom sheet ──────────────────────────────────────────────────
class _PredictionSheet extends StatefulWidget {
  final LckMatch match;
  final bool isLoggedIn;
  const _PredictionSheet({required this.match, required this.isLoggedIn});

  @override
  State<_PredictionSheet> createState() => _PredictionSheetState();
}

class _PredictionSheetState extends State<_PredictionSheet> {
  String? _submittedPick;
  String? _myPick;
  bool _loading = true;
  bool _submitting = false;
  ({int team1Count, int team2Count})? _stats;

  bool get _isNew => _submittedPick == null;
  bool get _hasChanged => _submittedPick != null && _myPick != _submittedPick;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final match = widget.match;
    final futures = <Future>[
      if (widget.isLoggedIn) PredictionService.instance.getMyPrediction(match.id),
      PredictionService.instance.getMatchStats(
        matchId: match.id,
        team1Code: match.team1.code,
        team2Code: match.team2.code,
      ),
    ];
    final results = await Future.wait(futures);
    if (!mounted) return;
    setState(() {
      if (widget.isLoggedIn) {
        _submittedPick = results[0] as String?;
        _myPick = results[0] as String?;
        _stats = results[1] as ({int team1Count, int team2Count});
      } else {
        _stats = results[0] as ({int team1Count, int team2Count});
      }
      _loading = false;
    });
  }

  void _select(String teamCode) {
    if (!widget.isLoggedIn || _submitting) return;
    setState(() => _myPick = teamCode);
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
      if (mounted) {
        setState(() { _submittedPick = _myPick; _submitting = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isNew ? '${_myPick!} 예측 완료!' : '${_myPick!}로 변경 완료!'),
            backgroundColor: _kAccent,
          ),
        );
        Navigator.pop(context);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: _kBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            match.isCompleted ? '경기 결과' : match.isLive ? '경기 진행 중 🔴' : '승부예측',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _kTextHigh,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${match.leagueName}  ${match.blockName}',
            style: const TextStyle(color: _kTextLow, fontSize: 12),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const CircularProgressIndicator(color: _kAccent)
          else if (!widget.isLoggedIn)
            const Text('로그인 후 예측에 참여할 수 있습니다.',
                style: TextStyle(color: _kTextMid))
          else if (match.isCompleted)
            _ResultView(match: match, myPick: _myPick)
          else if (match.isLive)
            _LiveView(match: match, myPick: _myPick)
          else ...[
            if (_isNew) ...[
              const Text(
                '어느 팀이 이길까요?',
                style: TextStyle(color: _kTextMid, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ] else
              const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: _TeamSelectButton(
                  team: match.team1,
                  selected: _myPick == match.team1.code,
                  isConfirmed: _submittedPick == match.team1.code,
                  onTap: () => _select(match.team1.code),
                )),
                const SizedBox(width: 12),
                Expanded(child: _TeamSelectButton(
                  team: match.team2,
                  selected: _myPick == match.team2.code,
                  isConfirmed: _submittedPick == match.team2.code,
                  onTap: () => _select(match.team2.code),
                )),
              ],
            ),
            const SizedBox(height: 16),
            if (_isNew || _hasChanged)
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _myPick == null || _submitting ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasChanged
                        ? const Color(0xFFD97706)
                        : _kAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _kBorder,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          _hasChanged ? '변경 확정' : '예측 확정',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _kAccent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
                ),
                child: const Center(
                  child: Text('✅ 예측 완료  |  다른 팀을 눌러 변경할 수 있어요.',
                      style: TextStyle(color: _kTextMid, fontSize: 12)),
                ),
              ),
          ],
          if (!_loading && _stats != null && (_stats!.team1Count + _stats!.team2Count) > 0) ...[
            const SizedBox(height: 20),
            _PredictionStatsBar(
              team1Code: match.team1.code,
              team2Code: match.team2.code,
              team1Count: _stats!.team1Count,
              team2Count: _stats!.team2Count,
            ),
          ],
        ],
      ),
    );
  }
}

class _TeamSelectButton extends StatelessWidget {
  final MatchTeam team;
  final bool selected;
  final bool isConfirmed;
  final VoidCallback onTap;
  const _TeamSelectButton({
    required this.team,
    required this.selected,
    required this.isConfirmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color tc = teamColor(team.code);
    final Color borderColor = selected ? tc : _kBorder;
    final Color bgColor = selected ? tc.withValues(alpha: 0.08) : const Color(0xFFF8FAFC);
    final Color textColor = selected ? tc : _kTextMid;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 22),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        child: Column(
          children: [
            Text(team.code,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 24, color: textColor)),
            if (selected) ...[
              const SizedBox(height: 8),
              Icon(
                isConfirmed ? Icons.check_circle : Icons.radio_button_checked,
                color: tc,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final LckMatch match;
  final String? myPick;
  const _ResultView({required this.match, this.myPick});

  @override
  Widget build(BuildContext context) {
    final winner = match.team1.outcome == 'win' ? match.team1.code : match.team2.code;
    final correct = myPick != null && myPick == winner;
    return Column(
      children: [
        Text('${match.team1.gameWins} : ${match.team2.gameWins}',
            style: const TextStyle(
                fontSize: 32, fontWeight: FontWeight.bold, color: _kTextHigh, letterSpacing: 4)),
        const SizedBox(height: 4),
        Text('${match.team1.code} vs ${match.team2.code}',
            style: const TextStyle(color: _kTextLow, fontSize: 13)),
        if (myPick != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: correct
                  ? const Color(0xFF059669).withValues(alpha: 0.08)
                  : const Color(0xFFEF4444).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: correct
                    ? const Color(0xFF059669).withValues(alpha: 0.3)
                    : const Color(0xFFEF4444).withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              correct ? '✅ 적중! ($myPick)' : '❌ 불일치 (예측: $myPick / 실제: $winner)',
              style: TextStyle(
                  color: correct ? const Color(0xFF059669) : const Color(0xFFEF4444),
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }
}

class _LiveView extends StatelessWidget {
  final LckMatch match;
  final String? myPick;
  const _LiveView({required this.match, this.myPick});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('🔴 경기가 진행 중입니다',
            style: TextStyle(color: _kLive, fontWeight: FontWeight.w600)),
        if (myPick != null) ...[
          const SizedBox(height: 12),
          Text('예측: $myPick', style: const TextStyle(color: _kTextMid)),
        ],
      ],
    );
  }
}

// ── 예측 통계 바 ──────────────────────────────────────────────────────────────
class _PredictionStatsBar extends StatelessWidget {
  final String team1Code;
  final String team2Code;
  final int team1Count;
  final int team2Count;

  const _PredictionStatsBar({
    required this.team1Code,
    required this.team2Code,
    required this.team1Count,
    required this.team2Count,
  });

  @override
  Widget build(BuildContext context) {
    final total = team1Count + team2Count;
    final t1Pct = total > 0 ? (team1Count / total) : 0.5;
    final t2Pct = 1.0 - t1Pct;
    final c1 = teamColor(team1Code);
    final c2 = teamColor(team2Code);

    return Column(
      children: [
        Row(
          children: [
            Text(
              team1Code,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c1),
            ),
            const SizedBox(width: 5),
            Text(
              '${(t1Pct * 100).round()}%',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c1),
            ),
            const Spacer(),
            Text(
              '총 $total명 참여',
              style: const TextStyle(fontSize: 11, color: _kTextLow),
            ),
            const Spacer(),
            Text(
              '${(t2Pct * 100).round()}%',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c2),
            ),
            const SizedBox(width: 5),
            Text(
              team2Code,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c2),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                if (t1Pct > 0)
                  Expanded(
                    flex: (t1Pct * 100).round(),
                    child: Container(color: c1),
                  ),
                if (t2Pct > 0)
                  Expanded(
                    flex: (t2Pct * 100).round(),
                    child: Container(color: c2),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── date header widget ────────────────────────────────────────────────────────
class _DateHeaderWidget extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  const _DateHeaderWidget({super.key, required this.date, required this.isToday});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Row(
        children: [
          if (isToday)
            Container(
              width: 3,
              height: 14,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _kAccent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Text(
            DateFormat('d일 (E)', 'ko').format(date),
            style: TextStyle(
              fontSize: 13,
              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
              color: isToday ? _kAccent : _kTextLow,
            ),
          ),
          if (isToday) ...[
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: _kAccent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '오늘',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
