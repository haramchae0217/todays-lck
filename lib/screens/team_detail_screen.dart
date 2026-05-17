import 'package:flutter/material.dart';
import '../models/team.dart';

const _positionOrder = ['top', 'jungle', 'mid', 'bottom', 'support'];
const _positionLabel = {
  'top': '탑',
  'jungle': '정글',
  'mid': '미드',
  'bottom': '원딜',
  'support': '서포터',
};

class TeamDetailScreen extends StatelessWidget {
  final Team team;
  const TeamDetailScreen({super.key, required this.team});

  Map<String, List<Player>> _groupByPosition() {
    final map = <String, List<Player>>{};
    for (final p in team.players) {
      final role = p.role.toLowerCase();
      map.putIfAbsent(role, () => []).add(p);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByPosition();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: CustomScrollView(
        slivers: [
          // ── 헤더 ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: const Color(0xFF0A0E1A),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // 배경 그라디언트
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF0BC4E3).withValues(alpha: 0.15),
                          const Color(0xFF0A0E1A),
                        ],
                      ),
                    ),
                  ),
                  // 팀 로고 + 이름
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Image.network(
                        team.imageUrl,
                        width: 80,
                        height: 80,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.shield, size: 80),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        team.code,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        team.name,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── 선수 포지션별 ──────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                ..._positionOrder.where((pos) => grouped.containsKey(pos)).map(
                  (pos) => _PositionSection(
                    label: _positionLabel[pos] ?? pos,
                    players: grouped[pos]!,
                  ),
                ),
                // 알려진 포지션 외의 선수 (있을 경우)
                ...grouped.entries
                    .where((e) => !_positionOrder.contains(e.key))
                    .map(
                      (e) => _PositionSection(
                        label: e.key,
                        players: e.value,
                      ),
                    ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _PositionSection extends StatelessWidget {
  final String label;
  final List<Player> players;
  const _PositionSection({required this.label, required this.players});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0BC4E3),
              letterSpacing: 1,
            ),
          ),
        ),
        ...players.map((p) => _PlayerRow(player: p)),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PlayerRow extends StatelessWidget {
  final Player player;
  const _PlayerRow({required this.player});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141928),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // 선수 사진
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              player.imageUrl ?? '',
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 52,
                height: 52,
                color: const Color(0xFF0BC4E3).withValues(alpha: 0.15),
                child: const Icon(Icons.person, color: Colors.white38),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // 이름 정보
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                player.summonerName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                player.fullName,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
