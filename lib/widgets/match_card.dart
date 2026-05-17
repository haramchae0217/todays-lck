import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/match.dart';
import '../services/notification_service.dart';
import '../utils/team_utils.dart';

String _formatBlockName(String raw) {
  final lower = raw.toLowerCase();
  if (lower.contains('playoff') || lower.contains('플레이오프')) return '플레이오프';
  if (lower.contains('semifinal') || lower.contains('준결승')) return '준결승';
  if (lower.contains('quarterfinal') || lower.contains('8강')) return '8강';
  if (lower.contains('final') || lower.contains('결승')) return '결승';
  if (lower.contains('play-in') || lower.contains('플레이인')) return '플레이인';
  return raw;
}

const _kAccent = Color(0xFF0891B2);
const _kLive = Color(0xFFEF4444);
const _kTextHigh = Color(0xFF0F172A);
const _kTextMid = Color(0xFF64748B);
const _kTextLow = Color(0xFF94A3B8);
const _kBorder = Color(0xFFE2E8F0);

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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: match.isLive
            ? Border.all(color: _kLive, width: 1.5)
            : Border.all(color: _kBorder, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (match.isLive)
            Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kLive, _kLive.withValues(alpha: 0.3), Colors.transparent],
                  stops: const [0.0, 0.6, 1.0],
                ),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
            ),
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
                    color: _kTextMid,
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
                    style: const TextStyle(color: _kTextLow, fontSize: 10),
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
        ],
      ),
    );
  }

  Widget _leagueChip() {
    final color = _leagueColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.40), width: 0.8),
      ),
      child: Text(
        match.leagueName,
        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Color _leagueColor() {
    switch (match.leagueSlug) {
      case 'msi': return const Color(0xFFD97706);
      case 'worlds': return const Color(0xFFEA580C);
      case 'first_stand': return const Color(0xFF7C3AED);
      default: return _kAccent;
    }
  }

  Widget _statusChip() {
    if (match.isLive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _kLive,
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
        child: const Text('종료', style: TextStyle(fontSize: 9, color: _kTextLow)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _kAccent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('예정',
          style: TextStyle(fontSize: 9, color: _kAccent, fontWeight: FontWeight.w600)),
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
                      ? (t1Win ? _kTextHigh : _kTextLow)
                      : _kTextHigh,
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
                    color: _kTextHigh,
                    letterSpacing: 1,
                  ),
                )
              : Text(
                  'vs',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: match.isLive ? _kLive : _kTextLow,
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
                      ? (t2Win ? _kTextHigh : _kTextLow)
                      : _kTextHigh,
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
              const Icon(Icons.shield, size: 18, color: _kTextLow),
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
          color: _subscribed! ? _kAccent : _kTextLow,
        ),
      ),
    );
  }
}
