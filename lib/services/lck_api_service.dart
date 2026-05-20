import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api.dart';
import '../models/match.dart';
import '../models/match_detail.dart' show MatchDetail, GameDetail, GameTeamStats;
import '../models/standing.dart';
import '../models/team.dart';

class ScheduleResult {
  final List<LckMatch> matches;
  final String? olderToken;
  final String? newerToken;
  const ScheduleResult({required this.matches, this.olderToken, this.newerToken});
}

class LckApiService {
  static final LckApiService instance = LckApiService._();
  LckApiService._();

  final _cache = <String, ({String body, int ts})>{};
  static const _cacheTtlMs = 15 * 60 * 1000; // 15분

  // ── 디스크 캐시 (과거 연도 불변 데이터 영구 보존) ─────────────────────────
  static const _diskPrefix = 'lck_disk_';

  Future<String?> _diskRead(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_diskPrefix$key');
    } catch (_) { return null; }
  }

  void _diskWrite(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_diskPrefix$key', value);
    } catch (_) {}
  }

  // 과거 연도 일정을 백그라운드에서 미리 패치 (이미 캐시 있으면 no-op)
  void prefetchLeaguepediaYear(int year) {
    final cacheKey = 'lp_year3_$year';
    if (_cache.containsKey(cacheKey)) return;
    getLeaguepediaYearSchedule(year);
  }

  // 연도 일정 파싱 중 동적으로 수집한 code → LP 팀 full name 역매핑
  final _dynamicTeamNames = <String, Set<String>>{};

  // 역사 코드 → 현재 코드 (이미지 폴백용): 팀이 리브랜딩됐을 때 현재 로고를 대신 사용
  // LP Teams 테이블에서 삭제된 해산 팀의 정적 이미지 URL
  static const _defunctTeamImages = <String, String>{
    'LSB': 'https://s-qwer.op.gg/images/lol/teams/2023sp_lsb.png',
  };

  // LP Teams 테이블에서 가져온 연도별 팀 데이터: LP이름 → (연도별 코드, 이미지URL)
  final _lpTeamData = <String, ({String code, String imageUrl})>{};

  // Leaguepedia MatchSchedule 기준 team1 코드 맵
  // key: "yyyy-MM-dd_CODEA_CODEB" (codes sorted) → LP Team1 code
  Map<String, String>? _lpTeam1Map;

  Map<String, String>? _teamImagesByCode;

  void clearCache([String? prefix]) {
    if (prefix == null) {
      _cache.clear();
    } else {
      _cache.removeWhere((k, _) => k.startsWith(prefix));
    }
  }

  Future<T> _get<T>(
    String endpoint,
    T Function(Map<String, dynamic>) parser, {
    bool cache = false,
  }) async {
    if (cache) {
      final hit = _cache[endpoint];
      if (hit != null &&
          DateTime.now().millisecondsSinceEpoch - hit.ts < _cacheTtlMs) {
        return parser(jsonDecode(hit.body)['data'] as Map<String, dynamic>);
      }
    }
    final uri = Uri.parse('${ApiConstants.baseUrl}/$endpoint');
    final res = await http
        .get(uri, headers: ApiConstants.headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('API 오류: ${res.statusCode}');
    if (cache) {
      _cache[endpoint] =
          (body: res.body, ts: DateTime.now().millisecondsSinceEpoch);
    }
    return parser(jsonDecode(res.body)['data'] as Map<String, dynamic>);
  }

  Future<ScheduleResult> getSchedule({String? pageToken}) async {
    final tokenParam = pageToken != null ? '&pageToken=$pageToken' : '';
    final endpoint =
        'getSchedule?hl=ko-KR&leagueId=${ApiConstants.scheduleLeagueIds}$tokenParam';

    // LP 순서 맵을 미리 로드 (첫 호출에만 실제 요청)
    await _ensureLpTeam1Map();

    return _get(
      endpoint,
      (data) {
        final schedule = data['schedule'] as Map<String, dynamic>;
        final events = schedule['events'] as List;
        final pages =
            schedule['pages'] as Map<String, dynamic>? ?? {};
        final matches = events
            .where((e) => e['type'] == 'match')
            .map((e) => _applyLpOrdering(LckMatch.fromJson(e as Map<String, dynamic>)))
            .toList();
        return ScheduleResult(
          matches: matches,
          olderToken: pages['older'] as String?,
          newerToken: pages['newer'] as String?,
        );
      },
      cache: true,
    );
  }

  // Leaguepedia MatchSchedule 기준 team1 순서 맵 로드 (한 번만)
  Future<void> _ensureLpTeam1Map() async {
    if (_lpTeam1Map != null) return;
    try {
      final uri = Uri.https('lol.fandom.com', '/wiki/Special:CargoExport', {
        'tables': 'MatchSchedule',
        'fields': 'Team1,Team2,DateTime_UTC',
        'where': "OverviewPage LIKE 'LCK/2026%'",
        'format': 'json',
        'limit': '500',
      });
      final res = await http.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200 || res.body.isEmpty) {
        _lpTeam1Map = {};
        return;
      }
      final rows = jsonDecode(res.body) as List;
      final map = <String, String>{};
      for (final row in rows) {
        final t1Name = (row['Team1'] as String? ?? '').trim();
        final t2Name = (row['Team2'] as String? ?? '').trim();
        final t1Code = _lpNameToCode[t1Name];
        final t2Code = _lpNameToCode[t2Name];
        final dateUtc = (row['DateTime UTC'] as String? ?? '');
        if (t1Code == null || t2Code == null || dateUtc.length < 10) continue;
        final dateKey = dateUtc.substring(0, 10);
        final codes = [t1Code, t2Code]..sort();
        map['${dateKey}_${codes[0]}_${codes[1]}'] = t1Code;
      }
      _lpTeam1Map = map;
      debugPrint('[LP] MatchSchedule loaded: ${map.length} matches');
    } catch (e) {
      debugPrint('[LP] MatchSchedule error: $e');
      _lpTeam1Map = {};
    }
  }

  // LP 순서 기준으로 필요하면 team1/team2 swap
  LckMatch _applyLpOrdering(LckMatch match) {
    final map = _lpTeam1Map;
    if (map == null || map.isEmpty) return match;
    if (match.leagueSlug != 'lck') return match;

    final dateKey = match.startTime.toUtc().toIso8601String().substring(0, 10);
    final codes = [match.team1.code, match.team2.code]..sort();
    final key = '${dateKey}_${codes[0]}_${codes[1]}';
    final lpTeam1 = map[key];

    if (lpTeam1 != null && lpTeam1 == match.team2.code) {
      return LckMatch(
        id: match.id,
        startTime: match.startTime,
        state: match.state,
        blockName: match.blockName,
        team1: match.team2,
        team2: match.team1,
        bestOf: match.bestOf,
        hasVod: match.hasVod,
        leagueName: match.leagueName,
        leagueSlug: match.leagueSlug,
      );
    }
    return match;
  }

  Future<List<Standing>> getStandings({String? tournamentId}) async {
    final id = tournamentId ?? ApiConstants.currentTournamentId;
    return _get(
      'getStandings?hl=ko-KR&tournamentId=$id',
      (data) {
        final stages = data['standings'][0]['stages'] as List;
        final regularStage = stages.firstWhere(
          (s) => s['slug'] == 'regular_season' || s['type'] == 'regular',
          orElse: () => stages[0],
        );
        final rankings = regularStage['sections'][0]['rankings'] as List;
        final List<Standing> standings = [];
        for (final ranking in rankings) {
          for (final team in ranking['teams']) {
            standings.add(Standing(
              rank: ranking['ordinal'],
              teamName: team['name'],
              teamCode: team['code'],
              imageUrl: team['image'] ?? '',
              wins: team['record']['wins'],
              losses: team['record']['losses'],
            ));
          }
        }
        return standings;
      },
      cache: true,
    );
  }

  // 2026 시즌 기준 활동 중인 LCK 10개 팀 코드
  static const _activeLckTeamCodes = {
    'T1', 'GEN', 'HLE', 'KT', 'DK', 'NS', 'BRO', 'BFX', 'KRX', 'DNS',
  };

  static const _subTeamKeywords = [
    'academy', 'challengers', 'toberemoved', 'rookies', 'youth',
  ];

  Future<List<Team>> getLckTeams() async {
    return _get(
      'getTeams?hl=ko-KR',
      (data) {
        final teams = data['teams'] as List;

        // 코드별로 서브팀 제외 후 선수 수 가장 많은 팀 선택
        final best = <String, Map<String, dynamic>>{};
        for (final t in teams) {
          final code = t['code'] as String? ?? '';
          if (!_activeLckTeamCodes.contains(code)) continue;
          final name = (t['name'] as String? ?? '').toLowerCase();
          if (_subTeamKeywords.any((k) => name.contains(k))) continue;
          final playerCount = (t['players'] as List? ?? []).length;
          if (!best.containsKey(code) ||
              playerCount > (best[code]!['players'] as List).length) {
            best[code] = t as Map<String, dynamic>;
          }
        }

        return best.values
            .map((t) => Team.fromJson(t))
            .toList()
          ..sort((a, b) => a.code.compareTo(b.code));
      },
      cache: true,
    );
  }

  Future<Team> getTeamDetail(String slug) async {
    return _get(
      'getTeams?hl=ko-KR&id=$slug',
      (data) => Team.fromJson((data['teams'] as List)[0] as Map<String, dynamic>),
    );
  }

  Future<String?> getLckLeagueImage() async {
    return _get(
      'getLeagues?hl=ko-KR',
      (data) {
        final leagues = data['leagues'] as List;
        final lck = leagues.firstWhere(
          (l) => l['slug'] == 'lck',
          orElse: () => null,
        );
        return lck?['image'] as String?;
      },
    );
  }

  Future<MatchDetail> getEventDetails(String matchId) async {
    return _get(
      'getEventDetails?hl=ko-KR&id=$matchId',
      (data) {
        final event = data['event'] as Map<String, dynamic>? ?? {};
        return MatchDetail.fromJson(event);
      },
      cache: true,
    );
  }

  // Feed API로 경기별 상세 스탯 (킬, 골드, 타워, 오브젝트) 가져오기
  // startingTime: 경기 종료 이후 시각 (과거여야 함). match.startTime + 4h 권장.
  Future<({GameTeamStats? blueTeam, GameTeamStats? redTeam, DateTime? firstFrameTime, DateTime? lastFrameTime, String? winnerSide, String? patchVersion})?> getGameWindow(String gameId, String startingTime) async {
    final cacheKey = 'window_$gameId';
    final hit = _cache[cacheKey];
    if (hit != null && DateTime.now().millisecondsSinceEpoch - hit.ts < _cacheTtlMs) {
      return _parseWindowBody(hit.body);
    }

    try {
      final uri = Uri.parse(
        'https://feed.lolesports.com/livestats/v1/window/$gameId?startingTime=$startingTime',
      );
      final res = await http.get(uri, headers: const {
        'origin': 'https://lolesports.com',
        'referer': 'https://lolesports.com/',
      }).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return null;
      _cache[cacheKey] = (body: res.body, ts: DateTime.now().millisecondsSinceEpoch);
      return _parseWindowBody(res.body);
    } catch (e) {
      return null;
    }
  }

  ({GameTeamStats? blueTeam, GameTeamStats? redTeam, DateTime? firstFrameTime, DateTime? lastFrameTime, String? winnerSide, String? patchVersion})? _parseWindowBody(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final frames = data['frames'] as List? ?? [];
      if (frames.isEmpty) return null;

      final firstFrame = frames.first as Map<String, dynamic>;
      final lastFrame = frames.last as Map<String, dynamic>;
      final blueData = lastFrame['blueTeam'] as Map<String, dynamic>?;
      final redData = lastFrame['redTeam'] as Map<String, dynamic>?;

      DateTime? firstFrameTime;
      DateTime? lastFrameTime;
      try {
        firstFrameTime = DateTime.parse(firstFrame['rfc460Timestamp'] as String);
        lastFrameTime = DateTime.parse(lastFrame['rfc460Timestamp'] as String);
      } catch (_) {}

      final metadata = data['gameMetadata'] as Map<String, dynamic>? ?? {};
      final patchVersion = metadata['patchVersion'] as String?;
      final blueMeta = metadata['blueTeamMetadata'] as Map<String, dynamic>? ?? {};
      final redMeta = metadata['redTeamMetadata'] as Map<String, dynamic>? ?? {};
      final bluePicks = (blueMeta['participantMetadata'] as List? ?? [])
          .map((p) => p['championId']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      final redPicks = (redMeta['participantMetadata'] as List? ?? [])
          .map((p) => p['championId']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      // 승자 판별: 인히비터 > 타워 > 킬 순으로 신뢰도 높은 지표 사용
      String? winnerSide;
      final blueInh = blueData?['inhibitors'] as int? ?? 0;
      final redInh = redData?['inhibitors'] as int? ?? 0;
      final blueTow = blueData?['towers'] as int? ?? 0;
      final redTow = redData?['towers'] as int? ?? 0;
      final blueKills = blueData?['totalKills'] as int? ?? 0;
      final redKills = redData?['totalKills'] as int? ?? 0;
      if (blueInh != redInh) {
        winnerSide = blueInh > redInh ? 'blue' : 'red';
      } else if (blueTow != redTow) {
        winnerSide = blueTow > redTow ? 'blue' : 'red';
      } else if (blueKills != redKills) {
        winnerSide = blueKills > redKills ? 'blue' : 'red';
      }

      return (
        blueTeam: blueData != null ? GameTeamStats.fromWindowJson(blueData, picks: bluePicks) : null,
        redTeam: redData != null ? GameTeamStats.fromWindowJson(redData, picks: redPicks) : null,
        firstFrameTime: firstFrameTime,
        lastFrameTime: lastFrameTime,
        winnerSide: winnerSide,
        patchVersion: patchVersion,
      );
    } catch (e) {
      return null;
    }
  }

  // Feed API 스냅샷은 :00/:30 초에만 존재 → 프로브를 반드시 해당 경계로 맞춰야 함
  DateTime _snapToHalfMinute(DateTime dt) {
    final s = dt.second;
    if (s == 0) return dt.copyWith(millisecond: 0, microsecond: 0);
    if (s < 30) return dt.copyWith(second: 30, millisecond: 0, microsecond: 0);
    if (s == 30) return dt.copyWith(millisecond: 0, microsecond: 0);
    // s > 30 → 다음 분의 :00
    return dt
        .add(Duration(seconds: 60 - s))
        .copyWith(millisecond: 0, microsecond: 0);
  }

  // 게임 시작 시각 탐색:
  // chapter+4min부터 chapter+20min까지 1분 간격으로 17개 병렬 프로브
  // 각 프로브는 :00/:30 경계로 스냅하여 API 스냅샷 간격과 일치시킴
  Future<DateTime?> _getGameStartTime(String gameId, DateTime chapterStart) async {
    final cacheKey = 'gamestart_$gameId';
    final hit = _cache[cacheKey];
    if (hit != null && DateTime.now().millisecondsSinceEpoch - hit.ts < _cacheTtlMs) {
      return hit.body.isEmpty ? null : DateTime.tryParse(hit.body);
    }

    final base = chapterStart.toUtc();
    // 4분~20분 범위, 1분 간격 (17개) → 각각 :00/:30으로 스냅
    final probeTimes = List.generate(17, (i) {
      final raw = base.add(Duration(minutes: 4 + i));
      return _snapToHalfMinute(raw);
    });
    // 중복 제거 (스냅 결과가 같은 경우)
    final uniqueTimes = probeTimes.toSet().toList()..sort();

    final results = await Future.wait(uniqueTimes.map((t) async {
      final timeStr = '${t.toIso8601String().substring(0, 19)}.000Z';
      try {
        final uri = Uri.parse(
            'https://feed.lolesports.com/livestats/v1/window/$gameId?startingTime=$timeStr');
        final res = await http.get(uri, headers: const {
          'origin': 'https://lolesports.com',
          'referer': 'https://lolesports.com/',
        }).timeout(const Duration(seconds: 10));
        if (res.statusCode != 200 || res.body.isEmpty) {
          return (t: t, firstTs: null as DateTime?);
        }
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final frames = data['frames'] as List? ?? [];
        if (frames.isEmpty) return (t: t, firstTs: null as DateTime?);
        final ts = frames.first['rfc460Timestamp'] as String?;
        return (t: t, firstTs: ts != null ? DateTime.tryParse(ts) : null);
      } catch (_) {
        return (t: t, firstTs: null as DateTime?);
      }
    }));

    results.sort((a, b) => a.t.compareTo(b.t));

    DateTime? gameStart;
    DateTime? lastBeforeT;
    DateTime? firstAfterT;

    for (final r in results) {
      if (r.firstTs == null) {
        lastBeforeT = r.t;
      } else if (r.firstTs!.isAfter(r.t)) {
        // 직접 감지: 프로브 시각 이후에 첫 프레임 → 그 시각이 게임 시작
        gameStart = r.firstTs;
        break;
      } else {
        firstAfterT ??= r.t;
      }
    }

    // 직접 감지 실패 시 전환 구간 중간값으로 추정 (±30초 오차)
    if (gameStart == null && firstAfterT != null) {
      final lo = lastBeforeT ?? firstAfterT.subtract(const Duration(seconds: 60));
      final hi = firstAfterT;
      gameStart = lo.add(Duration(milliseconds: hi.difference(lo).inMilliseconds ~/ 2));
    }

    _cache[cacheKey] = (
      body: gameStart?.toIso8601String() ?? '',
      ts: DateTime.now().millisecondsSinceEpoch,
    );
    return gameStart;
  }

  // 팀 코드 → Leaguepedia 표시명 목록 (연도별 구분: 2026은 KRX, 2025이전은 DRX 등)
  static const _leaguepediaTeamAliases = <String, List<String>>{
    // 2026 LCK 활성 팀
    'T1':  ['T1', 'SK Telecom T1'],
    'GEN': ['Gen.G', 'KSV eSports', 'Samsung Galaxy'],
    'HLE': ['Hanwha Life Esports', 'HLE'],
    'KT':  ['KT Rolster'],
    'DK':  ['Dplus Kia', 'Dplus KIA', 'DWG KIA', 'DAMWON Gaming', 'DAMWON KIA'],
    'NS':  ['Nongshim RedForce'],
    'BRO': ['HANJIN BRION', 'BRION', 'OK Savings Bank BRION', 'OKSavingsBank BRION',
            'Brion', 'BRO', 'BRION Esports', 'Fredit BRION', 'APK Prince'],
    'BFX': ['BNK FEARX', 'BNK FearX', 'FearX'],
    'KRX': ['Kiwoom DRX', 'DRX', 'DRX (Korean Team)', 'DragonX', 'Kingzone DragonX', 'Longzhu Gaming'],
    'DNS': ['DN SOOPers', 'DN Freecs', 'Kwangdong Freecs', 'KDF', 'Afreeca Freecs'],
    'LSB': ['Liiv SANDBOX', 'LSB', 'SANDBOX Gaming'],
    // 순수 해산 팀 (이미지 없음, 코드 파생 오류 방지용)
    'GRF': ['Griffin', 'Griffin (Korean Team)'],
    'JAG': ['Jin Air Green Wings'],
    'CJE': ['CJ Entus'],
    'ROX': ['ROX Tigers'],
    'MVP': ['MVP'],
    'BBQ': ['bbq Olivers'],
    'SBE': ['SBENU Sonicboom'],
    'KDM': ['Kongdoo Monster'],
    'EMF': ['e-mFire'],
    'ESC': ['ESC Ever', 'Ever8 Winners'],
    'SPX': ['SeolHaeOne Prince'],
    'TDY': ['Team Dynamics'],
    'SBG': ['Seorabeol Gaming'],
    // 주요 해외 팀
    'G2':  ['G2 Esports', 'G2'],
    'FNC': ['Fnatic', 'Fnatic (2024 EMEA Team)'],
    'MAD': ['MAD Lions', 'KOI', 'Movistar KOI', 'KOI (2023 EMEA Team)', 'KOI (2024 EMEA Team)'],
    'VIT': ['Team Vitality', 'Vitality'],
    'TL':  ['Team Liquid', 'Team Liquid Honda'],
    'C9':  ['Cloud9'],
    'FLY': ['FlyQuest', 'FLY'],
    '100': ['100 Thieves'],
    'EG':  ['Evil Geniuses'],
    'JDG': ['JD Gaming', 'JDG'],
    'BLG': ['Bilibili Gaming', 'BLG'],
    'EDG': ['Edward Gaming', 'EDG'],
    'RNG': ['Royal Never Give Up', 'RNG'],
    'WBG': ['Weibo Gaming', 'WBG'],
    'FPX': ['FunPlus Phoenix', 'FPX'],
    'TES': ['Top Esports', 'TES'],
    'LNG': ['LNG Esports', 'LNG'],
    'NRG': ['NRG Esports', 'NRG'],
    'PRX': ['Paper Rex', 'PRX'],
    'GAM': ['GAM Esports', 'GAM'],
    'PSG': ['PSG Talon', 'Talon Esports', 'Talon'],
    'GG':  ['Golden Guardians', 'GG'],
    'SHG': ['Shopify Rebellion', 'SHG'],
    'DFM': ['DetonatioN FocusMe', 'DFM'],
    'CFO': ['CFO', 'CTBC Flying Oyster', 'CTBC'],
    'LOUD': ['LOUD'],
    'LYON': ['LYON (2024 American Team)', 'LYON'],
    'TSW': ['Team Secret Whales', 'TSW'],
    'NOVA': ['Nova Esports', 'NOVA'],
    'TH':  ['Team Heretics', 'TH'],
    'WOL': ['Wolves Esports', 'WOL'],
  };

  // LP 팀명 → 시대별 짧은 표시명
  static const _lpShortName = <String, String>{
    'SK Telecom T1': 'SKT', 'T1': 'T1',
    'Samsung Galaxy': 'SSG', 'KSV eSports': 'KSV', 'Gen.G': 'GEN',
    'DAMWON Gaming': 'DWG', 'DAMWON KIA': 'DWG KIA',
    'DWG KIA': 'DWG KIA', 'Dplus KIA': 'DK', 'Dplus Kia': 'DK',
    'Longzhu Gaming': 'LZ', 'Kingzone DragonX': 'KZ',
    'DragonX': 'DRX', 'DRX': 'DRX', 'DRX (Korean Team)': 'DRX', 'Kiwoom DRX': 'KRX',
    'Afreeca Freecs': 'AF', 'Kwangdong Freecs': 'KDF', 'KDF': 'KDF',
    'DN Freecs': 'DNS', 'DN SOOPers': 'DNS',
    'Hanwha Life Esports': 'HLE', 'HLE': 'HLE',
    'KT Rolster': 'KT', 'Nongshim RedForce': 'NS',
    'BNK FEARX': 'BFX', 'BNK FearX': 'BFX', 'FearX': 'BFX',
    'HANJIN BRION': 'BRO', 'BRION': 'BRO', 'OK Savings Bank BRION': 'BRO',
    'OKSavingsBank BRION': 'BRO', 'Brion': 'BRO', 'BRO': 'BRO',
    'BRION Esports': 'BRO', 'Fredit BRION': 'BRO', 'APK Prince': 'APK',
    'Liiv SANDBOX': 'LSB', 'LSB': 'LSB', 'SANDBOX Gaming': 'SBG',
    'Griffin': 'GRF', 'Griffin (Korean Team)': 'GRF',
    'ROX Tigers': 'ROX', 'CJ Entus': 'CJE', 'Jin Air Green Wings': 'JAG',
    'MVP': 'MVP', 'bbq Olivers': 'BBQ', 'SBENU Sonicboom': 'SBE',
    'Kongdoo Monster': 'KDM', 'e-mFire': 'EMF',
    'ESC Ever': 'ESC', 'Ever8 Winners': 'E8W',
    'SeolHaeOne Prince': 'SPX', 'Team Dynamics': 'TDY', 'Seorabeol Gaming': 'SBG',
  };

  // Leaguepedia 표시명 → DDragon 내부 ID 변환
  static const _champExceptions = <String, String>{
    'Wukong': 'MonkeyKing',
    'Nunu & Willump': 'Nunu',
    "Cho'Gath": 'Chogath',
    "Kai'Sa": 'Kaisa',
    "Kha'Zix": 'Khazix',
    "K'Sante": 'KSante',
    "Rek'Sai": 'RekSai',
    "Vel'Koz": 'Velkoz',
    "Bel'Veth": 'Belveth',
    "LeBlanc": 'Leblanc',
    "Jarvan IV": 'JarvanIV',
    "Miss Fortune": 'MissFortune',
    "Twisted Fate": 'TwistedFate',
    "Lee Sin": 'LeeSin',
    "Master Yi": 'MasterYi',
    "Tahm Kench": 'TahmKench',
    "Xin Zhao": 'XinZhao',
    "Dr. Mundo": 'DrMundo',
    "Aurelion Sol": 'AurelionSol',
    "Kog'Maw": 'KogMaw',
    "Renata Glasc": 'Renata',
  };

  String _toDDragonId(String displayName) {
    if (_champExceptions.containsKey(displayName)) return _champExceptions[displayName]!;
    // 공백, 특수문자 제거 후 단어별 대소문자 유지
    return displayName.replaceAll(RegExp(r"['\s&\.]"), '');
  }

  // LCK 전체 시즌 팀별 게임 승/패 집계 (Leaguepedia)
  Future<Map<String, ({int wins, int losses})>> getTeamGameRecords() async {
    const cacheKey = 'team_game_records_lck2026_v3';
    final hit = _cache[cacheKey];
    if (hit != null && DateTime.now().millisecondsSinceEpoch - hit.ts < _cacheTtlMs) {
      return _parseTeamGameRecords(hit.body);
    }

    try {
      final uri = Uri.https('lol.fandom.com', '/wiki/Special:CargoExport', {
        'tables': 'ScoreboardGames',
        'fields': 'Team1,Team2,WinTeam',
        'where': "_pageName LIKE 'LCK/2026%' AND _pageName NOT LIKE '%Cup%'",
        'format': 'json',
        'limit': '500',
      });
      final res = await http.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200 || res.body.isEmpty) return {};
      _cache[cacheKey] = (body: res.body, ts: DateTime.now().millisecondsSinceEpoch);
      return _parseTeamGameRecords(res.body);
    } catch (e) {
      debugPrint('[LP] getTeamGameRecords error: $e');
      return {};
    }
  }

  // Leaguepedia 이름 → 팀 코드 역방향 맵
  static final _lpNameToCode = <String, String>{
    for (final entry in _leaguepediaTeamAliases.entries)
      for (final alias in entry.value) alias: entry.key,
  };

  Map<String, ({int wins, int losses})> _parseTeamGameRecords(String body) {
    final rows = jsonDecode(body) as List? ?? [];
    final wins = <String, int>{};
    final losses = <String, int>{};
    for (final row in rows) {
      final t1 = _lpNameToCode[row['Team1'] as String? ?? ''];
      final t2 = _lpNameToCode[row['Team2'] as String? ?? ''];
      final winner = _lpNameToCode[row['WinTeam'] as String? ?? ''];
      if (t1 == null || t2 == null || winner == null) continue;
      wins[winner] = (wins[winner] ?? 0) + 1;
      final loser = winner == t1 ? t2 : t1;
      losses[loser] = (losses[loser] ?? 0) + 1;
    }
    final codes = {...wins.keys, ...losses.keys};
    return {for (final c in codes) c: (wins: wins[c] ?? 0, losses: losses[c] ?? 0)};
  }

  // 게임 골드 타임라인 (블루팀/레드팀 시간별 골드)
  Future<List<({int seconds, int blueGold, int redGold})>> getGoldTimeline(
      String gameId, DateTime gameStart, int durationSeconds) async {
    final cacheKey = 'gold_$gameId';
    final hit = _cache[cacheKey];
    if (hit != null && DateTime.now().millisecondsSinceEpoch - hit.ts < _cacheTtlMs) {
      if (hit.body.isEmpty) return [];
      return _parseGoldTimeline(hit.body);
    }

    // 2분 단위 window 40개 병렬 요청 (80분 커버 — chapter start 기준이어도 충분)
    // stride를 좁게 해서 window 간 공백 제거 (각 window는 약 3-4분 데이터 반환)
    const strideMin = 2;
    const numWindows = 40;
    final allFrames = <Map<String, dynamic>>[];

    await Future.wait(
      List.generate(numWindows, (i) async {
        final rawMs = gameStart.add(Duration(minutes: i * strideMin)).toUtc().millisecondsSinceEpoch;
        // API requires startingTime divisible by 10 seconds — floor to nearest 10s
        final snapped = DateTime.fromMillisecondsSinceEpoch((rawMs ~/ 10000) * 10000, isUtc: true);
        final t = '${snapped.toIso8601String().substring(0, 19)}.000Z';
        try {
          final res = await http.get(
            Uri.parse('https://feed.lolesports.com/livestats/v1/window/$gameId?startingTime=$t'),
            headers: const {
              'origin': 'https://lolesports.com',
              'referer': 'https://lolesports.com/',
            },
          ).timeout(const Duration(seconds: 15));
          if (res.statusCode == 200 && res.body.isNotEmpty) {
            final data = jsonDecode(res.body) as Map<String, dynamic>;
            final frames = (data['frames'] as List? ?? []).cast<Map<String, dynamic>>();
            allFrames.addAll(frames);
          }
        } catch (e) {
          debugPrint('[Gold] window $i error: $e');
        }
      }),
    );

    if (allFrames.isEmpty) {
      _cache[cacheKey] = (body: '', ts: DateTime.now().millisecondsSinceEpoch);
      return [];
    }
    final combined = jsonEncode(allFrames);
    _cache[cacheKey] = (body: combined, ts: DateTime.now().millisecondsSinceEpoch);
    return _parseGoldTimeline(combined);
  }

  List<({int seconds, int blueGold, int redGold})> _parseGoldTimeline(String body) {
    try {
      final frames = jsonDecode(body) as List;

      // 타임스탬프 순 정렬
      final sorted = frames
          .where((f) => f['rfc460Timestamp'] != null)
          .toList()
        ..sort((a, b) => (a['rfc460Timestamp'] as String).compareTo(b['rfc460Timestamp'] as String));

      // 골드가 처음 등장하는 프레임 = 실제 게임 시작 기준점
      DateTime? effectiveStart;
      for (final frame in sorted) {
        final bg = (frame['blueTeam']?['totalGold'] as int?) ?? 0;
        final rg = (frame['redTeam']?['totalGold'] as int?) ?? 0;
        if (bg > 0 || rg > 0) {
          effectiveStart = DateTime.tryParse(frame['rfc460Timestamp'] as String? ?? '');
          break;
        }
      }
      if (effectiveStart == null) return [];

      final seen = <int>{};
      final points = <({int seconds, int blueGold, int redGold})>[];
      for (final frame in sorted) {
        final ts = DateTime.tryParse(frame['rfc460Timestamp'] as String? ?? '');
        if (ts == null) continue;
        final secs = ts.difference(effectiveStart).inSeconds;
        if (secs < 0) continue;
        if (seen.contains(secs)) continue;
        seen.add(secs);
        final bg = (frame['blueTeam']?['totalGold'] as int?) ?? 0;
        final rg = (frame['redTeam']?['totalGold'] as int?) ?? 0;
        if (bg == 0 && rg == 0) continue;
        points.add((seconds: secs, blueGold: bg, redGold: rg));
      }
      return points;
    } catch (_) {
      return [];
    }
  }

  // Special:CargoExport 엔드포인트 — api.php와 달리 rate limit 없음
  Future<List<({int gameN, int heralds1, int heralds2, int grubs1, int grubs2, List<String> bans1, List<String> bans2})>>
      _getLeaguepediaStats(String team1Code, String team2Code, DateTime matchDate) async {
    final t1Aliases = _leaguepediaTeamAliases[team1Code] ?? [team1Code];
    final t2Aliases = _leaguepediaTeamAliases[team2Code] ?? [team2Code];
    if (t1Aliases.isEmpty || t2Aliases.isEmpty) return [];

    final cacheKey = 'lpedia3_${team1Code}_${team2Code}_${matchDate.toUtc().toIso8601String().substring(0, 10)}';
    final hit = _cache[cacheKey];
    if (hit != null && DateTime.now().millisecondsSinceEpoch - hit.ts < _cacheTtlMs) {
      if (hit.body.isEmpty) return [];
      return _parseLeaguepediaExport(hit.body, t1Aliases, t2Aliases);

    }

    final dateUtc = matchDate.toUtc();
    final d0 = dateUtc.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    final d1 = dateUtc.add(const Duration(days: 2)).toIso8601String().substring(0, 10);

    try {
      final uri = Uri.https('lol.fandom.com', '/wiki/Special:CargoExport', {
        'tables': 'ScoreboardGames',
        'fields': 'Team1,Team2,DateTime_UTC,Team1RiftHeralds,Team2RiftHeralds,Team1VoidGrubs,Team2VoidGrubs,Team1Bans,Team2Bans',
        'where': "(_pageName LIKE 'LCK/${matchDate.year}%' OR _pageName LIKE 'First Stand/${matchDate.year}%' OR _pageName LIKE '${matchDate.year} First Stand%' OR _pageName LIKE 'Season Kickoff/${matchDate.year}%' OR _pageName LIKE 'MSI/${matchDate.year}%' OR _pageName LIKE 'Worlds/${matchDate.year}%') AND DateTime_UTC > '$d0' AND DateTime_UTC < '$d1'",
        'format': 'json',
        'limit': '50',
      });
      final res = await http.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200 || res.body.isEmpty) {
        debugPrint('[LP] CargoExport HTTP ${res.statusCode}');
        _cache[cacheKey] = (body: '', ts: DateTime.now().millisecondsSinceEpoch);
        return [];
      }
      debugPrint('[LP] CargoExport OK rows=${(jsonDecode(res.body) as List?)?.length}');
      _cache[cacheKey] = (body: res.body, ts: DateTime.now().millisecondsSinceEpoch);
      return _parseLeaguepediaExport(res.body, t1Aliases, t2Aliases);
    } catch (e) {
      debugPrint('[LP] error: $e');
      return [];
    }
  }

  List<({int gameN, int heralds1, int heralds2, int grubs1, int grubs2, List<String> bans1, List<String> bans2})>
      _parseLeaguepediaExport(String body, List<String> t1Aliases, List<String> t2Aliases) {
    try {
      final rows = jsonDecode(body) as List;
      final matched = <Map<String, dynamic>>[];

      for (final r in rows) {
        final row = r as Map<String, dynamic>;
        final rowT1 = row['Team1'] as String? ?? '';
        final rowT2 = row['Team2'] as String? ?? '';
        final forward = t1Aliases.contains(rowT1) && t2Aliases.contains(rowT2);
        final reverse = t2Aliases.contains(rowT1) && t1Aliases.contains(rowT2);
        if (!forward && !reverse) continue;
        matched.add({...row, '_forward': forward});
      }

      matched.sort((a, b) {
        final da = a['DateTime UTC'] as String? ?? a['DateTime_UTC'] as String? ?? '';
        final db = b['DateTime UTC'] as String? ?? b['DateTime_UTC'] as String? ?? '';
        return da.compareTo(db);
      });

      return List.generate(matched.length, (i) {
        final row = matched[i];
        final isForward = row['_forward'] as bool;
        final rawH1 = (row['Team1RiftHeralds'] as num?)?.toInt() ?? 0;
        final rawH2 = (row['Team2RiftHeralds'] as num?)?.toInt() ?? 0;
        final rawG1 = (row['Team1VoidGrubs'] as num?)?.toInt() ?? 0;
        final rawG2 = (row['Team2VoidGrubs'] as num?)?.toInt() ?? 0;

        List<String> parseBans(dynamic raw) {
          if (raw is List) return raw.map((e) => _toDDragonId(e.toString())).toList();
          if (raw is String && raw.isNotEmpty) return raw.split(',').map((e) => _toDDragonId(e.trim())).toList();
          return [];
        }

        final rawBans1 = row['Team1Bans'];
        final rawBans2 = row['Team2Bans'];
        final bansA = parseBans(rawBans1);
        final bansB = parseBans(rawBans2);

        return (
          gameN: i + 1,
          heralds1: isForward ? rawH1 : rawH2,
          heralds2: isForward ? rawH2 : rawH1,
          grubs1: isForward ? rawG1 : rawG2,
          grubs2: isForward ? rawG2 : rawG1,
          bans1: isForward ? bansA : bansB,
          bans2: isForward ? bansB : bansA,
        );
      });
    } catch (e) {
      debugPrint('[LP] parse error: $e');
      return [];
    }
  }

  // MatchDetail의 각 게임에 window 스탯 + 정확한 경기 시간 + 승팀 추가
  Future<MatchDetail> enrichWithWindowData(MatchDetail detail, LckMatch match) async {
    final afterMatch = match.startTime.toUtc().add(const Duration(hours: 4));
    final endTime = '${afterMatch.toIso8601String().substring(0, 19)}.000Z';
    final apiTeam1IsLckTeam1 = detail.team1Code.isEmpty || match.team1.code == detail.team1Code;

    // window 스탯과 leaguepedia 데이터를 병렬로 시작
    final lpediaFuture = _getLeaguepediaStats(match.team1.code, match.team2.code, match.startTime);

    final enriched = await Future.wait(
      detail.games.map((game) async {
        if (game.gameId == null) return game;

        final w = await getGameWindow(game.gameId!, endTime);
        if (w == null) return game;

        int? accurateDuration;
        DateTime? gameStartUtc;
        if (game.chapterStartUtc != null && w.lastFrameTime != null) {
          final gameStart = await _getGameStartTime(game.gameId!, game.chapterStartUtc!);
          if (gameStart != null) {
            final secs = w.lastFrameTime!.difference(gameStart).inSeconds;
            if (secs > 0 && secs < 7200) accurateDuration = secs;
            gameStartUtc = gameStart;
          }
        }

        final isApiTeam1Blue = game.team1Side == 'blue';
        final isLckTeam1Blue = apiTeam1IsLckTeam1 ? isApiTeam1Blue : !isApiTeam1Blue;

        String? winnerCode = game.winnerCode;
        if (winnerCode == null && w.winnerSide != null) {
          final winnerIsLckTeam1 = (w.winnerSide == 'blue') == isLckTeam1Blue;
          winnerCode = winnerIsLckTeam1 ? match.team1.code : match.team2.code;
        }

        return game.withWindowData(
          winnerCode: winnerCode,
          team1Stats: isLckTeam1Blue ? w.blueTeam : w.redTeam,
          team2Stats: isLckTeam1Blue ? w.redTeam : w.blueTeam,
          durationSeconds: accurateDuration ?? game.durationSeconds,
          patchVersion: w.patchVersion,
          team1IsBlue: isLckTeam1Blue,
          gameStartUtc: gameStartUtc ?? game.chapterStartUtc,
        );
      }),
    );

    // leaguepedia 데이터로 전령/유충 머지
    final lpediaGames = await lpediaFuture;
    if (lpediaGames.isEmpty) return MatchDetail(games: enriched, team1Code: detail.team1Code);

    final lpediaMap = {for (final g in lpediaGames) g.gameN: g};
    final merged = enriched.map((game) {
      final lp = lpediaMap[game.number];
      if (lp == null) return game;
      var updated = game;
      if (game.team1Stats != null) {
        updated = updated.withWindowData(
          winnerCode: game.winnerCode,
          team1Stats: game.team1Stats!.copyWith(heralds: lp.heralds1, voidGrubs: lp.grubs1),
          team2Stats: game.team2Stats?.copyWith(heralds: lp.heralds2, voidGrubs: lp.grubs2),
          durationSeconds: game.durationSeconds,
          patchVersion: game.patchVersion,
        );
      }
      if (lp.bans1.isNotEmpty || lp.bans2.isNotEmpty) {
        updated = updated.withBans(team1Bans: lp.bans1, team2Bans: lp.bans2);
      }
      return updated;
    }).toList();

    return MatchDetail(games: merged, team1Code: detail.team1Code);
  }

  Future<Map<String, String>> _getTeamImagesByCode() async {
    if (_teamImagesByCode != null) return _teamImagesByCode!;
    try {
      final teams = await getLckTeams();
      _teamImagesByCode = {for (final t in teams) t.code: t.imageUrl};
    } catch (_) {
      _teamImagesByCode = {};
    }
    return _teamImagesByCode!;
  }

  // LP Teams 테이블에서 연도별 팀 데이터(코드·로고) 조회 → _lpTeamData에 저장
  // LP Short을 코드로 사용해 팀명 변경(DRX→KRX 등)을 연도별로 올바르게 반영
  Future<void> _fetchLpTeamRoster(List<String> lpNames) async {
    final need = lpNames.where((n) => !_lpTeamData.containsKey(n)).toSet().toList();
    if (need.isEmpty) return;
    try {
      final inClause = need.map((n) => "'${n.replaceAll("'", "\\'")}'").join(',');
      final uri = Uri.https('lol.fandom.com', '/wiki/Special:CargoExport', {
        'tables': 'Teams',
        'fields': 'OverviewPage,Short,Image',
        'where': 'OverviewPage IN ($inClause)',
        'format': 'json',
        'limit': '200',
      });
      final res = await http.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || res.body.isEmpty) return;

      final rows = jsonDecode(res.body) as List;
      for (final r in rows) {
        final row = r as Map<String, dynamic>;
        final name = (row['OverviewPage']?.toString() ?? '').trim();
        final short = (row['Short']?.toString() ?? '').trim();
        final image = (row['Image']?.toString() ?? '').trim();
        if (name.isEmpty) continue;
        // LP Short을 우선 코드로 사용, 없으면 기존 정적 맵 → 파생 코드 순
        final code = short.isNotEmpty
            ? short.toUpperCase()
            : (_lpNameToCode[name] ?? _deriveTeamCode(name));
        final imageUrl = image.isNotEmpty
            ? 'https://lol.fandom.com/wiki/Special:FilePath/${Uri.encodeComponent(image)}?width=100'
            : '';
        if (code == 'KDF') debugPrint('[LP] KDF OverviewPage found: name=$name image=$image url=$imageUrl');
        _lpTeamData[name] = (code: code, imageUrl: imageUrl);
        _dynamicTeamNames.putIfAbsent(code, () => {}).add(name);
      }

      // Fallback: OverviewPage 쿼리에서 이미지를 못 찾은 팀 → Short 코드로 재시도
      // 단, 알려진 LCK 코드만 허용 (엉뚱한 해외 팀 이미지 오매칭 방지)
      final _knownCodes = _leaguepediaTeamAliases.keys.toSet();
      final stillMissing = need.where((n) =>
          !_lpTeamData.containsKey(n) ||
          (_lpTeamData[n]!.imageUrl.isEmpty)).toList();
      if (stillMissing.isNotEmpty) {
        final codes = stillMissing
            .map((n) => _lpNameToCode[n] ?? _deriveTeamCode(n))
            .where((c) => c.isNotEmpty && _knownCodes.contains(c))
            .toSet()
            .toList();
        if (codes.isNotEmpty) {
          final codeClause = codes.map((c) => "'${c.replaceAll("'", "\\'")}'").join(',');
          final uri2 = Uri.https('lol.fandom.com', '/wiki/Special:CargoExport', {
            'tables': 'Teams',
            'fields': 'OverviewPage,Short,Image',
            'where': 'Short IN ($codeClause)',
            'format': 'json',
            'limit': '200',
          });
          final res2 = await http.get(uri2, headers: const {
            'User-Agent': 'Mozilla/5.0',
            'Accept': 'application/json',
          }).timeout(const Duration(seconds: 10));
          if (res2.statusCode == 200 && res2.body.isNotEmpty) {
            final rows2 = jsonDecode(res2.body) as List;
            // code → imageUrl 맵 구성
            final codeToImage = <String, String>{};
            for (final r2 in rows2) {
              final row2 = r2 as Map<String, dynamic>;
              final short2 = (row2['Short']?.toString() ?? '').trim().toUpperCase();
              final image2 = (row2['Image']?.toString() ?? '').trim();
              if (short2.isNotEmpty && image2.isNotEmpty && !codeToImage.containsKey(short2)) {
                codeToImage[short2] = 'https://lol.fandom.com/wiki/Special:FilePath/${Uri.encodeComponent(image2)}?width=100';
              }
            }
            // 여전히 이미지 없는 팀에 적용
            for (final n in stillMissing) {
              final code = _lpNameToCode[n] ?? _deriveTeamCode(n);
              final imgUrl = codeToImage[code] ?? '';
              if (imgUrl.isEmpty) continue;
              if (_lpTeamData.containsKey(n)) {
                _lpTeamData[n] = (code: _lpTeamData[n]!.code, imageUrl: imgUrl);
              } else {
                _lpTeamData[n] = (code: code, imageUrl: imgUrl);
                _dynamicTeamNames.putIfAbsent(code, () => {}).add(n);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[LP] _fetchLpTeamRoster error: $e');
    }
  }

  // JSON body에서 LP 팀 이름 목록 추출
  List<String> _extractLpTeamNamesFromBody(String body) {
    try {
      final rows = jsonDecode(body) as List;
      final names = <String>{};
      for (final r in rows) {
        final row = r as Map<String, dynamic>;
        final t1 = (row['Team1']?.toString() ?? '').trim();
        final t2 = (row['Team2']?.toString() ?? '').trim();
        if (t1.isNotEmpty) names.add(t1);
        if (t2.isNotEmpty) names.add(t2);
      }
      return names.toList();
    } catch (_) { return []; }
  }

  Future<List<LckMatch>> getLeaguepediaYearSchedule(int year) async {
    final cacheKey = 'lp_year3_$year';
    final hit = _cache[cacheKey];
    if (hit != null && DateTime.now().millisecondsSinceEpoch - hit.ts < _cacheTtlMs) {
      await _fetchLpTeamRoster(_extractLpTeamNamesFromBody(hit.body));
      return _parseLpYearSchedule(hit.body, await _getTeamImagesByCode());
    }

    // 과거 연도: 디스크 캐시 우선 (불변 데이터)
    final isPastYear = year < DateTime.now().year;
    if (isPastYear) {
      final disk = await _diskRead(cacheKey);
      if (disk != null && disk.isNotEmpty) {
        _cache[cacheKey] = (body: disk, ts: DateTime.now().millisecondsSinceEpoch);
        await _fetchLpTeamRoster(_extractLpTeamNamesFromBody(disk));
        return _parseLpYearSchedule(disk, await _getTeamImagesByCode());
      }
    }

    final where = [
      "OverviewPage LIKE 'LCK/$year%'",
      "OverviewPage LIKE 'MSI/$year%'",
      "OverviewPage LIKE '$year Mid-Season Invitational%'",
      "OverviewPage LIKE 'Worlds/$year%'",
      "OverviewPage LIKE '$year Season World Championship%'",
      "OverviewPage LIKE 'Esports World Cup $year%'",
      "OverviewPage LIKE 'First Stand/$year%'",
      "OverviewPage LIKE '$year First Stand%'",
      "OverviewPage LIKE 'Season Kickoff/$year%'",
    ].join(' OR ');

    try {
      final uri = Uri.https('lol.fandom.com', '/wiki/Special:CargoExport', {
        'tables': 'MatchSchedule',
        'fields': 'Tab,Team1,Team2,Team1Score,Team2Score,Winner,DateTime_UTC,OverviewPage,BestOf',
        'where': '($where)',
        'order by': 'DateTime_UTC ASC',
        'format': 'json',
        'limit': '1000',
      });
      final res = await http.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200 || res.body.isEmpty) return [];
      _cache[cacheKey] = (body: res.body, ts: DateTime.now().millisecondsSinceEpoch);
      if (isPastYear) _diskWrite(cacheKey, res.body);
      await _fetchLpTeamRoster(_extractLpTeamNamesFromBody(res.body));
      return _parseLpYearSchedule(res.body, await _getTeamImagesByCode());
    } catch (e) {
      debugPrint('[LP] getLeaguepediaYearSchedule $year error: $e');
      return [];
    }
  }

  List<LckMatch> _parseLpYearSchedule(String body, Map<String, String> imagesByCode) {
    try {
      final rows = jsonDecode(body) as List;
      final matches = <LckMatch>[];
      for (int i = 0; i < rows.length; i++) {
        final row = rows[i] as Map<String, dynamic>;
        final t1Name = (row['Team1']?.toString() ?? '').trim();
        final t2Name = (row['Team2']?.toString() ?? '').trim();
        if (t1Name.isEmpty || t2Name.isEmpty) continue;

        // 코드는 정적 맵(역사적 이름 보존) 우선 → 파생; LP Teams Short는 현재 상태라 역사 데이터에 부정확
        final t1Code = _lpNameToCode[t1Name] ?? _deriveTeamCode(t1Name);
        final t2Code = _lpNameToCode[t2Name] ?? _deriveTeamCode(t2Name);
        _dynamicTeamNames.putIfAbsent(t1Code, () => {}).add(t1Name);
        _dynamicTeamNames.putIfAbsent(t2Code, () => {}).add(t2Name);

        final dateStr = (row['DateTime UTC']?.toString() ?? row['DateTime_UTC']?.toString() ?? '').trim();
        if (dateStr.length < 10) continue;
        DateTime startTime;
        try {
          // Leaguepedia DateTime_UTC is always UTC — append Z so Dart parses correctly
          final utcStr = dateStr.contains('Z') || dateStr.contains('+')
              ? dateStr
              : dateStr.replaceAll(' ', 'T') + 'Z';
          startTime = DateTime.parse(utcStr).toLocal();
        } catch (_) { continue; }

        final winnerName = (row['Winner']?.toString() ?? '').trim();
        final winnerCode = _lpNameToCode[winnerName] ?? (winnerName.isNotEmpty ? _deriveTeamCode(winnerName) : null);
        final t1Score = int.tryParse(row['Team1Score']?.toString() ?? '') ?? 0;
        final t2Score = int.tryParse(row['Team2Score']?.toString() ?? '') ?? 0;
        final bestOf = int.tryParse(row['BestOf']?.toString() ?? '') ?? 3;
        final overviewPage = (row['OverviewPage']?.toString() ?? '').trim();
        final tab = (row['Tab']?.toString() ?? '').trim();
        final state = winnerName.isNotEmpty ? 'completed' : 'unstarted';

        matches.add(LckMatch(
          id: 'lp_${overviewPage}_${t1Code}_${t2Code}_$i',
          startTime: startTime,
          state: state,
          blockName: tab.isNotEmpty ? tab : overviewPage,
          team1: MatchTeam(
            name: t1Name, code: t1Code,
            imageUrl: (_lpTeamData[t1Name]?.imageUrl.isNotEmpty == true)
                ? _lpTeamData[t1Name]!.imageUrl
                : (imagesByCode[t1Code] ?? _defunctTeamImages[t1Code] ?? ''),
            outcome: winnerCode == null ? null : (winnerCode == t1Code ? 'win' : 'loss'),
            gameWins: t1Score, wins: 0, losses: 0,
          ),
          team2: MatchTeam(
            name: t2Name, code: t2Code,
            imageUrl: (_lpTeamData[t2Name]?.imageUrl.isNotEmpty == true)
                ? _lpTeamData[t2Name]!.imageUrl
                : (imagesByCode[t2Code] ?? _defunctTeamImages[t2Code] ?? ''),
            outcome: winnerCode == null ? null : (winnerCode == t2Code ? 'win' : 'loss'),
            gameWins: t2Score, wins: 0, losses: 0,
          ),
          bestOf: bestOf,
          hasVod: false,
          leagueName: _overviewToLeagueName(overviewPage),
          leagueSlug: _overviewToSlug(overviewPage),
        ));
      }
      return matches;
    } catch (e) {
      debugPrint('[LP] parse error: $e');
      return [];
    }
  }

  String _deriveTeamCode(String name) {
    if (name.isEmpty) return '???';
    final words = name.trim().split(RegExp(r'\s+'));
    final first = words[0];
    // 첫 단어가 짧으면 그게 팀 약어 (G2, T1, NIP 등)
    if (first.length <= 4 && first == first.toUpperCase()) return first;
    // 그 외엔 이니셜
    final initials = words.map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
    return initials.substring(0, initials.length.clamp(1, 4));
  }

  // match.id = 'lp_${overviewPage}_${t1Code}_${t2Code}_$i' 에서 overviewPage 역추출
  String? _extractOverviewPageFromId(String id, String t1Code, String t2Code) {
    const prefix = 'lp_';
    if (!id.startsWith(prefix)) return null;
    final body = id.substring(prefix.length);
    final suffix = '_${t1Code}_${t2Code}_';
    final idx = body.lastIndexOf(suffix);
    if (idx <= 0) return null;
    return body.substring(0, idx);
  }

  String _overviewToSlug(String page) {
    if (page.startsWith('MSI/') || RegExp(r'^\d{4} Mid-Season Invitational').hasMatch(page)) return 'msi';
    if (page.startsWith('Worlds/') || RegExp(r'^\d{4} Season World Championship').hasMatch(page)) return 'worlds';
    if (page.startsWith('Esports World Cup')) return 'ewc';
    if (page.startsWith('First Stand/') || page.startsWith('Season Kickoff/') ||
        RegExp(r'^\d{4} First Stand').hasMatch(page)) return 'first_stand';
    if (page.contains('Cup')) return 'lck_cup';
    return 'lck';
  }

  String _overviewToLeagueName(String page) {
    if (page.startsWith('MSI/') || RegExp(r'^\d{4} Mid-Season Invitational').hasMatch(page)) return 'MSI';
    if (page.startsWith('Worlds/') || RegExp(r'^\d{4} Season World Championship').hasMatch(page)) return 'Worlds';
    if (page.startsWith('Esports World Cup')) return 'EWC';
    if (page.startsWith('First Stand/') || page.startsWith('Season Kickoff/') ||
        RegExp(r'^\d{4} First Stand').hasMatch(page)) return 'First Stand';
    if (page.contains('Cup')) return 'LCK Cup';
    return 'LCK';
  }

  // 과거 시즌 LCK 정규리그 순위표 (Leaguepedia)
  // 반환: 스플릿 이름 → 순위 리스트 (예: {"Spring": [...], "Summer": [...]})
  Future<Map<String, List<Standing>>> getLeaguepediaStandings(int year) async {
    final cacheKey = 'lp_standings10_$year';
    final hit = _cache[cacheKey];
    if (hit != null && DateTime.now().millisecondsSinceEpoch - hit.ts < _cacheTtlMs) {
      final teamNames = (jsonDecode(hit.body) as List)
          .expand((r) => [r['Team1']?.toString() ?? '', r['Team2']?.toString() ?? ''])
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
      await _fetchLpTeamRoster(teamNames);
      return _parseLpStandings(hit.body, await _getTeamImagesByCode());
    }

    try {
      final uri = Uri.https('lol.fandom.com', '/wiki/Special:CargoExport', {
        'tables': 'MatchSchedule',
        'fields': 'Team1,Team2,Team1Score,Team2Score,Winner,OverviewPage',
        'where': "OverviewPage LIKE 'LCK/$year%' AND OverviewPage NOT LIKE '%Playoffs%' AND OverviewPage NOT LIKE '%Regional%' AND OverviewPage NOT LIKE '%Cup%' AND OverviewPage NOT LIKE '%Qualifier%' AND OverviewPage NOT LIKE '%Promotion%' AND OverviewPage NOT LIKE '%Road to MSI%'",
        'order by': 'DateTime_UTC ASC',
        'format': 'json',
        'limit': '500',
      });
      final res = await http.get(uri, headers: const {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200 || res.body.isEmpty) return {};
      final decoded = jsonDecode(res.body) as List;
      debugPrint('[LP] standings $year: ${decoded.length} rows');
      _cache[cacheKey] = (body: res.body, ts: DateTime.now().millisecondsSinceEpoch);
      // LP 팀 이미지 로드 (LoL Esports API에 없는 해산/개명 팀 대응)
      final teamNames = decoded
          .expand((r) => [r['Team1']?.toString() ?? '', r['Team2']?.toString() ?? ''])
          .where((n) => n.isNotEmpty)
          .toSet()
          .toList();
      await _fetchLpTeamRoster(teamNames);
      return _parseLpStandings(res.body, await _getTeamImagesByCode());
    } catch (e) {
      debugPrint('[LP] getLeaguepediaStandings $year error: $e');
      return {};
    }
  }

  Map<String, List<Standing>> _parseLpStandings(String body, Map<String, String> imagesByCode) {
    try {
      final rows = jsonDecode(body) as List;
      final splitMap = <String, Map<String, ({int w, int l, int gw, int gl})>>{};
      // split → code → LP팀명 (시대별 표시명 추출용)
      final splitLpNames = <String, Map<String, String>>{};

      for (final r in rows) {
        final row = r as Map<String, dynamic>;
        final t1Name = (row['Team1']?.toString() ?? '').trim();
        final t2Name = (row['Team2']?.toString() ?? '').trim();
        final winnerName = (row['Winner']?.toString() ?? '').trim();
        if (t1Name.isEmpty || t2Name.isEmpty || winnerName.isEmpty) continue;

        final t1Code = _lpNameToCode[t1Name] ?? _deriveTeamCode(t1Name);
        final t2Code = _lpNameToCode[t2Name] ?? _deriveTeamCode(t2Name);
        final String winnerCode;
        if (winnerName == '1') {
          winnerCode = t1Code;
        } else if (winnerName == '2') {
          winnerCode = t2Code;
        } else {
          winnerCode = _lpNameToCode[winnerName] ?? _deriveTeamCode(winnerName);
        }

        final t1Score = int.tryParse(row['Team1Score']?.toString() ?? '') ?? 0;
        final t2Score = int.tryParse(row['Team2Score']?.toString() ?? '') ?? 0;

        final overviewPage = (row['OverviewPage']?.toString() ?? '').trim();
        final parts = overviewPage.split('/');
        String splitName;
        if (parts.length >= 4) {
          splitName = parts[parts.length - 2];
        } else {
          splitName = parts.length >= 3 ? parts[2] : 'Regular Season';
        }
        if (splitName.endsWith(' Season')) {
          splitName = splitName.substring(0, splitName.length - ' Season'.length);
        }

        splitMap.putIfAbsent(splitName, () => {});
        splitLpNames.putIfAbsent(splitName, () => {});
        final data = splitMap[splitName]!;
        final lpNames = splitLpNames[splitName]!;
        lpNames[t1Code] = t1Name;
        lpNames[t2Code] = t2Name;

        final loserCode = winnerCode == t1Code ? t2Code : t1Code;
        final wGw = winnerCode == t1Code ? t1Score : t2Score;
        final wGl = winnerCode == t1Code ? t2Score : t1Score;

        final wOld = data[winnerCode] ?? (w: 0, l: 0, gw: 0, gl: 0);
        data[winnerCode] = (w: wOld.w + 1, l: wOld.l, gw: wOld.gw + wGw, gl: wOld.gl + wGl);

        final lOld = data[loserCode] ?? (w: 0, l: 0, gw: 0, gl: 0);
        data[loserCode] = (w: lOld.w, l: lOld.l + 1, gw: lOld.gw + wGl, gl: lOld.gl + wGw);
      }

      // 2025 형식: "Rounds 1-2" + "Rounds 3-5" → "정규시즌"으로 합산
      final r12Data = splitMap.remove('Rounds 1-2');
      final r35Data = splitMap.remove('Rounds 3-5');
      final r12Names = splitLpNames.remove('Rounds 1-2') ?? {};
      final r35Names = splitLpNames.remove('Rounds 3-5') ?? {};
      if (r12Data != null || r35Data != null) {
        final merged = <String, ({int w, int l, int gw, int gl})>{};
        final mergedNames = <String, String>{};
        for (final src in [r12Data, r35Data]) {
          if (src == null) continue;
          for (final entry in src.entries) {
            final ex = merged[entry.key];
            merged[entry.key] = ex == null
                ? entry.value
                : (w: ex.w + entry.value.w, l: ex.l + entry.value.l,
                   gw: ex.gw + entry.value.gw, gl: ex.gl + entry.value.gl);
          }
        }
        for (final src in [r35Names, r12Names]) {
          src.forEach((k, v) => mergedNames.putIfAbsent(k, () => v));
        }
        splitMap['정규시즌'] = merged;
        splitLpNames['정규시즌'] = mergedNames;
      }

      final result = <String, List<Standing>>{};
      for (final entry in splitMap.entries) {
        final lpNamesForSplit = splitLpNames[entry.key] ?? {};
        final standings = entry.value.entries.map((e) {
          final code = e.key;
          final lpName = lpNamesForSplit[code] ?? code;
          final displayName = _lpShortName[lpName] ?? code;
          final imageUrl = (_lpTeamData[lpName]?.imageUrl.isNotEmpty == true)
              ? _lpTeamData[lpName]!.imageUrl
              : (imagesByCode[code] ??
                 _defunctTeamImages[code] ??
                 _lpTeamData.entries
                     .where((lp) => (_lpNameToCode[lp.key] ?? _deriveTeamCode(lp.key)) == code)
                     .map((lp) => lp.value.imageUrl)
                     .firstWhere((u) => u.isNotEmpty, orElse: () => ''));
          return Standing(
            rank: 0,
            teamName: displayName,
            teamCode: code,
            imageUrl: imageUrl,
            wins: e.value.w,
            losses: e.value.l,
            gameDiff: e.value.gw - e.value.gl,
            gameWins: e.value.gw,
            gameLosses: e.value.gl,
          );
        }).toList()
          ..sort((a, b) {
            final w = b.wins.compareTo(a.wins);
            if (w != 0) return w;
            final l = a.losses.compareTo(b.losses);
            if (l != 0) return l;
            return b.gameDiff.compareTo(a.gameDiff);
          });

        for (int i = 0; i < standings.length; i++) {
          standings[i] = standings[i].copyWith(rank: i + 1);
        }
        result[entry.key] = standings;
      }
      return result;
    } catch (e) {
      debugPrint('[LP] parse standings error: $e');
      return {};
    }
  }

  // 연도별 Worlds/MSI 우승·준우승 (코드 + 이미지)
  Future<Map<String, List<({String code, String imageUrl})>>> getInternationalPlacements(int year) async {
    final cacheKey = 'intl_placements3_$year';
    final hit = _cache[cacheKey];
    if (hit != null && DateTime.now().millisecondsSinceEpoch - hit.ts < _cacheTtlMs) {
      return _decodeIntlPlacements(hit.body);
    }
    final tournaments = <String, String>{
      'Worlds': '$year Season World Championship/Main Event',
      'MSI':    '$year Mid-Season Invitational',
    };
    final result = <String, List<({String code, String imageUrl})>>{};
    for (final entry in tournaments.entries) {
      final placement = await _fetchTournamentTop2(entry.value);
      if (placement.isNotEmpty) result[entry.key] = placement;
    }
    final encoded = jsonEncode(result.map((k, v) =>
        MapEntry(k, v.map((t) => {'code': t.code, 'imageUrl': t.imageUrl}).toList())));
    _cache[cacheKey] = (body: encoded, ts: DateTime.now().millisecondsSinceEpoch);
    return result;
  }

  Future<List<({String code, String imageUrl})>> _fetchTournamentTop2(String overviewPage) async {
    try {
      final uri = Uri.https('lol.fandom.com', '/wiki/Special:CargoExport', {
        'tables': 'MatchSchedule',
        'fields': 'Team1,Team2,Winner,Tab',
        'where': "OverviewPage = '$overviewPage' AND Tab = 'Finals'",
        'format': 'json',
        'limit': '5',
      });
      final res = await http.get(uri, headers: const {'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || res.body.isEmpty) return [];
      final rows = jsonDecode(res.body) as List;
      if (rows.isEmpty) return [];
      final r = rows.first as Map<String, dynamic>;
      final t1 = (r['Team1']?.toString() ?? '').trim();
      final t2 = (r['Team2']?.toString() ?? '').trim();
      final w = r['Winner'];
      final winnerName = (w == 1 || w == '1') ? t1 : t2;
      final loserName  = (w == 1 || w == '1') ? t2 : t1;
      if (winnerName.isEmpty || loserName.isEmpty) return [];

      // 해외 팀 포함한 이미지 로드
      await _fetchLpTeamRoster([winnerName, loserName]);

      final p1Code = _lpNameToCode[winnerName] ?? _deriveTeamCode(winnerName);
      final p2Code = _lpNameToCode[loserName]  ?? _deriveTeamCode(loserName);
      final p1Image = _lpTeamData[winnerName]?.imageUrl ?? '';
      final p2Image = _lpTeamData[loserName]?.imageUrl  ?? '';
      return [
        (code: p1Code, imageUrl: p1Image),
        (code: p2Code, imageUrl: p2Image),
      ];
    } catch (_) { return []; }
  }

  Map<String, List<({String code, String imageUrl})>> _decodeIntlPlacements(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(k, (v as List).map((e) {
        final m = e as Map<String, dynamic>;
        return (code: m['code'].toString(), imageUrl: m['imageUrl'].toString());
      }).toList()));
    } catch (_) { return {}; }
  }

  String _slugToLpPageFilter(String slug, int year) {
    switch (slug) {
      case 'msi': return "_pageName LIKE 'MSI/$year%' OR _pageName LIKE '$year Mid-Season Invitational%'";
      case 'worlds': return "_pageName LIKE 'Worlds/$year%' OR _pageName LIKE '$year Season World Championship%'";
      case 'ewc': return "_pageName LIKE 'Esports World Cup $year%'";
      case 'first_stand': return "_pageName LIKE 'First Stand/$year%' OR _pageName LIKE '${year} First Stand%' OR _pageName LIKE 'Season Kickoff/$year%'";
      case 'lck_cup': return "_pageName LIKE 'LCK/$year%Cup%'";
      default: return "_pageName LIKE 'LCK/$year%'";
    }
  }

  // Leaguepedia ScoreboardGames + ScoreboardPlayers로 과거 경기 상세 로드
  Future<MatchDetail?> getLeaguepediaMatchDetail(LckMatch match) async {
    final t1Code = match.team1.code;
    final t2Code = match.team2.code;
    final t1Aliases = _leaguepediaTeamAliases[t1Code]
        ?? (_dynamicTeamNames[t1Code]?.toList())
        ?? [t1Code];
    final t2Aliases = _leaguepediaTeamAliases[t2Code]
        ?? (_dynamicTeamNames[t2Code]?.toList())
        ?? [t2Code];

    final cacheKey = 'lpdetail3_${match.id}';
    final hit = _cache[cacheKey];
    if (hit != null && DateTime.now().millisecondsSinceEpoch - hit.ts < _cacheTtlMs) {
      if (hit.body.isEmpty) return null;
      final cached = jsonDecode(hit.body) as Map<String, dynamic>;
      return _buildLpMatchDetail(
        cached['games'] as List, cached['players'] as List,
        t1Aliases, t2Aliases, t1Code, t2Code,
      );
    }

    // 과거 연도 경기: 디스크 캐시 확인 (불변 데이터)
    final isPastMatch = match.startTime.year < DateTime.now().year;
    if (isPastMatch) {
      final disk = await _diskRead(cacheKey);
      if (disk != null && disk.isNotEmpty) {
        _cache[cacheKey] = (body: disk, ts: DateTime.now().millisecondsSinceEpoch);
        final cached = jsonDecode(disk) as Map<String, dynamic>;
        return _buildLpMatchDetail(
          cached['games'] as List, cached['players'] as List,
          t1Aliases, t2Aliases, t1Code, t2Code,
        );
      }
    }

    final dateUtc = match.startTime.toUtc();
    final d0 = dateUtc.subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
    final d1 = dateUtc.add(const Duration(days: 2)).toIso8601String().substring(0, 10);
    final year = match.startTime.year;

    // OverviewPage를 match.id에서 역추출해 정밀 필터 우선 사용
    // match.id 형식: 'lp_${overviewPage}_${t1Code}_${t2Code}_$i'
    final overviewPage = _extractOverviewPageFromId(match.id, t1Code, t2Code);
    final pageFilter = overviewPage != null
        ? "_pageName LIKE '${overviewPage.replaceAll("'", "\\'")}%'"
        : _slugToLpPageFilter(match.leagueSlug, year);

    // Each team must appear in the match (either side)
    final t1InMatch = t1Aliases.map((a) {
      final e = a.replaceAll("'", "\\'");
      return "Team1='$e' OR Team2='$e'";
    }).join(' OR ');
    final t2InMatch = t2Aliases.map((a) {
      final e = a.replaceAll("'", "\\'");
      return "Team1='$e' OR Team2='$e'";
    }).join(' OR ');

    // Player query: match any alias from either team, scoped by date only
    final allAliases = [...t1Aliases, ...t2Aliases];
    final playerTeamFilter = allAliases.map((a) => "Team='${a.replaceAll("'", "\\'")}'").join(' OR ');

    const lpHeaders = {'User-Agent': 'Mozilla/5.0', 'Accept': 'application/json'};

    try {
      final gamesUri = Uri.https('lol.fandom.com', '/wiki/Special:CargoExport', {
        'tables': 'ScoreboardGames',
        'fields': 'Team1,Team2,WinTeam,Team1Kills,Team2Kills,Team1Gold,Team2Gold,'
            'Team1Towers,Team2Towers,Team1Barons,Team2Barons,Team1Dragons,Team2Dragons,'
            'Team1Elders,Team2Elders,Team1RiftHeralds,Team2RiftHeralds,'
            'Team1VoidGrubs,Team2VoidGrubs,Team1Bans,Team2Bans,Gamelength,DateTime_UTC',
        'where': '($pageFilter) AND ($t1InMatch) AND ($t2InMatch) AND DateTime_UTC > \'$d0\' AND DateTime_UTC < \'$d1\'',
        'order_by': 'DateTime_UTC ASC',
        'format': 'json',
        'limit': '10',
      });

      final playersUri = Uri.https('lol.fandom.com', '/wiki/Special:CargoExport', {
        'tables': 'ScoreboardPlayers',
        'fields': 'Team,Champion,Kills,Deaths,Assists,DateTime_UTC',
        'where': '($playerTeamFilter) AND DateTime_UTC > \'$d0\' AND DateTime_UTC < \'$d1\'',
        'order_by': 'DateTime_UTC ASC',
        'format': 'json',
        'limit': '100',
      });

      final results = await Future.wait([
        http.get(gamesUri, headers: lpHeaders).timeout(const Duration(seconds: 15)),
        http.get(playersUri, headers: lpHeaders).timeout(const Duration(seconds: 15)),
      ]);

      final gamesRes = results[0];
      final playersRes = results[1];

      if (gamesRes.statusCode != 200 || gamesRes.body.isEmpty) {
        _cache[cacheKey] = (body: '', ts: DateTime.now().millisecondsSinceEpoch);
        return null;
      }

      final gamesData = jsonDecode(gamesRes.body) as List;
      final playersData = (playersRes.statusCode == 200 && playersRes.body.isNotEmpty)
          ? jsonDecode(playersRes.body) as List
          : <dynamic>[];

      debugPrint('[LP] detail games=${gamesData.length} players=${playersData.length}');
      final encoded = jsonEncode({'games': gamesData, 'players': playersData});
      _cache[cacheKey] = (body: encoded, ts: DateTime.now().millisecondsSinceEpoch);
      if (isPastMatch) _diskWrite(cacheKey, encoded);

      return _buildLpMatchDetail(gamesData, playersData, t1Aliases, t2Aliases, t1Code, t2Code);
    } catch (e) {
      debugPrint('[LP] getLeaguepediaMatchDetail error: $e');
      return null;
    }
  }

  MatchDetail? _buildLpMatchDetail(
    List gamesData,
    List playersData,
    List<String> t1Aliases,
    List<String> t2Aliases,
    String t1Code,
    String t2Code,
  ) {
    // 1. Filter rows to this matchup, sort by DateTime_UTC
    final matched = <Map<String, dynamic>>[];
    for (final r in gamesData) {
      final row = r as Map<String, dynamic>;
      final rt1 = row['Team1']?.toString().trim() ?? '';
      final rt2 = row['Team2']?.toString().trim() ?? '';
      final fwd = t1Aliases.contains(rt1) && t2Aliases.contains(rt2);
      final rev = t2Aliases.contains(rt1) && t1Aliases.contains(rt2);
      if (!fwd && !rev) continue;
      matched.add({...row, '_fwd': fwd});
    }
    if (matched.isEmpty) return null;

    matched.sort((a, b) {
      final da = a['DateTime_UTC']?.toString() ?? a['DateTime UTC']?.toString() ?? '';
      final db = b['DateTime_UTC']?.toString() ?? b['DateTime UTC']?.toString() ?? '';
      return da.compareTo(db);
    });

    // 2. DateTime_UTC → 1-based game number for player matching
    final dtToGameN = <String, int>{};
    for (int i = 0; i < matched.length; i++) {
      final dt = matched[i]['DateTime_UTC']?.toString() ??
                 matched[i]['DateTime UTC']?.toString() ?? '';
      if (dt.isNotEmpty) dtToGameN[dt] = i + 1;
    }

    // 3. Players → picks + assists per game, keyed by our t1/t2
    final picks = <int, Map<String, List<String>>>{};
    final teamAssists = <int, Map<String, int>>{};

    for (final r in playersData) {
      final row = r as Map<String, dynamic>;
      final dt = row['DateTime_UTC']?.toString() ?? row['DateTime UTC']?.toString() ?? '';
      final gameN = dtToGameN[dt];
      if (gameN == null) continue;
      final team = row['Team']?.toString().trim() ?? '';
      final champ = row['Champion']?.toString().trim() ?? '';
      final isT1 = t1Aliases.contains(team);
      final isT2 = t2Aliases.contains(team);
      if (!isT1 && !isT2) continue;
      final side = isT1 ? 't1' : 't2';
      picks.putIfAbsent(gameN, () => {'t1': [], 't2': []});
      if (champ.isNotEmpty) picks[gameN]![side]!.add(_toDDragonId(champ));
      final ast = int.tryParse(row['Assists']?.toString() ?? '') ?? 0;
      teamAssists.putIfAbsent(gameN, () => {'t1': 0, 't2': 0});
      teamAssists[gameN]![side] = (teamAssists[gameN]![side] ?? 0) + ast;
    }

    // 4. Build GameDetail list
    // LP 데이터는 드래곤 개수만 있고 타입 정보 없음 → 'lp_dragon' 마커 사용
    List<String> makeDragons(int count, int elders) => [
      ...List.filled(count, 'lp_dragon'),
      ...List.filled(elders, 'elder'),
    ];

    List<String> parseBans(dynamic raw) {
      if (raw is List) return raw.map((e) => _toDDragonId(e.toString())).where((e) => e.isNotEmpty).toList();
      if (raw is String && raw.isNotEmpty) {
        return raw.split(',').map((e) => _toDDragonId(e.trim())).where((e) => e.isNotEmpty).toList();
      }
      return [];
    }

    final games = <GameDetail>[];
    for (int i = 0; i < matched.length; i++) {
      final row = matched[i];
      int lpInt(String k) => (row[k] as num?)?.toInt() ?? 0;
      final gameN = i + 1;
      final fwd = row['_fwd'] as bool;

      final winTeam = row['WinTeam']?.toString().trim() ?? '';
      String? winner;
      if (t1Aliases.contains(winTeam)) winner = t1Code;
      else if (t2Aliases.contains(winTeam)) winner = t2Code;
      else if (winTeam.isNotEmpty) winner = _lpNameToCode[winTeam];

      int? duration;
      final gl = row['Gamelength']?.toString() ?? '';
      if (gl.contains(':')) {
        final p = gl.split(':');
        if (p.length == 2) duration = (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
      } else {
        duration = int.tryParse(gl);
      }

      final t1k = lpInt(fwd ? 'Team1Kills' : 'Team2Kills');
      final t2k = lpInt(fwd ? 'Team2Kills' : 'Team1Kills');
      final gPicks = picks[gameN];
      final gAst = teamAssists[gameN];

      games.add(GameDetail(
        number: gameN,
        winnerCode: winner,
        team1IsBlue: true,
        durationSeconds: duration,
        team1Stats: GameTeamStats(
          kills: t1k,
          deaths: t2k,
          assists: gAst?['t1'] ?? 0,
          gold: lpInt(fwd ? 'Team1Gold' : 'Team2Gold'),
          towers: lpInt(fwd ? 'Team1Towers' : 'Team2Towers'),
          barons: lpInt(fwd ? 'Team1Barons' : 'Team2Barons'),
          inhibitors: 0,
          heralds: lpInt(fwd ? 'Team1RiftHeralds' : 'Team2RiftHeralds'),
          voidGrubs: lpInt(fwd ? 'Team1VoidGrubs' : 'Team2VoidGrubs'),
          dragonTypes: makeDragons(
            lpInt(fwd ? 'Team1Dragons' : 'Team2Dragons'),
            lpInt(fwd ? 'Team1Elders' : 'Team2Elders'),
          ),
          picks: gPicks?['t1'] ?? [],
        ),
        team2Stats: GameTeamStats(
          kills: t2k,
          deaths: t1k,
          assists: gAst?['t2'] ?? 0,
          gold: lpInt(fwd ? 'Team2Gold' : 'Team1Gold'),
          towers: lpInt(fwd ? 'Team2Towers' : 'Team1Towers'),
          barons: lpInt(fwd ? 'Team2Barons' : 'Team1Barons'),
          inhibitors: 0,
          heralds: lpInt(fwd ? 'Team2RiftHeralds' : 'Team1RiftHeralds'),
          voidGrubs: lpInt(fwd ? 'Team2VoidGrubs' : 'Team1VoidGrubs'),
          dragonTypes: makeDragons(
            lpInt(fwd ? 'Team2Dragons' : 'Team1Dragons'),
            lpInt(fwd ? 'Team2Elders' : 'Team1Elders'),
          ),
          picks: gPicks?['t2'] ?? [],
        ),
        team1Bans: parseBans(row[fwd ? 'Team1Bans' : 'Team2Bans']),
        team2Bans: parseBans(row[fwd ? 'Team2Bans' : 'Team1Bans']),
      ));
    }

    if (games.isEmpty) return null;
    return MatchDetail(games: games, team1Code: t1Code);
  }

  Future<List<LckMatch>> getLiveMatches() async {
    return _get(
      'getLive?hl=ko-KR',
      (data) {
        final events = data['schedule']['events'] as List;
        return events
            .where((e) => e['type'] == 'match')
            .map((e) => LckMatch.fromJson(e as Map<String, dynamic>))
            .toList();
      },
    );
  }
}
