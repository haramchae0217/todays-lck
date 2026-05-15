class Standing {
  final int rank;
  final String teamName;
  final String teamCode;
  final String imageUrl;
  final int wins;
  final int losses;

  const Standing({
    required this.rank,
    required this.teamName,
    required this.teamCode,
    required this.imageUrl,
    required this.wins,
    required this.losses,
  });

  int get totalGames => wins + losses;
  double get winRate => totalGames == 0 ? 0 : wins / totalGames;
}
