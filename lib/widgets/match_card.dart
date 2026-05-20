import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../constants/colors.dart';
import '../models/match.dart';
import '../services/notification_service.dart';
import '../utils/team_utils.dart';

String _formatBlockName(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('grand final')) return '결승전';
  if (lower.contains('upper bracket')) {
    if (lower.contains('final')) return '승자조 결승';
    final m = RegExp(r'round\s*(\d+)', caseSensitive: false).firstMatch(raw);
    return m != null ? '승자조 ${m.group(1)}R' : '승자조';
  }
  if (lower.contains('lower bracket')) {
    if (lower.contains('final')) return '패자조 결승';
    final m = RegExp(r'round\s*(\d+)', caseSensitive: false).firstMatch(raw);
    return m != null ? '패자조 ${m.group(1)}R' : '패자조';
  }
  if (lower.contains('playoff') || lower.contains('플레이오프')) return '플레이오프';
  if (lower.contains('semifinal') || lower.contains('준결승')) return '준결승';
  if (lower.contains('quarterfinal') || lower.contains('8강')) return '8강';
  if (lower.contains('final') || lower.contains('결승')) return '결승';
  if (lower.contains('play-in') || lower.contains('플레이인')) return '플레이인';
  if (lower.contains('group a') || lower.contains('그룹 a')) return '그룹 A';
  if (lower.contains('group b') || lower.contains('그룹 b')) return '그룹 B';
  if (lower.contains('group c') || lower.contains('그룹 c')) return '그룹 C';
  if (lower.contains('group d') || lower.contains('그룹 d')) return '그룹 D';
  if (lower.contains('group') || lower.contains('그룹')) return '그룹';
  if (lower.contains('regular') || lower.contains('정규')) return '정규';
  // OverviewPage 전체 경로 (예: LCK/2025 Season/Split 2/Playoffs) → 마지막 세그먼트 재귀 처리
  if (raw.contains('/')) {
    final lastSeg = raw.split('/').last.trim();
    if (lastSeg.isNotEmpty && lastSeg != raw) return _formatBlockName(lastSeg);
  }
  return raw;
}


class MatchCard extends StatelessWidget {
  final LckMatch match;
  final VoidCallback? onTap;
  const MatchCard({super.key, required this.match, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _CardBody(match: match),
    );
  }
}

class _CardBody extends StatelessWidget {
  final LckMatch match;
  const _CardBody({required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF111528),
        borderRadius: BorderRadius.circular(12),
        border: match.isLive
            ? Border.all(color: AppColors.live, width: 1.5)
            : Border.all(color: AppColors.border, width: 1),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                _statusChip(),
                const SizedBox(width: 6),
                Text(
                  DateFormat('HH:mm').format(match.startTime),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMid,
                  ),
                ),
                const SizedBox(width: 6),
                if (match.leagueSlug != 'lck') ...[
                  _leagueChip(),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  flex: 2,
                  child: Text(
                    _formatBlockName(match.blockName),
                    style: const TextStyle(color: AppColors.textLow, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: _CompactMatchRow(match: match),
                ),
                if (match.isUpcoming)
                  _SmallBellButton(match: match),
              ],
            ),
          ),
          if (match.isLive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.live, AppColors.live.withValues(alpha: 0.3), Colors.transparent],
                    stops: const [0.0, 0.6, 1.0],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _leagueChip() {
    final color = _leagueColor();
    final label = switch (match.leagueSlug) {
      'first_stand' => 'FS',
      'lck_cup'     => 'CUP',
      'msi'         => 'MSI',
      'worlds'      => 'Worlds',
      _             => match.leagueName,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Color _leagueColor() {
    switch (match.leagueSlug) {
      case 'msi': return const Color(0xFFD97706);
      case 'worlds': return const Color(0xFFEA580C);
      case 'first_stand': return const Color(0xFF7C3AED);
      case 'lck_cup': return const Color(0xFF059669);
      default: return AppColors.accent;
    }
  }

  Widget _statusChip() {
    if (match.isLive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.live,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('LIVE',
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
      );
    }
    if (match.isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('종료', style: TextStyle(fontSize: 9, color: AppColors.textLow)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('예정',
          style: TextStyle(fontSize: 9, color: AppColors.accent, fontWeight: FontWeight.w600)),
    );
  }
}

class _CompactMatchRow extends StatelessWidget {
  final LckMatch match;
  const _CompactMatchRow({required this.match});

  @override
  Widget build(BuildContext context) {
    final t1Win = match.team1.outcome == 'win';
    final t2Win = match.team2.outcome == 'win';

    return Row(
      children: [
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                match.team1.code,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: match.isCompleted
                      ? (t1Win ? AppColors.textHigh : AppColors.textLow)
                      : AppColors.textHigh,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(width: 5),
              _teamLogo(match.team1.imageUrl, match.team1.code, dimmed: match.isCompleted && !t1Win),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: match.isCompleted
              ? Text(
                  '${match.team1.gameWins}:${match.team2.gameWins}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textHigh,
                    letterSpacing: 1,
                  ),
                )
              : Text(
                  'vs',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: match.isLive ? AppColors.live : AppColors.textLow,
                  ),
                ),
        ),
        Expanded(
          child: Row(
            children: [
              _teamLogo(match.team2.imageUrl, match.team2.code, dimmed: match.isCompleted && !t2Win),
              const SizedBox(width: 5),
              Text(
                match.team2.code,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: match.isCompleted
                      ? (t2Win ? AppColors.textHigh : AppColors.textLow)
                      : AppColors.textHigh,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _teamLogo(String url, String code, {bool dimmed = false}) {
    return Opacity(
      opacity: dimmed ? 0.35 : 1.0,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: teamLogoBgColor(code),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(2),
        child: Image.network(
          url,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.shield, size: 18, color: AppColors.textLow),
        ),
      ),
    );
  }
}

class _SmallBellButton extends StatefulWidget {
  final LckMatch match;
  const _SmallBellButton({required this.match});

  @override
  State<_SmallBellButton> createState() => _SmallBellButtonState();
}

class _SmallBellButtonState extends State<_SmallBellButton> {
  bool? _subscribed;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.isSubscribed(widget.match.id).then((v) {
      if (mounted) setState(() => _subscribed = v);
    });
  }

  Future<void> _toggle() async {
    final granted = await NotificationService.instance.requestPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알림 권한이 필요합니다. 설정에서 허용해주세요.')),
        );
      }
      return;
    }
    final newState = await NotificationService.instance.toggleMatchNotification(widget.match);
    if (mounted) {
      setState(() => _subscribed = newState);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newState ? '경기 10분 전 알림이 설정됐습니다.' : '알림이 해제됐습니다.'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_subscribed == null) return const SizedBox(width: 24);
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Icon(
          _subscribed! ? Icons.notifications_active : Icons.notifications_none_outlined,
          size: 16,
          color: _subscribed! ? AppColors.accent : AppColors.textLow,
        ),
      ),
    );
  }
}
