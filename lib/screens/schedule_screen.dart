import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../constants/colors.dart';
import '../services/lck_api_service.dart';
import '../models/match.dart';
import '../widgets/match_card.dart';
import 'match_detail_screen.dart';

// ── Notifier: 페이지네이션 상태 관리 ──────────────────────────────────────────
class ScheduleState {
  final List<LckMatch> matches;
  final String? olderToken;
  final bool loadingMore;
  const ScheduleState({
    required this.matches,
    this.olderToken,
    this.loadingMore = false,
  });
  ScheduleState copyWith({
    List<LckMatch>? matches,
    String? olderToken,
    bool clearOlderToken = false,
    bool? loadingMore,
  }) =>
      ScheduleState(
        matches: matches ?? this.matches,
        olderToken: clearOlderToken ? null : (olderToken ?? this.olderToken),
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

// API 데이터에서 현재 시즌 시작 이전 LCK 경기를 LCK Cup으로 재분류
List<LckMatch> _reclassifyCup(List<LckMatch> matches) {
  final cupCutoff = DateTime.utc(DateTime.now().year, 4, 1);
  return matches.map((m) {
    if (m.leagueSlug == 'lck' && m.startTime.toUtc().isBefore(cupCutoff)) {
      return LckMatch(
        id: m.id, startTime: m.startTime, state: m.state,
        blockName: m.blockName, team1: m.team1, team2: m.team2,
        bestOf: m.bestOf, hasVod: m.hasVod,
        leagueName: 'LCK Cup', leagueSlug: 'lck_cup',
      );
    }
    return m;
  }).toList();
}

class ScheduleNotifier extends AsyncNotifier<ScheduleState> {
  @override
  Future<ScheduleState> build() async {
    final r = await LckApiService.instance.getSchedule();
    var allMatches = r.matches;
    var olderToken = r.olderToken;

    // 2026 LCK 정규시즌 시작일(4/1)까지 자동 페이지네이션 (최대 5페이지)
    final seasonStart = DateTime.utc(DateTime.now().year, 4, 1);
    for (int i = 0; i < 5 && olderToken != null; i++) {
      final earliest = allMatches.isEmpty
          ? null
          : allMatches.map((m) => m.startTime).reduce((a, b) => a.isBefore(b) ? a : b);
      if (earliest != null && earliest.isBefore(seasonStart)) break;
      final older = await LckApiService.instance.getSchedule(pageToken: olderToken);
      if (older.matches.isEmpty) break;
      allMatches = [...allMatches, ...older.matches];
      olderToken = older.olderToken;
    }

    return ScheduleState(matches: _reclassifyCup(allMatches), olderToken: olderToken);
  }

  Future<void> loadOlder() async {
    final cur = state.valueOrNull;
    if (cur == null || cur.olderToken == null || cur.loadingMore) return;
    state = AsyncData(cur.copyWith(loadingMore: true));
    try {
      final r = await LckApiService.instance.getSchedule(pageToken: cur.olderToken);
      state = AsyncData(ScheduleState(
        matches: [...cur.matches, ..._reclassifyCup(r.matches)],
        olderToken: r.olderToken,
      ));
    } catch (_) {
      state = AsyncData(cur.copyWith(loadingMore: false));
    }
  }

  Future<void> refresh() async {
    LckApiService.instance.clearCache('getSchedule');
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build());
  }
}

final scheduleProvider =
    AsyncNotifierProvider<ScheduleNotifier, ScheduleState>(ScheduleNotifier.new);

final historicalScheduleProvider = FutureProvider.family<List<LckMatch>, int>((ref, year) {
  return LckApiService.instance.getLeaguepediaYearSchedule(year);
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
  _LeagueTab('LCK', 'lck'),
  _LeagueTab('LCK Cup', 'lck_cup'),
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
  static const _minYear = 2012;

  final _scrollController = ScrollController();
  final _targetKey = GlobalKey();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _selectedSlug;
  bool _scrolledToTarget = false;
  // Auto-snap: 연도별 첫 진입 시 1회만 실행, 현재 연도는 스킵
  int? _autoSnapDoneForYear = DateTime.now().year;

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

  void _openMatchDetail(BuildContext context, LckMatch match) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MatchDetailScreen(match: match)),
    );
  }

  List<LckMatch> _filterMatches(List<LckMatch> matches) {
    return matches.where((m) {
      if (m.startTime.year != _selectedMonth.year ||
          m.startTime.month != _selectedMonth.month) {
        return false;
      }
      if (_selectedSlug != null) return m.leagueSlug == _selectedSlug;
      return true;
    }).toList();
  }

  // 필터 선택 + 해당 리그의 가장 최근 달로 이동
  void _selectLeague(String? slug, List<LckMatch> allMatches) {
    if (slug == null || slug == _selectedSlug) {
      setState(() { _selectedSlug = null; _resetScroll(); });
      return;
    }
    DateTime? latest;
    for (final m in allMatches) {
      if (m.leagueSlug == slug) {
        final mm = DateTime(m.startTime.year, m.startTime.month);
        if (latest == null || mm.isAfter(latest)) latest = mm;
      }
    }
    setState(() {
      _selectedSlug = slug;
      if (latest != null) _selectedMonth = latest;
      _resetScroll();
    });
  }

  void _changeMonth(int delta) {
    final now = DateTime.now();
    final minDate = DateTime(_minYear, 1);
    final maxDate = DateTime(now.year, now.month);

    var year = _selectedMonth.year;
    var month = _selectedMonth.month + delta;
    if (month < 1) { month = 12; year--; }
    else if (month > 12) { month = 1; year++; }

    final next = DateTime(year, month);
    if (next.isBefore(minDate) || next.isAfter(maxDate)) return;

    final yearChanged = next.year != _selectedMonth.year;
    setState(() {
      _selectedMonth = next;
      if (yearChanged) _autoSnapDoneForYear = null; // 새 연도엔 snap 허용
      _resetScroll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final year = _selectedMonth.year;
    final isCurrent = year == DateTime.now().year;
    final schedule2026 = ref.watch(scheduleProvider);
    final scheduleHist = isCurrent ? null : ref.watch(historicalScheduleProvider(year));

    List<LckMatch> matches = [];
    bool isLoading = false;
    Object? error;
    ScheduleState? state2026;

    if (isCurrent) {
      schedule2026.when(
        loading: () { isLoading = true; },
        error: (e, _) { error = e; },
        data: (s) {
          state2026 = s;
          matches = s.matches;
        },
      );
    } else {
      scheduleHist!.when(
        loading: () { isLoading = true; },
        error: (e, _) { error = e; },
        data: (list) { matches = list; },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('LCK 일정', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _resetScroll();
              if (isCurrent) {
                ref.read(scheduleProvider.notifier).refresh();
              } else {
                ref.invalidate(historicalScheduleProvider(year));
              }
            },
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : error != null
              ? Center(child: Text('오류: $error'))
              : _buildContent(matches, context, state2026, isCurrent),
    );
  }

  Widget _buildContent(List<LckMatch> matches, BuildContext context, ScheduleState? state2026, bool is2026) {
    // Auto-snap: 연도 첫 진입 시 1회만 — 해당 달에 경기 없으면 데이터 있는 첫 달로 이동
    final monthsWithData = <int>{};
    for (final m in matches) {
      if (m.startTime.year == _selectedMonth.year) {
        monthsWithData.add(m.startTime.month);
      }
    }
    if (matches.isNotEmpty &&
        !monthsWithData.contains(_selectedMonth.month) &&
        _autoSnapDoneForYear != _selectedMonth.year) {
      final first = monthsWithData.isEmpty ? null : (monthsWithData.toList()..sort()).first;
      if (first != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _autoSnapDoneForYear = _selectedMonth.year;
              _selectedMonth = DateTime(_selectedMonth.year, first);
            });
          }
        });
      }
    }

    final now = DateTime.now();
    final canGoPrev = _selectedMonth.isAfter(DateTime(_minYear, 1)) ||
        (_selectedMonth.year == _minYear && _selectedMonth.month > 1);
    final canGoNext = _selectedMonth.year < now.year ||
        (_selectedMonth.year == now.year && _selectedMonth.month < now.month);

    final filtered = _filterMatches(matches);
    final items = _buildItems(filtered);

    final hasTarget =
        items.any((e) => e is _DateHeader && (e.isToday || e.isScrollTarget));
    if (hasTarget) _scrollToTarget();

    return Column(
      children: [
        // ── 헤더 (연도 + 월 네비게이터 + 리그 필터) ──
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0A0E1A),
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          padding: const EdgeInsets.fromLTRB(0, 6, 0, 0),
          child: Column(
            children: [
              // ── 연도 + 월 통합 네비게이터 ──
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: canGoPrev ? () => _changeMonth(-1) : null,
                    icon: Icon(
                      Icons.chevron_left,
                      color: canGoPrev ? AppColors.textMid : AppColors.border,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('yyyy년 M월', 'ko').format(_selectedMonth),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textHigh,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: canGoNext ? () => _changeMonth(1) : null,
                    icon: Icon(
                      Icons.chevron_right,
                      color: canGoNext ? AppColors.textMid : AppColors.border,
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
                        onTap: () => _selectLeague(isSelected ? null : tab.slug, matches),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accent.withValues(alpha: 0.15)
                                : const Color(0xFF111528),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? AppColors.accent : AppColors.border,
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
                              color: isSelected ? AppColors.accent : AppColors.textMid,
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
                    style: TextStyle(color: AppColors.textLow),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: () async {
                    _resetScroll();
                    if (is2026) {
                      await ref.read(scheduleProvider.notifier).refresh();
                    } else {
                      ref.invalidate(historicalScheduleProvider(_selectedMonth.year));
                    }
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...items.map((item) {
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
                            onTap: () => _openMatchDetail(context, m),
                          );
                        }),
                        // ── 이전 기간 더 보기 (2026년만) ──
                        if (is2026 && state2026?.olderToken != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: OutlinedButton.icon(
                              onPressed: state2026!.loadingMore
                                  ? null
                                  : () => ref
                                      .read(scheduleProvider.notifier)
                                      .loadOlder(),
                              icon: state2026.loadingMore
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.textMid))
                                  : const Icon(Icons.history,
                                      size: 16, color: AppColors.textMid),
                              label: Text(
                                state2026.loadingMore ? '불러오는 중...' : '이전 경기 더 보기',
                                style: const TextStyle(
                                    color: AppColors.textMid, fontSize: 13),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                      ],
                    ),
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
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          Text(
            DateFormat('d일 (E)', 'ko').format(date),
            style: TextStyle(
              fontSize: 13,
              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
              color: isToday ? AppColors.accent : AppColors.textLow,
            ),
          ),
          if (isToday) ...[
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.accent,
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
