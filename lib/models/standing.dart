class Standing {
  final int rank;
  final String teamName;
  final String teamCode;
  final String imageUrl;
  final int wins;
  final int losses;
  final int gameDiff;
  final int gameWins;
  final int gameLosses;

  const Standing({
    required this.rank,
    required this.teamName,
    required this.teamCode,
    required this.imageUrl,
    required this.wins,
    required this.losses,
    this.gameDiff = 0,
    this.gameWins = 0,
    this.gameLosses = 0,
  });

  int get totalGames => wins + losses;
  double get winRate => totalGames == 0 ? 0 : wins / totalGames;

  Standing copyWith({int? rank, int? gameDiff, int? gameWins, int? gameLosses}) {
    return Standing(
      rank: rank ?? this.rank,
      teamName: teamName,
      teamCode: teamCode,
      imageUrl: imageUrl,
      wins: wins,
      losses: losses,
      gameDiff: gameDiff ?? this.gameDiff,
      gameWins: gameWins ?? this.gameWins,
      gameLosses: gameLosses ?? this.gameLosses,
    );
  }
}
