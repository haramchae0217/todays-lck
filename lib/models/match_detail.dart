class GameTeamStats {
  final int kills;
  final int deaths;
  final int assists;
  final int gold;
  final int towers;
  final int barons;
  final int inhibitors;
  final int heralds;
  final int voidGrubs;
  final List<String> dragonTypes; // includes 'elder'
  final List<String> picks; // champion internal names

  const GameTeamStats({
    required this.kills,
    this.deaths = 0,
    this.assists = 0,
    required this.gold,
    required this.towers,
    required this.barons,
    this.dragonTypes = const [],
    required this.inhibitors,
    this.heralds = 0,
    this.voidGrubs = 0,
    this.picks = const [],
  });

  int get dragons => dragonTypes.where((d) => d != 'elder').length;
  int get elders => dragonTypes.where((d) => d == 'elder').length;

  GameTeamStats copyWith({int? heralds, int? voidGrubs}) => GameTeamStats(
        kills: kills,
        deaths: deaths,
        assists: assists,
        gold: gold,
        towers: towers,
        barons: barons,
        dragonTypes: dragonTypes,
        inhibitors: inhibitors,
        heralds: heralds ?? this.heralds,
        voidGrubs: voidGrubs ?? this.voidGrubs,
        picks: picks,
      );

  factory GameTeamStats.fromWindowJson(
    Map<String, dynamic> json, {
    List<String> picks = const [],
  }) {
    final dragons = (json['dragons'] as List? ?? [])
        .map((d) => d.toString().toLowerCase())
        .toList();

    // Aggregate deaths & assists from participants in the frame
    int deaths = 0, assists = 0;
    for (final p in (json['participants'] as List? ?? [])) {
      deaths += (p['deaths'] as int? ?? 0);
      assists += (p['assists'] as int? ?? 0);
    }

    return GameTeamStats(
      kills: json['totalKills'] as int? ?? 0,
      deaths: deaths,
      assists: assists,
      gold: json['totalGold'] as int? ?? 0,
      towers: json['towers'] as int? ?? 0,
      barons: json['barons'] as int? ?? 0,
      dragonTypes: dragons,
      inhibitors: json['inhibitors'] as int? ?? 0,
      heralds: json['riftHeralds'] as int? ?? json['heralds'] as int? ?? 0,
      voidGrubs: json['voidGrubs'] as int? ?? json['voidMonsters'] as int? ?? json['grubs'] as int? ?? 0,
      picks: picks,
    );
  }
}

class GameDetail {
  final int number;
  final String? winnerCode;
  final String? gameId;
  final String? team1Side; // "blue" or "red"
  final bool? team1IsBlue; // match.team1 기준 블루 여부 (enrichWithWindowData에서 설정)
  final int? durationSeconds;
  final GameTeamStats? team1Stats;
  final GameTeamStats? team2Stats;
  final String? patchVersion; // e.g. "26.9"
  final List<String> team1Bans; // champion internal names
  final List<String> team2Bans;
  final DateTime? firstFrameTime; // UTC timestamp of first game frame
  final DateTime? chapterStartUtc; // VOD chapter start = broadcastStart + startMillis
  final DateTime? gameStartUtc; // actual in-game start (computed from window API)

  const GameDetail({
    required this.number,
    this.winnerCode,
    this.gameId,
    this.team1Side,
    this.team1IsBlue,
    this.durationSeconds,
    this.team1Stats,
    this.team2Stats,
    this.patchVersion,
    this.team1Bans = const [],
    this.team2Bans = const [],
    this.firstFrameTime,
    this.chapterStartUtc,
    this.gameStartUtc,
  });

  GameDetail withWindowData({
    String? winnerCode,
    GameTeamStats? team1Stats,
    GameTeamStats? team2Stats,
    int? durationSeconds,
    String? patchVersion,
    bool? team1IsBlue,
    DateTime? gameStartUtc,
  }) =>
      GameDetail(
        number: number,
        winnerCode: winnerCode ?? this.winnerCode,
        gameId: gameId,
        team1Side: team1Side,
        team1IsBlue: team1IsBlue ?? this.team1IsBlue,
        durationSeconds: durationSeconds ?? this.durationSeconds,
        team1Stats: team1Stats ?? this.team1Stats,
        team2Stats: team2Stats ?? this.team2Stats,
        patchVersion: patchVersion ?? this.patchVersion,
        team1Bans: team1Bans,
        team2Bans: team2Bans,
        firstFrameTime: firstFrameTime,
        chapterStartUtc: chapterStartUtc,
        gameStartUtc: gameStartUtc ?? this.gameStartUtc,
      );

  GameDetail withBans({
    required List<String> team1Bans,
    required List<String> team2Bans,
  }) =>
      GameDetail(
        number: number,
        winnerCode: winnerCode,
        gameId: gameId,
        team1Side: team1Side,
        team1IsBlue: team1IsBlue,
        durationSeconds: durationSeconds,
        team1Stats: team1Stats,
        team2Stats: team2Stats,
        patchVersion: patchVersion,
        team1Bans: team1Bans,
        team2Bans: team2Bans,
        firstFrameTime: firstFrameTime,
        chapterStartUtc: chapterStartUtc,
        gameStartUtc: gameStartUtc,
      );
}

class MatchDetail {
  final List<GameDetail> games;
  final String team1Code; // getEventDetails match.teams[0]['code'] — may differ from LckMatch team ordering

  const MatchDetail({required this.games, this.team1Code = ''});

  static const empty = MatchDetail(games: []);

  factory MatchDetail.fromJson(Map<String, dynamic> json) {
    final match = json['match'] as Map<String, dynamic>? ?? {};

    final teamIdToCode = <String, String>{};
    final teams = match['teams'] as List? ?? [];
    for (final t in teams) {
      final id = t['id'] as String? ?? '';
      final code = t['code'] as String? ?? '';
      if (id.isNotEmpty && code.isNotEmpty) teamIdToCode[id] = code;
    }

    // team1 = first team in match.teams list
    final team1Id = teams.isNotEmpty ? teams[0]['id'] as String? ?? '' : '';

    final gamesRaw = match['games'] as List? ?? [];


    final games = gamesRaw
        .where((g) => g['state'] != 'unneeded')
        .map<GameDetail>((g) {
          String? winnerCode;

          // 1) winner 필드 직접 확인
          final winnerObj = g['winner'] as Map<String, dynamic>?;
          if (winnerObj != null) {
            final wId = winnerObj['id'] as String?;
            final wCode = winnerObj['code'] as String?;
            winnerCode = (wCode?.isNotEmpty == true)
                ? wCode
                : (wId != null ? teamIdToCode[wId] : null);
          }

          // 2) game teams result 확인
          if (winnerCode == null) {
            for (final gt in (g['teams'] as List? ?? [])) {
              final result = gt['result'] as Map<String, dynamic>?;
              final isWin = result?['outcome'] == 'win' ||
                  (result?['gameWins'] != null && result!['gameWins'] == 1);
              if (isWin) {
                final directCode = gt['code'] as String?;
                winnerCode = (directCode?.isNotEmpty == true)
                    ? directCode
                    : teamIdToCode[gt['id'] as String? ?? ''];
                break;
              }
            }
          }

          // game ID와 team1 사이드 파싱
          final gameId = g['id'] as String?;
          String? team1Side;
          List<String> team1Bans = [];
          List<String> team2Bans = [];

          for (final gt in (g['teams'] as List? ?? [])) {
            final gtId = gt['id'] as String? ?? '';
            final isTeam1 = gtId == team1Id;
            if (isTeam1) team1Side = gt['side'] as String?;

            // bans might be on the game-team object
            final bans = (gt['bans'] as List? ?? [])
                .map((b) => b['id']?.toString() ?? b['championId']?.toString() ?? b.toString())
                .where((s) => s.isNotEmpty)
                .toList();
            if (isTeam1) {
              team1Bans = bans;
            } else {
              team2Bans = bans;
            }
          }

          // Also check top-level game bans (some API versions put bans here)
          if (team1Bans.isEmpty && team2Bans.isEmpty) {
            for (final ban in (g['bans'] as List? ?? [])) {
              final teamId = ban['teamId'] as String? ?? '';
              final champ = ban['id']?.toString() ?? ban['championId']?.toString() ?? '';
              if (champ.isEmpty) continue;
              if (teamId == team1Id) team1Bans.add(champ);
              else team2Bans.add(champ);
            }
          }

          // VOD에서 firstFrameTime, chapterStartUtc, clip duration 파싱
          DateTime? firstFrameTime;
          DateTime? chapterStartUtc;
          int? vodDuration;
          for (final vod in (g['vods'] as List? ?? [])) {
            final fft = vod['firstFrameTime'] as String?;
            final startMs = vod['startMillis'] as int?;
            final endMs = vod['endMillis'] as int?;
            if (fft != null && firstFrameTime == null) {
              firstFrameTime = DateTime.tryParse(fft);
            }
            if (fft != null && startMs != null && endMs != null && endMs > startMs) {
              final broadcastStart = DateTime.tryParse(fft);
              if (broadcastStart != null && chapterStartUtc == null) {
                chapterStartUtc = broadcastStart.add(Duration(milliseconds: startMs));
                vodDuration ??= (endMs - startMs) ~/ 1000;
              }
            }
          }

          return GameDetail(
            number: g['number'] as int? ?? 0,
            winnerCode: winnerCode,
            gameId: gameId,
            team1Side: team1Side,
            team1Bans: team1Bans,
            team2Bans: team2Bans,
            durationSeconds: vodDuration,
            firstFrameTime: firstFrameTime,
            chapterStartUtc: chapterStartUtc,
          );
        })
        .toList()
      ..sort((a, b) => a.number.compareTo(b.number));

    final team1Code = teams.isNotEmpty ? (teams[0]['code'] as String? ?? '') : '';

    return MatchDetail(games: games, team1Code: team1Code);
  }
}
