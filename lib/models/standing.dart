class Standing {
  final int rank;
  final String teamName;
  final String teamCode;
  final String imageUrl;
  final int wins;
  final int losses;
  final int gameDiff;

  const Standing({
    required this.rank,
    required this.teamName,
    required this.teamCode,
    required this.imageUrl,
    required this.wins,
    required this.losses,
    this.gameDiff = 0,
  });

  int get totalGames => wins + losses;
  double get winRate => totalGames == 0 ? 0 : wins / totalGames;

  Standing copyWith({int? rank, int? gameDiff}) {
    return Standing(
      rank: rank ?? this.rank,
      teamName: teamName,
      teamCode: teamCode,
      imageUrl: imageUrl,
      wins: wins,
      losses: losses,
      gameDiff: gameDiff ?? this.gameDiff,
    );
  }
}
