import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';

class CommunityService {
  CommunityService._();
  static final instance = CommunityService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Stream<List<Post>> posts() {
    return _db
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map(Post.fromFirestore).toList());
  }

  Stream<Post?> postStream(String postId) {
    return _db
        .collection('posts')
        .doc(postId)
        .snapshots()
        .map((s) => s.exists ? Post.fromFirestore(s) : null);
  }

  Stream<List<Comment>> comments(String postId) {
    return _db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs.map(Comment.fromFirestore).toList());
  }

  Future<String> _displayName() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다.');
    final doc = await _db.collection('users').doc(user.uid).get();
    return (doc.data()?['displayName'] as String?)?.isNotEmpty == true
        ? doc.data()!['displayName'] as String
        : user.email?.split('@').first ?? '익명';
  }

  Future<void> createPost(String title, String content) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다.');
    final name = await _displayName();
    await _db.collection('posts').add({
      'title': title.trim(),
      'content': content.trim(),
      'authorId': user.uid,
      'authorName': name,
      'commentCount': 0,
      'likeCount': 0,
      'likedBy': [],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // 좋아요 토글 — 원자적으로 처리
  Future<bool> toggleLike(String postId) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다.');
    final uid = user.uid;
    final ref = _db.collection('posts').doc(postId);

    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final liked = List<String>.from(snap.data()?['likedBy'] ?? []);
      final isLiked = liked.contains(uid);
      if (isLiked) {
        liked.remove(uid);
        tx.update(ref, {
          'likedBy': liked,
          'likeCount': FieldValue.increment(-1),
        });
        return false;
      } else {
        liked.add(uid);
        tx.update(ref, {
          'likedBy': liked,
          'likeCount': FieldValue.increment(1),
        });
        return true;
      }
    });
  }

  Future<void> addComment(String postId, String content) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('로그인이 필요합니다.');
    final name = await _displayName();
    final batch = _db.batch();
    final commentRef =
        _db.collection('posts').doc(postId).collection('comments').doc();
    batch.set(commentRef, {
      'content': content.trim(),
      'authorId': user.uid,
      'authorName': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('posts').doc(postId), {
      'commentCount': FieldValue.increment(1),
    });
    await batch.commit();
  }

  Future<void> deletePost(String postId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final postRef = _db.collection('posts').doc(postId);
    final doc = await postRef.get();
    if (doc.data()?['authorId'] != uid) throw Exception('삭제 권한이 없습니다.');

    final comments = await postRef.collection('comments').get();
    final batch = _db.batch();
    for (final c in comments.docs) {
      batch.delete(c.reference);
    }
    batch.delete(postRef);
    await batch.commit();
  }

  Future<void> reportPost(String postId, String reason) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('로그인이 필요합니다.');

    final existing = await _db
        .collection('reports')
        .where('postId', isEqualTo: postId)
        .where('reporterId', isEqualTo: uid)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) throw Exception('이미 신고한 게시글입니다.');

    await _db.collection('reports').add({
      'postId': postId,
      'reporterId': uid,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
