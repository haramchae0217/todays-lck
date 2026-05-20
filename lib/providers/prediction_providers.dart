import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/prediction.dart';
import 'auth_provider.dart';
import '../services/prediction_service.dart';

final myPredictionsProvider = StreamProvider<List<Prediction>>((ref) {
  ref.watch(authStateProvider);
  return PredictionService.instance.myPredictions();
});

final leaderboardProvider = StreamProvider<List<LeaderboardEntry>>((ref) {
  ref.watch(authStateProvider);
  return PredictionService.instance.leaderboardStream();
});
