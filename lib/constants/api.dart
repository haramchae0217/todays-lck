class ApiConstants {
  static const String baseUrl = 'https://esports-api.lolesports.com/persisted/gw';
  static const String apiKey = '0TvQnueqKa5mxJntVWt0w4LpLfEkrV1Ta8rQBb9Z';
  static const String lckLeagueId = '98767991310872058';

  // 현재 시즌 토너먼트 ID (스플릿 변경 시 업데이트)
  static const String currentTournamentId = '115548128960088078'; // 2026 Split 2
  static const String nextTournamentId = '115548147890329817';    // 2026 Split 3

  static const Map<String, String> headers = {
    'x-api-key': apiKey,
  };
}
