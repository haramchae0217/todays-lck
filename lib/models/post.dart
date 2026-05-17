import 'package:cloud_firestore/cloud_firestore.dart';

class Post {
  final String id;
  final String title;
  final String content;
  final String authorId;
  final String authorName;
  final DateTime? createdAt;
  final int commentCount;
  final int likeCount;
  final List<String> likedBy; // 좋아요 누른 uid 목록

  const Post({
    required this.id,
    required this.title,
    required this.content,
    required this.authorId,
    required this.authorName,
    this.createdAt,
    required this.commentCount,
    this.likeCount = 0,
    this.likedBy = const [],
  });

  factory Post.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Post(
      id: doc.id,
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'] ?? '알 수 없음',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      commentCount: (data['commentCount'] ?? 0) as int,
      likeCount: (data['likeCount'] ?? 0) as int,
      likedBy: List<String>.from(data['likedBy'] ?? []),
    );
  }
}

class Comment {
  final String id;
  final String content;
  final String authorId;
  final String authorName;
  final DateTime? createdAt;

  const Comment({
    required this.id,
    required this.content,
    required this.authorId,
    required this.authorName,
    this.createdAt,
  });

  factory Comment.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Comment(
      id: doc.id,
      content: data['content'] ?? '',
      authorId: data['authorId'] ?? '',
      authorName: data['authorName'] ?? '알 수 없음',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
