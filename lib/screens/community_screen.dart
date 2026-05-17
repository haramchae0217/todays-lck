import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../services/community_service.dart';

const _kAccent = Color(0xFF0891B2);
const _kLike = Color(0xFFEF4444);
const _kTextHigh = Color(0xFF0F172A);
const _kTextMid = Color(0xFF64748B);
const _kTextLow = Color(0xFF94A3B8);
const _kBorder = Color(0xFFE2E8F0);

final _postsProvider = StreamProvider<List<Post>>((ref) {
  return CommunityService.instance.posts();
});

final _sortPopularProvider = StateProvider<bool>((ref) => false);

class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(_postsProvider);
    final isPopular = ref.watch(_sortPopularProvider);
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('커뮤니티', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (user != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WritePostScreen()),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── 정렬 탭 ──
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: _kBorder)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _SortTab(
                    label: '최신순',
                    selected: !isPopular,
                    onTap: () =>
                        ref.read(_sortPopularProvider.notifier).state = false),
                const SizedBox(width: 8),
                _SortTab(
                    label: '인기순',
                    selected: isPopular,
                    onTap: () =>
                        ref.read(_sortPopularProvider.notifier).state = true),
              ],
            ),
          ),
          // ── 게시글 목록 ──
          Expanded(
            child: postsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator(color: _kAccent)),
              error: (e, _) => Center(child: Text('오류: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(
                    child: Text('첫 번째 게시글을 작성해보세요!',
                        style: TextStyle(color: _kTextLow)),
                  );
                }
                final sorted = isPopular
                    ? ([...list]
                      ..sort((a, b) => b.likeCount.compareTo(a.likeCount)))
                    : list;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: sorted.length,
                  itemBuilder: (_, i) =>
                      _PostTile(post: sorted[i], myUid: user?.uid),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SortTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SortTab(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? _kAccent.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _kAccent : _kBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? _kAccent : _kTextMid,
          ),
        ),
      ),
    );
  }
}

class _PostTile extends StatelessWidget {
  final Post post;
  final String? myUid;
  const _PostTile({required this.post, this.myUid});

  @override
  Widget build(BuildContext context) {
    final isLiked = myUid != null && post.likedBy.contains(myUid);
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => PostDetailScreen(post: post, myUid: myUid)),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(post.title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _kTextHigh),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(post.authorName,
                    style: const TextStyle(color: _kTextMid, fontSize: 11)),
                const SizedBox(width: 6),
                if (post.createdAt != null)
                  Text(
                    DateFormat('M.d HH:mm').format(post.createdAt!),
                    style: const TextStyle(color: _kTextLow, fontSize: 10),
                  ),
                const Spacer(),
                GestureDetector(
                  onTap: myUid == null
                      ? null
                      : () async {
                          try {
                            await CommunityService.instance.toggleLike(post.id);
                          } catch (_) {}
                        },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          isLiked ? Icons.favorite : Icons.favorite_border,
                          size: 13,
                          color: isLiked ? _kLike : _kTextLow,
                        ),
                        const SizedBox(width: 3),
                        Text('${post.likeCount}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isLiked ? _kLike : _kTextLow,
                            )),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chat_bubble_outline,
                    size: 13, color: _kTextLow),
                const SizedBox(width: 3),
                Text('${post.commentCount}',
                    style: const TextStyle(color: _kTextLow, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── 글쓰기 ────────────────────────────────────────────────────────────────────
class WritePostScreen extends StatefulWidget {
  const WritePostScreen({super.key});

  @override
  State<WritePostScreen> createState() => _WritePostScreenState();
}

class _WritePostScreenState extends State<WritePostScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty || _content.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제목과 내용을 입력해주세요.')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await CommunityService.instance.createPost(_title.text, _content.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('오류: $e')));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('글쓰기', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _kAccent)),
            )
          else
            TextButton(
              onPressed: _submit,
              child: const Text('등록',
                  style: TextStyle(
                      color: _kAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _inputField(_title, '제목', maxLines: 1, maxLength: 50),
            const SizedBox(height: 12),
            Expanded(
              child: _inputField(_content, '내용을 자유롭게 작성해보세요.',
                  maxLines: null, expand: true, maxLength: 1000),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputField(TextEditingController ctrl, String hint,
      {int? maxLines, bool expand = false, int? maxLength}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      expands: expand,
      maxLength: maxLength,
      textAlignVertical: expand ? TextAlignVertical.top : null,
      style: const TextStyle(color: _kTextHigh, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _kTextLow),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kAccent, width: 1.5),
        ),
        counterStyle: const TextStyle(color: _kTextLow, fontSize: 11),
      ),
    );
  }
}

// ── 게시글 상세 ───────────────────────────────────────────────────────────────
class PostDetailScreen extends ConsumerStatefulWidget {
  final Post post;
  final String? myUid;
  const PostDetailScreen(
      {super.key, required this.post, this.myUid});

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentCtrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    if (_commentCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await CommunityService.instance
          .addComment(widget.post.id, _commentCtrl.text);
      _commentCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;

    return StreamBuilder<Post?>(
      stream: CommunityService.instance.postStream(widget.post.id),
      initialData: widget.post,
      builder: (context, postSnap) {
        final post = postSnap.data ?? widget.post;

        final commentsList = StreamBuilder<List<Comment>>(
          stream: CommunityService.instance.comments(widget.post.id),
          builder: (_, snap) {
            final list = snap.data ?? [];
            return SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _CommentTile(comment: list[i]),
                childCount: list.length,
              ),
            );
          },
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text('게시글'),
            actions: [
              if (post.authorId == widget.myUid)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Color(0xFFEF4444)),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('삭제'),
                        content: const Text('게시글을 삭제할까요?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('취소')),
                          TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('삭제',
                                  style:
                                      TextStyle(color: Color(0xFFEF4444)))),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await CommunityService.instance
                          .deletePost(widget.post.id);
                      if (mounted) Navigator.pop(context);
                    }
                  },
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(post.title,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: _kTextHigh)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(post.authorName,
                                    style: const TextStyle(
                                        color: _kTextMid, fontSize: 12)),
                                const Spacer(),
                                if (post.createdAt != null)
                                  Text(
                                    DateFormat('yyyy.M.d HH:mm')
                                        .format(post.createdAt!),
                                    style: const TextStyle(
                                        color: _kTextLow, fontSize: 12),
                                  ),
                              ],
                            ),
                            const Divider(color: _kBorder, height: 24),
                            Text(post.content,
                                style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.7,
                                    color: _kTextHigh)),
                            const SizedBox(height: 20),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: widget.myUid == null
                                      ? null
                                      : () async {
                                          try {
                                            await CommunityService.instance
                                                .toggleLike(post.id);
                                          } catch (_) {}
                                        },
                                  behavior: HitTestBehavior.opaque,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: (widget.myUid != null &&
                                              post.likedBy
                                                  .contains(widget.myUid))
                                          ? _kLike.withValues(alpha: 0.08)
                                          : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: (widget.myUid != null &&
                                                post.likedBy
                                                    .contains(widget.myUid))
                                            ? _kLike.withValues(alpha: 0.4)
                                            : _kBorder,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          (widget.myUid != null &&
                                                  post.likedBy
                                                      .contains(widget.myUid))
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          size: 14,
                                          color: (widget.myUid != null &&
                                                  post.likedBy
                                                      .contains(widget.myUid))
                                              ? _kLike
                                              : _kTextLow,
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          '${post.likeCount}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: (widget.myUid != null &&
                                                    post.likedBy.contains(
                                                        widget.myUid))
                                                ? _kLike
                                                : _kTextLow,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(Icons.chat_bubble_outline,
                                    size: 14, color: _kTextLow),
                                const SizedBox(width: 6),
                                Text('댓글 ${post.commentCount}',
                                    style: const TextStyle(
                                        color: _kTextMid, fontSize: 13)),
                              ],
                            ),
                            const Divider(color: _kBorder, height: 20),
                          ],
                        ),
                      ),
                    ),
                    commentsList,
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  ],
                ),
              ),
              if (user != null)
                _CommentInput(
                    ctrl: _commentCtrl,
                    sending: _sending,
                    onSend: _addComment),
            ],
          ),
        );
      },
    );
  }
}

class _CommentTile extends StatelessWidget {
  final Comment comment;
  const _CommentTile({required this.comment});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(comment.authorName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: _kTextHigh)),
              const Spacer(),
              if (comment.createdAt != null)
                Text(
                  DateFormat('M.d HH:mm').format(comment.createdAt!),
                  style: const TextStyle(color: _kTextLow, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(comment.content,
              style: const TextStyle(
                  color: _kTextMid, fontSize: 13, height: 1.4)),
          const Divider(color: _kBorder, height: 20),
        ],
      ),
    );
  }
}

class _CommentInput extends StatelessWidget {
  final TextEditingController ctrl;
  final bool sending;
  final VoidCallback onSend;
  const _CommentInput(
      {required this.ctrl, required this.sending, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _kBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLength: 300,
              style: const TextStyle(color: _kTextHigh, fontSize: 14),
              decoration: InputDecoration(
                hintText: '댓글을 입력하세요',
                hintStyle: const TextStyle(color: _kTextLow),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: 8),
          sending
              ? const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _kAccent))
              : IconButton(
                  onPressed: onSend,
                  icon: const Icon(Icons.send, color: _kAccent),
                ),
        ],
      ),
    );
  }
}
