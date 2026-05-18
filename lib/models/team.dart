class Team {
  final String id;
  final String slug;
  final String name;
  final String code;
  final String imageUrl;
  final List<Player> players;

  const Team({
    required this.id,
    required this.slug,
    required this.name,
    required this.code,
    required this.imageUrl,
    required this.players,
  });

  factory Team.fromJson(Map<String, dynamic> json) {
    return Team(
      id: json['id'] ?? '',
      slug: json['slug'] ?? '',
      name: json['name'],
      code: json['code'],
      imageUrl: (json['image'] as String? ?? '').replaceFirst('http://', 'https://'),
      players: (json['players'] as List? ?? [])
          .map((p) => Player.fromJson(p))
          .toList(),
    );
  }
}

class Player {
  final String summonerName;
  final String firstName;
  final String lastName;
  final String role;
  final String? imageUrl;

  const Player({
    required this.summonerName,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.imageUrl,
  });

  String get fullName => '$firstName $lastName'.trim();

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      summonerName: json['summonerName'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      role: json['role'] ?? '',
      imageUrl: json['image'],
    );
  }
}
