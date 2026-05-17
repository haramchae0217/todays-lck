import 'package:cloud_firestore/cloud_firestore.dart';

class AppUser {
  final String uid;
  final String displayName;
  final String email;
  final String photoUrl;
  final String? favoriteTeamCode;
  final DateTime? createdAt;
  final DateTime? displayNameChangedAt;

  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.photoUrl,
    this.favoriteTeamCode,
    this.createdAt,
    this.displayNameChangedAt,
  });

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AppUser(
      uid: doc.id,
      displayName: data['displayName'] ?? '',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'] ?? '',
      favoriteTeamCode: data['favoriteTeamCode'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      displayNameChangedAt: (data['displayNameChangedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get canChangeDisplayName {
    if (displayNameChangedAt == null) return true;
    return DateTime.now().difference(displayNameChangedAt!).inDays >= 30;
  }

  DateTime? get nextDisplayNameChangeDate =>
      displayNameChangedAt?.add(const Duration(days: 30));
}
