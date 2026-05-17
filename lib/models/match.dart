class LckMatch {
  final String id;
  final DateTime startTime;
  final String state; // 'unstarted', 'inProgress', 'completed'
  final String blockName;
  final MatchTeam team1;
  final MatchTeam team2;
  final int bestOf;
  final bool hasVod;
  final String leagueName;
  final String leagueSlug;

  const LckMatch({
    required this.id,
    required this.startTime,
    required this.state,
    required this.blockName,
    required this.team1,
    required this.team2,
    required this.bestOf,
    required this.hasVod,
    required this.leagueName,
    required this.leagueSlug,
  });

  bool get isCompleted => state == 'completed';
  bool get isLive => state == 'inProgress';
  bool get isUpcoming => state == 'unstarted';

  factory LckMatch.fromJson(Map<String, dynamic> json) {
    final match = json['match'] as Map<String, dynamic>;
    final teams = (match['teams'] as List?) ?? [];
    if (teams.length < 2) throw FormatException('팀 데이터 부족: ${match['id']}');
    final league = json['league'] as Map<String, dynamic>? ?? {};
    return LckMatch(
      id: match['id'] ?? '',
      startTime: DateTime.parse(json['startTime']).toLocal(),
      state: json['state'] ?? 'unstarted',
      blockName: json['blockName'] ?? '',
      team1: MatchTeam.fromJson(teams[0]),
      team2: MatchTeam.fromJson(teams[1]),
      bestOf: match['strategy']?['count'] ?? 3,
      hasVod: (match['flags'] as List?)?.contains('hasVod') ?? false,
      leagueName: league['name'] ?? '',
      leagueSlug: league['slug'] ?? '',
    );
  }
}

class MatchTeam {
  final String name;
  final String code;
  final String imageUrl;
  final String? outcome; // 'win', 'loss', null
  final int gameWins;
  final int wins;
  final int losses;

  const MatchTeam({
    required this.name,
    required this.code,
    required this.imageUrl,
    this.outcome,
    required this.gameWins,
    required this.wins,
    required this.losses,
  });

  factory MatchTeam.fromJson(Map<String, dynamic> json) {
    return MatchTeam(
      name: json['name'],
      code: json['code'],
      imageUrl: json['image'] ?? '',
      outcome: json['result']?['outcome'],
      gameWins: json['result']?['gameWins'] ?? 0,
      wins: json['record']?['wins'] ?? 0,
      losses: json['record']?['losses'] ?? 0,
    );
  }
}
