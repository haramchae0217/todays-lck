import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/colors.dart';
import '../services/lck_api_service.dart';
import '../models/standing.dart';
import '../models/team.dart';
import 'team_detail_screen.dart';
import 'teams_screen.dart' show teamsProvider;
import '../utils/team_utils.dart';

const _headerStyle = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: AppColors.accent,
  letterSpacing: 0.3,
);

final standingsProvider = FutureProvider<List<Standing>>((ref) async {
  final results = await Future.wait([
    LckApiService.instance.getStandings(),
    LckApiService.instance.getTeamGameRecords(),
  ]);

  final standings = results[0] as List<Standing>;
  final gameRecords = results[1] as Map<String, ({int wins, int losses})>;

  final withDiff = standings
      .map((s) {
        final rec = gameRecords[s.teamCode];
        final gw = rec?.wins ?? 0;
        final gl = rec?.losses ?? 0;
        return s.copyWith(
          gameDiff: gw - gl,
          gameWins: gw,
          gameLosses: gl,
        );
      })
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

final historicalStandingsProvider =
    FutureProvider.family<Map<String, List<Standing>>, int>((ref, year) {
  return LckApiService.instance.getLeaguepediaStandings(year);
});

// 스플릿 표시 순서
const _splitOrder = ['Spring', 'Split 1', 'Summer', 'Split 2', 'Winter'];

List<String> _sortedSplits(Iterable<String> splits) {
  final list = splits.toList();
  list.sort((a, b) {
    final ai = _splitOrder.indexOf(a);
    final bi = _splitOrder.indexOf(b);
    if (ai == -1 && bi == -1) return a.compareTo(b);
    if (ai == -1) return 1;
    if (bi == -1) return -1;
    return ai.compareTo(bi);
  });
  return list;
}

class StandingsScreen extends ConsumerStatefulWidget {
  const StandingsScreen({super.key});

  @override
  ConsumerState<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends ConsumerState<StandingsScreen> {
  static const _minYear = 2012;

  int _selectedYear = DateTime.now().year;
  String? _selectedSplit;

  bool get _isCurrent => _selectedYear == DateTime.now().year;

  void _setYear(int year) {
    setState(() {
      _selectedYear = year;
      _selectedSplit = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxYear = DateTime.now().year;
    final canPrevYear = _selectedYear > _minYear;
    final canNextYear = _selectedYear < maxYear;

    return Scaffold(
      appBar: AppBar(
        title: const Text('LCK 순위', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_isCurrent) {
                ref.invalidate(standingsProvider);
              } else {
                ref.invalidate(historicalStandingsProvider(_selectedYear));
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── 연도 네비게이터 ──
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0A0E1A),
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: canPrevYear ? () => _setYear(_selectedYear - 1) : null,
                  icon: Icon(
                    Icons.chevron_left,
                    color: canPrevYear ? AppColors.textMid : AppColors.border,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$_selectedYear년',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textHigh,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: canNextYear ? () => _setYear(_selectedYear + 1) : null,
                  icon: Icon(
                    Icons.chevron_right,
                    color: canNextYear ? AppColors.textMid : AppColors.border,
                    size: 26,
                  ),
                ),
              ],
            ),
          ),
          // ── 내용 ──
          Expanded(
            child: _isCurrent ? _buildCurrent() : _buildHistorical(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrent() {
    final standings = ref.watch(standingsProvider);
    final teams = ref.watch(teamsProvider).valueOrNull ?? [];
    final teamMap = {for (final t in teams) t.code: t};

    return standings.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (list) => _buildTable(list, teamMap),
    );
  }

  Widget _buildHistorical() {
    final data = ref.watch(historicalStandingsProvider(_selectedYear));

    return data.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.accent)),
      error: (e, _) => Center(child: Text('오류: $e')),
      data: (splitMap) {
        if (splitMap.isEmpty) {
          return const Center(
            child: Text('데이터가 없습니다', style: TextStyle(color: AppColors.textLow)),
          );
        }

        final splits = _sortedSplits(splitMap.keys);
        // 처음 로드 시 마지막 스플릿으로 기본 설정
        if (_selectedSplit == null || !splits.contains(_selectedSplit)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedSplit = splits.last);
          });
        }

        final activeSplit = _selectedSplit ?? splits.last;
        final list = splitMap[activeSplit] ?? [];

        return Column(
          children: [
            // 스플릿 선택
            if (splits.length > 1)
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF0A0E1A),
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: splits.map((split) {
                    final isSelected = activeSplit == split;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedSplit = split),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.accent.withValues(alpha: 0.15)
                                : const Color(0xFF111528),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? AppColors.accent : AppColors.border,
                            ),
                          ),
                          child: Text(
                            split,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppColors.accent : AppColors.textMid,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            Expanded(child: _buildTable(list, {})),
          ],
        );
      },
    );
  }

  Widget _buildTable(List<Standing> list, Map<String, Team> teamMap) {
    if (list.isEmpty) {
      return const Center(
        child: Text('순위 정보가 없습니다', style: TextStyle(color: AppColors.textLow)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          color: AppColors.accent,
          onRefresh: () async {
            if (_isCurrent) {
              ref.invalidate(standingsProvider);
            } else {
              ref.invalidate(historicalStandingsProvider(_selectedYear));
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: constraints.maxHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF111528),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    children: [
                      const _TableHeader(),
                      const Divider(height: 1, thickness: 1, color: AppColors.border),
                      Expanded(
                        child: Column(
                          children: list.asMap().entries.map((e) => Expanded(
                            child: _StandingRow(
                              standing: e.value,
                              index: e.key,
                              team: teamMap[e.value.teamCode],
                              isLast: e.key == list.length - 1,
                            ),
                          )).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

const double _wRank = 26;
const double _wLogo = 28;
const double _wStat = 28;
const double _wSet  = 44;
const double _wDiff = 38;
const double _wRate = 40;

class _TableHeader extends StatelessWidget {
  const _TableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
      ),
      child: const Row(
        children: [
          SizedBox(width: _wRank, child: Text('#', style: _headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: 8),
          SizedBox(width: _wLogo),
          SizedBox(width: 8),
          Expanded(child: Text('팀', style: _headerStyle)),
          SizedBox(width: _wStat, child: Text('승', style: _headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: 6),
          SizedBox(width: _wStat, child: Text('패', style: _headerStyle, textAlign: TextAlign.center)),
          SizedBox(width: 6),
          SizedBox(width: _wSet, child: Text('세트', style: _headerStyle, textAlign: TextAlign.center)),
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
      1 => const Color(0xFFD97706),
      2 => const Color(0xFF64748B),
      3 => const Color(0xFF92400E),
      _ => AppColors.textLow,
    };
    final diffColor = standing.gameDiff > 0
        ? const Color(0xFF059669)
        : standing.gameDiff < 0
            ? const Color(0xFFEF4444)
            : AppColors.textLow;

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: team == null
                ? null
                : () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team!))),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: index.isEven ? const Color(0xFF111528) : const Color(0xFF161B30),
                borderRadius: isLast
                    ? const BorderRadius.vertical(bottom: Radius.circular(14))
                    : null,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: _wRank,
                    child: Text(
                      '${standing.rank}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
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
                      borderRadius: BorderRadius.circular(5),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: standing.imageUrl.isNotEmpty
                        ? Image.network(
                            standing.imageUrl,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.shield, size: 18, color: AppColors.textLow),
                          )
                        : const Icon(Icons.shield, size: 18, color: AppColors.textLow),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      standing.teamCode,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.textHigh,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _wStat,
                    child: Text(
                      '${standing.wins}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textHigh),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: _wStat,
                    child: Text(
                      '${standing.losses}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: AppColors.textLow),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: _wSet,
                    child: Text(
                      '${standing.gameWins}-${standing.gameLosses}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.textMid),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: _wDiff,
                    child: Text(
                      standing.gameDiff > 0 ? '+${standing.gameDiff}' : '${standing.gameDiff}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: diffColor),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: _wRate,
                    child: Text(
                      '${(standing.winRate * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
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
        ),
        if (!isLast)
          const Divider(height: 1, thickness: 1, indent: 12, endIndent: 12, color: AppColors.border),
      ],
    );
  }
}
