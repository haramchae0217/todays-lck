import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  static const _testAccounts = [
    {'id': 'admin', 'email': 'admin@lckapp.dev', 'password': 'admin_lck_2024', 'displayName': 'Admin'},
    {'id': 'test2', 'email': 'test2@lckapp.dev', 'password': 'test2_lck_2024', 'displayName': 'Tester2'},
  ];

  Stream<User?> get authStateChanges => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithTestAccount(String id, String pw) async {
    final account = _testAccounts.where(
      (a) => a['id'] == id.trim() && pw.trim() == 'admin',
    ).firstOrNull;
    if (account == null) {
      throw Exception('아이디 또는 비밀번호가 올바르지 않습니다.');
    }
    final email = account['email']!;
    final password = account['password']!;
    final displayName = account['displayName']!;
    try {
      final result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _createUserIfNeeded(result.user!, displayName: displayName);
      return result;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        final result = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await _firestore.collection('users').doc(result.user!.uid).set({
          'uid': result.user!.uid,
          'displayName': displayName,
          'email': email,
          'photoUrl': '',
          'favoriteTeamCode': null,
          'totalPredictions': 0,
          'correctPredictions': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return result;
      }
      rethrow;
    }
  }

  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final result = await _auth.signInWithCredential(credential);
    await _createUserIfNeeded(result.user!);
    return result;
  }

  Future<UserCredential?> signInWithApple() async {
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );
    final result = await _auth.signInWithCredential(oauthCredential);
    await _createUserIfNeeded(result.user!);
    return result;
  }

  Future<void> _createUserIfNeeded(User user, {String? displayName}) async {
    final doc = _firestore.collection('users').doc(user.uid);
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      await doc.set({
        'uid': user.uid,
        'displayName': displayName ?? user.displayName ?? '',
        'email': user.email ?? '',
        'photoUrl': user.photoURL ?? '',
        'favoriteTeamCode': null,
        'totalPredictions': 0,
        'correctPredictions': 0,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> updateProfile(String uid, {String? displayName, String? favoriteTeamCode, bool clearTeam = false}) async {
    final data = <String, dynamic>{};

    if (displayName != null) {
      // 30일 쿨다운 체크
      final userSnap = await _firestore.collection('users').doc(uid).get();
      final changedAt = (userSnap.data()?['displayNameChangedAt'] as Timestamp?)?.toDate();
      if (changedAt != null && DateTime.now().difference(changedAt).inDays < 30) {
        final next = changedAt.add(const Duration(days: 30));
        throw Exception('닉네임은 ${next.month}월 ${next.day}일부터 변경할 수 있습니다.');
      }

      // 중복 체크
      final dup = await _firestore.collection('users')
          .where('displayName', isEqualTo: displayName)
          .limit(1)
          .get();
      if (dup.docs.isNotEmpty && dup.docs.first.id != uid) {
        throw Exception('이미 사용 중인 닉네임입니다.');
      }

      data['displayName'] = displayName;
      data['displayNameChangedAt'] = FieldValue.serverTimestamp();

      // 포스트·댓글 작성자명 일괄 업데이트
      await _updateAuthorName(uid, displayName);
    }

    if (clearTeam) {
      data['favoriteTeamCode'] = null;
    } else if (favoriteTeamCode != null) {
      data['favoriteTeamCode'] = favoriteTeamCode;
    }
    if (data.isNotEmpty) {
      await _firestore.collection('users').doc(uid).update(data);
    }
  }

  Future<void> _updateAuthorName(String uid, String newName) async {
    final posts = await _firestore.collection('posts')
        .where('authorId', isEqualTo: uid)
        .get();
    final comments = await _firestore.collectionGroup('comments')
        .where('authorId', isEqualTo: uid)
        .get();

    if (posts.docs.isEmpty && comments.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in posts.docs) {
      batch.update(doc.reference, {'authorName': newName});
    }
    for (final doc in comments.docs) {
      batch.update(doc.reference, {'authorName': newName});
    }
    await batch.commit();
  }

  Future<void> updateFavoriteTeam(String uid, String? teamCode) async {
    await _firestore.collection('users').doc(uid).update({
      'favoriteTeamCode': teamCode,
    });
  }

  Future<void> deleteAccount(String uid) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final predictions = await _firestore.collection('predictions')
        .where('userId', isEqualTo: uid).get();
    final posts = await _firestore.collection('posts')
        .where('authorId', isEqualTo: uid).get();
    final myComments = await _firestore.collectionGroup('comments')
        .where('authorId', isEqualTo: uid).get();

    final allRefs = <DocumentReference>[
      _firestore.collection('users').doc(uid),
      ...predictions.docs.map((d) => d.reference),
      ...myComments.docs.map((d) => d.reference),
    ];
    for (final post in posts.docs) {
      final postComments = await post.reference.collection('comments').get();
      for (final c in postComments.docs) {
        allRefs.add(c.reference);
      }
      allRefs.add(post.reference);
    }

    for (int i = 0; i < allRefs.length; i += 500) {
      final batch = _firestore.batch();
      final chunk = allRefs.sublist(i, (i + 500).clamp(0, allRefs.length));
      for (final ref in chunk) {
        batch.delete(ref);
      }
      await batch.commit();
    }

    await GoogleSignIn().signOut();
    await user.delete();
  }

  Future<void> signOut() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }
}
