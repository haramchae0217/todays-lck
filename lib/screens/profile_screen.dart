import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/team.dart';
import '../providers/auth_provider.dart';
import '../services/lck_api_service.dart';
import '../services/notification_service.dart';
import 'schedule_screen.dart' show scheduleProvider;

const _kAccent = Color(0xFF0891B2);
const _kTextHigh = Color(0xFF0F172A);
const _kTextMid = Color(0xFF64748B);
const _kTextLow = Color(0xFF94A3B8);
const _kBorder = Color(0xFFE2E8F0);

final _teamsForProfileProvider = FutureProvider<List<Team>>((ref) {
  return LckApiService.instance.getLckTeams();
});

final _lckLeagueImageProvider = FutureProvider<String?>((ref) {
  return LckApiService.instance.getLckLeagueImage();
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(appUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MY', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('로그아웃'),
                  content: const Text('로그아웃 하시겠어요?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('로그아웃',
                          style: TextStyle(color: Color(0xFFEF4444))),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(authServiceProvider).signOut();
              }
            },
          ),
        ],
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _kAccent)),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (user) {
          if (user == null) return const Center(child: Text('유저 정보 없음'));
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _ProfileHeader(
                user: user,
                onEdit: () => _showEditSheet(context, ref, user),
                onDelete: () => _confirmDelete(context, ref, user),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref, AppUser user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditProfileSheet(user: user, ref: ref),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, AppUser user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text('탈퇴하면 모든 데이터가 삭제되며\n복구할 수 없습니다. 탈퇴하시겠어요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('탈퇴',
                style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(authServiceProvider).deleteAccount(user.uid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('탈퇴 실패: $e')),
        );
      }
    }
  }
}

// ── 프로필 헤더 ──────────────────────────────────────────────────────────────
class _ProfileHeader extends ConsumerWidget {
  final AppUser user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ProfileHeader(
      {required this.user, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamsAsync = ref.watch(_teamsForProfileProvider);
    final teams = teamsAsync.valueOrNull ?? [];
    final favoriteTeam = teams.isEmpty
        ? null
        : teams.where((t) => t.code == user.favoriteTeamCode).firstOrNull;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _Avatar(user: user, favoriteTeam: favoriteTeam),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName.isNotEmpty ? user.displayName : '사용자',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _kTextHigh),
                ),
                const SizedBox(height: 4),
                Text(user.email,
                    style: const TextStyle(color: _kTextMid, fontSize: 13)),
              ],
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20, color: _kTextMid),
            tooltip: '프로필 편집',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.person_remove_outlined,
                size: 20, color: Color(0xFFEF4444)),
            tooltip: '회원 탈퇴',
          ),
        ],
      ),
    );
  }
}

class _Avatar extends ConsumerWidget {
  final AppUser user;
  final Team? favoriteTeam;
  const _Avatar({required this.user, this.favoriteTeam});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (favoriteTeam != null) {
      return _circle(
        child: Image.network(
          favoriteTeam!.imageUrl,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.shield, color: _kAccent),
        ),
        borderColor: _kAccent,
      );
    }
    if (user.photoUrl.isNotEmpty) {
      return CircleAvatar(
          radius: 32, backgroundImage: NetworkImage(user.photoUrl));
    }
    final lckImage = ref.watch(_lckLeagueImageProvider).valueOrNull;
    if (lckImage != null) {
      return _circle(
        child: Image.network(
          lckImage,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.sports_esports, color: _kTextMid),
        ),
        borderColor: _kBorder,
        bgOpacity: 0.5,
      );
    }
    return CircleAvatar(
      radius: 32,
      backgroundColor: _kAccent.withValues(alpha: 0.10),
      child: const Icon(Icons.sports_esports, size: 30, color: _kTextMid),
    );
  }

  Widget _circle(
      {required Widget child,
      required Color borderColor,
      double bgOpacity = 0.10}) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: borderColor.withValues(alpha: bgOpacity),
        border: Border.all(
            color: borderColor.withValues(alpha: 0.5), width: 1.5),
      ),
      padding: const EdgeInsets.all(10),
      child: child,
    );
  }
}

// ── 프로필 편집 바텀시트 ──────────────────────────────────────────────────────
class _EditProfileSheet extends ConsumerStatefulWidget {
  final AppUser user;
  final WidgetRef ref;
  const _EditProfileSheet({required this.user, required this.ref});

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  String? _selectedTeamCode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user.displayName);
    _selectedTeamCode = widget.user.favoriteTeamCode;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final nameChanged = name != widget.user.displayName;

    if (nameChanged) {
      if (name.isEmpty) {
        await _alert('닉네임을 입력해주세요.');
        return;
      }
      if (!widget.user.canChangeDisplayName) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('닉네임 변경'),
          content: const Text('닉네임은 한 번 변경하면\n30일간 다시 변경할 수 없습니다.\n계속하시겠어요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('변경',
                  style: TextStyle(color: _kAccent)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() => _saving = true);
    try {
      final clearTeam =
          _selectedTeamCode == null && widget.user.favoriteTeamCode != null;
      await widget.ref.read(authServiceProvider).updateProfile(
            widget.user.uid,
            displayName: nameChanged ? name : null,
            favoriteTeamCode: _selectedTeamCode,
            clearTeam: clearTeam,
          );

      final teamChanged = _selectedTeamCode != widget.user.favoriteTeamCode;
      if (teamChanged && _selectedTeamCode != null) {
        await NotificationService.instance.requestPermission();
        final matches =
            widget.ref.read(scheduleProvider).valueOrNull ?? [];
        await NotificationService.instance
            .scheduleTeamNotifications(matches, _selectedTeamCode);
      } else if (teamChanged && _selectedTeamCode == null) {
        await NotificationService.instance
            .scheduleTeamNotifications([], null);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      final msg =
          e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      if (mounted) {
        await _alert(msg);
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _alert(String message) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('확인', style: TextStyle(color: _kAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teamsAsync = ref.watch(_teamsForProfileProvider);
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final canChangeName = widget.user.canChangeDisplayName;
    final nextChangeDate = widget.user.nextDisplayNameChangeDate;

    return Padding(
      padding:
          EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _kBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('프로필 편집',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _kTextHigh)),
          const SizedBox(height: 20),

          // 닉네임
          Row(
            children: [
              const Text('닉네임',
                  style: TextStyle(color: _kTextMid, fontSize: 12)),
              if (!canChangeName && nextChangeDate != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${nextChangeDate.month}월 ${nextChangeDate.day}일부터 변경 가능',
                  style: const TextStyle(
                      color: Color(0xFFD97706), fontSize: 11),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nameCtrl,
            maxLength: 20,
            enabled: canChangeName,
            style: TextStyle(
              color: canChangeName ? _kTextHigh : _kTextLow,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              hintText: '닉네임 입력',
              hintStyle: const TextStyle(color: _kTextLow),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _kBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: _kAccent, width: 1.5),
              ),
              counterStyle:
                  const TextStyle(color: _kTextLow, fontSize: 11),
            ),
          ),
          const SizedBox(height: 16),

          // 응원팀
          const Text('응원팀',
              style: TextStyle(color: _kTextMid, fontSize: 12)),
          const SizedBox(height: 10),
          teamsAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: _kAccent)),
            error: (e, _) => Text('오류: $e'),
            data: (teams) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.85,
              ),
              itemCount: teams.length,
              itemBuilder: (_, i) {
                final team = teams[i];
                final isSelected = _selectedTeamCode == team.code;
                return GestureDetector(
                  onTap: () => setState(() =>
                      _selectedTeamCode =
                          isSelected ? null : team.code),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _kAccent.withValues(alpha: 0.10)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(10),
                          border: isSelected
                              ? Border.all(
                                  color: _kAccent, width: 1.5)
                              : Border.all(color: _kBorder),
                        ),
                        child: Image.network(
                          team.imageUrl,
                          width: 32,
                          height: 32,
                          fit: BoxFit.contain,
                          errorBuilder: (context, e, st) =>
                              const Icon(Icons.shield, size: 32),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        team.code,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color:
                              isSelected ? _kAccent : _kTextMid,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('저장',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
