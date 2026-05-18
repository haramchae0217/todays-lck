import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api.dart';
import '../models/match.dart';
import '../models/match_detail.dart' show MatchDetail, GameTeamStats;
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
    return _get(
      endpoint,
      (data) {
        final schedule = data['schedule'] as Map<String, dynamic>;
        final events = schedule['events'] as List;
        final pages =
            schedule['pages'] as Map<String, dynamic>? ?? {};
        final matches = events
            .where((e) => e['type'] == 'match')
            .map((e) => LckMatch.fromJson(e as Map<String, dynamic>))
            .toList();
        return ScheduleResult(
          matches: matches,
          olderToken: pages['older'] as String?,
          newerToken: pages['newer'] as String?,
        );
      },
      cache: pageToken == null, // 첫 페이지만 캐시
    );
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

  // 실제 Leaguepedia 팀 이름 (2026 시즌 기준, 스폰서 변경 반영)
  static const _leaguepediaTeamAliases = <String, List<String>>{
    'T1':  ['T1'],
    'GEN': ['Gen.G'],
    'HLE': ['Hanwha Life Esports', 'HLE'],
    'KT':  ['KT Rolster'],
    'DK':  ['Dplus Kia', 'Dplus KIA'],
    'NS':  ['Nongshim RedForce'],
    'BRO': ['HANJIN BRION', 'BRION'],
    'BFX': ['BNK FEARX', 'BNK FearX'],
    'KRX': ['Kiwoom DRX', 'DRX'],
    'DNS': ['DN SOOPers', 'DN Freecs'],
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

  // Special:CargoExport 엔드포인트 — api.php와 달리 rate limit 없음
  Future<List<({int gameN, int heralds1, int heralds2, int grubs1, int grubs2, List<String> bans1, List<String> bans2})>>
      _getLeaguepediaStats(String team1Code, String team2Code, DateTime matchDate) async {
    final t1Aliases = _leaguepediaTeamAliases[team1Code] ?? [];
    final t2Aliases = _leaguepediaTeamAliases[team2Code] ?? [];
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
        'where': "_pageName LIKE 'LCK/2026%' AND DateTime_UTC > '$d0' AND DateTime_UTC < '$d1'",
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
        if (game.chapterStartUtc != null && w.lastFrameTime != null) {
          final gameStart = await _getGameStartTime(game.gameId!, game.chapterStartUtc!);
          if (gameStart != null) {
            final secs = w.lastFrameTime!.difference(gameStart).inSeconds;
            if (secs > 0 && secs < 7200) accurateDuration = secs;
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
