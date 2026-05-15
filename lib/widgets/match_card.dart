import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../models/match.dart';

class MatchCard extends StatelessWidget {
  final LckMatch match;
  const MatchCard({super.key, required this.match});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141928),
        borderRadius: BorderRadius.circular(14),
        border: match.isLive
            ? Border.all(color: Colors.redAccent, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _statusChip(),
              const SizedBox(width: 8),
              Text(
                match.blockName,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const Spacer(),
              Text(
                DateFormat('M.d (E) HH:mm', 'ko').format(match.startTime),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _TeamSide(team: match.team1, isWinner: match.team1.outcome == 'win'),
              _ScoreCenter(match: match),
              _TeamSide(team: match.team2, isWinner: match.team2.outcome == 'win', isRight: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusChip() {
    if (match.isLive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }
    if (match.isCompleted) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text('종료', style: TextStyle(fontSize: 11, color: Colors.white54)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF0BC4E3).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text('예정', style: TextStyle(fontSize: 11, color: Color(0xFF0BC4E3))),
    );
  }
}

class _TeamSide extends StatelessWidget {
  final MatchTeam team;
  final bool isWinner;
  final bool isRight;

  const _TeamSide({required this.team, required this.isWinner, this.isRight = false});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          CachedNetworkImage(
            imageUrl: team.imageUrl,
            width: 48,
            height: 48,
            color: isWinner || team.outcome == null ? null : Colors.white24,
            colorBlendMode: BlendMode.modulate,
            errorWidget: (_, __, ___) => const Icon(Icons.shield, size: 48),
          ),
          const SizedBox(height: 6),
          Text(
            team.code,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: isWinner ? Colors.white : Colors.white60,
            ),
          ),
          Text(
            '${team.wins}W ${team.losses}L',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ScoreCenter extends StatelessWidget {
  final LckMatch match;
  const _ScoreCenter({required this.match});

  @override
  Widget build(BuildContext context) {
    if (match.isCompleted) {
      return Column(
        children: [
          Text(
            '${match.team1.gameWins} : ${match.team2.gameWins}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              letterSpacing: 2,
            ),
          ),
          Text(
            'BO${match.bestOf}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      );
    }
    return Column(
      children: [
        const Text('VS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white38)),
        Text('BO${match.bestOf}', style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }
}
