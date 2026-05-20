import 'package:cloud_firestore/cloud_firestore.dart';

class Prediction {
  final String id;
  final String userId;
  final String matchId;
  final String predictedTeamCode;
  final String team1Code;
  final String team2Code;
  final String team1Name;
  final String team2Name;
  final String leagueName;
  final DateTime matchTime;
  final bool? isCorrect;
  final String? actualWinnerCode;
  final DateTime? createdAt;

  const Prediction({
    required this.id,
    required this.userId,
    required this.matchId,
    required this.predictedTeamCode,
    required this.team1Code,
    required this.team2Code,
    required this.team1Name,
    required this.team2Name,
    required this.leagueName,
    required this.matchTime,
    this.isCorrect,
    this.actualWinnerCode,
    this.createdAt,
  });

  factory Prediction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Prediction(
      id: doc.id,
      userId: data['userId'] ?? '',
      matchId: data['matchId'] ?? '',
      predictedTeamCode: data['predictedTeamCode'] ?? '',
      team1Code: data['team1Code'] ?? '',
      team2Code: data['team2Code'] ?? '',
      team1Name: data['team1Name'] ?? '',
      team2Name: data['team2Name'] ?? '',
      leagueName: data['leagueName'] ?? '',
      matchTime: (data['matchTime'] as Timestamp).toDate(),
      isCorrect: data['isCorrect'] as bool?,
      actualWinnerCode: data['actualWinnerCode'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class LeaderboardEntry {
  final String uid;
  final String displayName;
  final String photoUrl;
  final int correctPredictions;
  final int totalPredictions;
  final int resolvedPredictions;

  double get accuracy {
    final denom = resolvedPredictions > 0 ? resolvedPredictions : totalPredictions;
    return denom > 0 ? correctPredictions / denom : 0;
  }

  const LeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.photoUrl,
    required this.correctPredictions,
    required this.totalPredictions,
    required this.resolvedPredictions,
  });

  factory LeaderboardEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return LeaderboardEntry(
      uid: doc.id,
      displayName: data['displayName'] ?? '알 수 없음',
      photoUrl: data['photoUrl'] ?? '',
      correctPredictions: (data['correctPredictions'] ?? 0) as int,
      totalPredictions: (data['totalPredictions'] ?? 0) as int,
      resolvedPredictions: (data['resolvedPredictions'] ?? 0) as int,
    );
  }
}
