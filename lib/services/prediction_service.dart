import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/match.dart';
import '../models/prediction.dart';

class PredictionService {
  PredictionService._();
  static final instance = PredictionService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  Future<void> submitPrediction({
    required LckMatch match,
    required String predictedTeamCode,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('로그인이 필요합니다.');

    final existing = await _db
        .collection('predictions')
        .where('userId', isEqualTo: uid)
        .where('matchId', isEqualTo: match.id)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) throw Exception('이미 예측한 경기입니다.');

    final batch = _db.batch();
    final predRef = _db.collection('predictions').doc();
    batch.set(predRef, {
      'userId': uid,
      'matchId': match.id,
      'predictedTeamCode': predictedTeamCode,
      'team1Code': match.team1.code,
      'team2Code': match.team2.code,
      'team1Name': match.team1.name,
      'team2Name': match.team2.name,
      'leagueName': match.leagueName,
      'matchTime': Timestamp.fromDate(match.startTime),
      'isCorrect': null,
      'actualWinnerCode': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('users').doc(uid), {
      'totalPredictions': FieldValue.increment(1),
    });
    await batch.commit();
  }

  Future<void> updatePrediction({
    required String matchId,
    required String newTeamCode,
  }) async {
    final uid = _uid;
    if (uid == null) throw Exception('로그인이 필요합니다.');
    final snap = await _db
        .collection('predictions')
        .where('userId', isEqualTo: uid)
        .where('matchId', isEqualTo: matchId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) throw Exception('예측 내역이 없습니다.');
    await snap.docs.first.reference.update({'predictedTeamCode': newTeamCode});
  }

  Future<String?> getMyPrediction(String matchId) async {
    final uid = _uid;
    if (uid == null) return null;
    final snap = await _db
        .collection('predictions')
        .where('userId', isEqualTo: uid)
        .where('matchId', isEqualTo: matchId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.data()['predictedTeamCode'] as String?;
  }

  Stream<List<Prediction>> myPredictions() {
    final uid = _uid;
    if (uid == null) return Stream.value([]);
    return _db
        .collection('predictions')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .map((s) {
          final list = s.docs.map(Prediction.fromFirestore).toList();
          list.sort((a, b) => b.matchTime.compareTo(a.matchTime));
          return list;
        });
  }

  Future<void> resolveCompleted(List<LckMatch> completedMatches) async {
    final uid = _uid;
    if (uid == null || completedMatches.isEmpty) return;

    // 단일 필드 쿼리 후 Dart 필터 (복합 인덱스 불필요)
    final snap = await _db
        .collection('predictions')
        .where('userId', isEqualTo: uid)
        .get();
    final unresolved = snap.docs
        .where((d) => d.data()['isCorrect'] == null)
        .toList();
    if (unresolved.isEmpty) return;

    final resultMap = <String, String>{};
    for (final m in completedMatches) {
      final winner = m.team1.outcome == 'win'
          ? m.team1.code
          : m.team2.outcome == 'win'
              ? m.team2.code
              : null;
      if (winner != null) resultMap[m.id] = winner;
    }

    final batch = _db.batch();
    bool anyResolved = false;
    for (final doc in unresolved) {
      final matchId = doc.data()['matchId'] as String;
      final winner = resultMap[matchId];
      if (winner == null) continue;
      final predicted = doc.data()['predictedTeamCode'] as String;
      final correct = predicted == winner;
      batch.update(doc.reference, {'isCorrect': correct, 'actualWinnerCode': winner});
      anyResolved = true;
    }
    if (anyResolved) await batch.commit();
  }

  // 예측 컬렉션으로부터 users 문서의 적중 통계를 항상 동기화
  Future<void> syncUserStats() async {
    final uid = _uid;
    if (uid == null) return;

    final snap = await _db
        .collection('predictions')
        .where('userId', isEqualTo: uid)
        .get();

    final resolved = snap.docs.where((d) => d.data()['isCorrect'] != null).length;
    final correct = snap.docs.where((d) => d.data()['isCorrect'] == true).length;

    await _db.collection('users').doc(uid).update({
      'resolvedPredictions': resolved,
      'correctPredictions': correct,
    });
  }

  Future<({int team1Count, int team2Count})> getMatchStats({
    required String matchId,
    required String team1Code,
    required String team2Code,
  }) async {
    final snap = await _db
        .collection('predictions')
        .where('matchId', isEqualTo: matchId)
        .get();
    int t1 = 0, t2 = 0;
    for (final doc in snap.docs) {
      final code = doc.data()['predictedTeamCode'] as String?;
      if (code == team1Code) t1++;
      else if (code == team2Code) t2++;
    }
    return (team1Count: t1, team2Count: t2);
  }


  Future<List<LeaderboardEntry>> getLeaderboard() async {
    final snap = await _db
        .collection('users')
        .orderBy('correctPredictions', descending: true)
        .limit(100)
        .get();
    final entries = snap.docs
        .map(LeaderboardEntry.fromFirestore)
        .where((e) => e.totalPredictions > 0)
        .toList();
    // 동점 시 적중률 내림차순
    entries.sort((a, b) {
      final cmp = b.correctPredictions.compareTo(a.correctPredictions);
      if (cmp != 0) return cmp;
      return b.accuracy.compareTo(a.accuracy);
    });
    return entries;
  }

  Stream<List<LeaderboardEntry>> leaderboardStream() {
    return _db
        .collection('users')
        .orderBy('correctPredictions', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) {
          final entries = snap.docs
              .map(LeaderboardEntry.fromFirestore)
              .where((e) => e.totalPredictions > 0)
              .toList();
          entries.sort((a, b) {
            final cmp = b.correctPredictions.compareTo(a.correctPredictions);
            if (cmp != 0) return cmp;
            return b.accuracy.compareTo(a.accuracy);
          });
          return entries;
        });
  }
}
