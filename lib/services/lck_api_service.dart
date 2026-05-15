import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api.dart';
import '../models/match.dart';
import '../models/standing.dart';
import '../models/team.dart';

class LckApiService {
  static final LckApiService instance = LckApiService._();
  LckApiService._();

  Future<T> _get<T>(String endpoint, T Function(Map<String, dynamic>) parser) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/$endpoint');
    final res = await http.get(uri, headers: ApiConstants.headers);
    if (res.statusCode != 200) throw Exception('API 오류: ${res.statusCode}');
    return parser(jsonDecode(res.body)['data']);
  }

  Future<List<LckMatch>> getSchedule({String? pageToken}) async {
    final tokenParam = pageToken != null ? '&pageToken=$pageToken' : '';
    return _get(
      'getSchedule?hl=ko-KR&leagueId=${ApiConstants.lckLeagueId}$tokenParam',
      (data) {
        final events = data['schedule']['events'] as List;
        return events
            .where((e) => e['type'] == 'match')
            .map((e) => LckMatch.fromJson(e))
            .toList();
      },
    );
  }

  Future<List<Standing>> getStandings({String? tournamentId}) async {
    final id = tournamentId ?? ApiConstants.currentTournamentId;
    return _get(
      'getStandings?hl=ko-KR&tournamentId=$id',
      (data) {
        final stages = data['standings'][0]['stages'] as List;
        final regularStage = stages.firstWhere(
          (s) => s['slug'] == 'regular_season' || s['type'] == 'regular',
          orElse: () => stages[0],
        );
        final rankings = regularStage['sections'][0]['rankings'] as List;
        final List<Standing> standings = [];
        for (final ranking in rankings) {
          for (final team in ranking['teams']) {
            standings.add(Standing(
              rank: ranking['ordinal'],
              teamName: team['name'],
              teamCode: team['code'],
              imageUrl: team['image'] ?? '',
              wins: team['record']['wins'],
              losses: team['record']['losses'],
            ));
          }
        }
        return standings;
      },
    );
  }

  Future<List<Team>> getLckTeams() async {
    return _get(
      'getTeams?hl=ko-KR',
      (data) {
        final teams = data['teams'] as List;
        return teams
            .where((t) => t['homeLeague']?['name'] == 'LCK')
            .map((t) => Team.fromJson(t))
            .where((t) => t.players.isNotEmpty)
            .toList();
      },
    );
  }

  Future<Team> getTeamDetail(String slug) async {
    return _get(
      'getTeams?hl=ko-KR&id=$slug',
      (data) => Team.fromJson((data['teams'] as List)[0]),
    );
  }

  Future<List<LckMatch>> getLiveMatches() async {
    return _get(
      'getLive?hl=ko-KR',
      (data) {
        final events = data['schedule']['events'] as List;
        return events
            .where((e) => e['type'] == 'match')
            .map((e) => LckMatch.fromJson(e))
            .toList();
      },
    );
  }
}
