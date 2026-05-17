import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import '../models/match.dart';

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  static const _subscribedKey = 'notif_subscribed_match_ids';
  static const _teamMatchIdsKey = 'notif_team_match_ids';
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(const InitializationSettings(iOS: iosSettings));
    _initialized = true;
  }

  // 알림 권한 요청 (최초 1회 시스템 다이얼로그)
  Future<bool> requestPermission() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final granted = await ios?.requestPermissions(
      alert: true,
      badge: false,
      sound: true,
    );
    return granted ?? false;
  }

  // ── 개별 경기 구독 ────────────────────────────────────────────────────────────
  Future<Set<String>> _loadSubscribed() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_subscribedKey) ?? []).toSet();
  }

  Future<void> _saveSubscribed(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_subscribedKey, ids.toList());
  }

  Future<bool> isSubscribed(String matchId) async {
    return (await _loadSubscribed()).contains(matchId);
  }

  // 종 버튼 토글 → true 반환 시 구독됨
  Future<bool> toggleMatchNotification(LckMatch match) async {
    final ids = await _loadSubscribed();
    if (ids.contains(match.id)) {
      ids.remove(match.id);
      await _cancel(match.id);
      await _saveSubscribed(ids);
      return false;
    } else {
      await _schedule(match, isTeam: false);
      ids.add(match.id);
      await _saveSubscribed(ids);
      return true;
    }
  }

  // ── 응원팀 경기 자동 알림 ─────────────────────────────────────────────────────
  Future<void> scheduleTeamNotifications(
      List<LckMatch> matches, String? teamCode) async {
    final prefs = await SharedPreferences.getInstance();

    // 기존 팀 알림 취소
    final oldIds = prefs.getStringList(_teamMatchIdsKey) ?? [];
    for (final id in oldIds) {
      await _cancel('team_$id');
    }
    await prefs.remove(_teamMatchIdsKey);

    if (teamCode == null) return;

    final upcoming = matches.where((m) =>
        !m.isCompleted &&
        !m.isLive &&
        (m.team1.code == teamCode || m.team2.code == teamCode) &&
        m.startTime.isAfter(DateTime.now())).toList();

    final scheduledIds = <String>[];
    for (final match in upcoming) {
      await _schedule(match, isTeam: true);
      scheduledIds.add(match.id);
    }
    await prefs.setStringList(_teamMatchIdsKey, scheduledIds);
  }

  // ── 내부 헬퍼 ────────────────────────────────────────────────────────────────
  Future<void> _schedule(LckMatch match, {required bool isTeam}) async {
    final notifTime = match.startTime.subtract(const Duration(minutes: 10));
    if (!notifTime.isAfter(DateTime.now())) return;

    final id = isTeam
        ? 'team_${match.id}'.hashCode.abs()
        : match.id.hashCode.abs();

    final tzTime = tz.TZDateTime.from(notifTime, tz.local);
    const details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: false,
      ),
    );

    await _plugin.zonedSchedule(
      id,
      '⚔️ 경기 시작 10분 전',
      '${match.team1.code} vs ${match.team2.code} — 지금 확인하세요!',
      tzTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: match.id,
    );
  }

  Future<void> _cancel(String key) async {
    await _plugin.cancel(key.hashCode.abs());
  }
}
