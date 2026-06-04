import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/player_model.dart';
import 'auth_service.dart';

class DbService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

  Future<void> updatePlayerStats(int newScore, bool isWin) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final docRef = _db.collection('players').doc(user.uid);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);

      if (!snapshot.exists) {
        transaction.set(docRef, PlayerModel(
          uid: user.uid,
          displayName: user.displayName ?? 'Player',
          highScore: newScore,
          totalScore: newScore,
          wins: isWin ? 1 : 0,
          totalGames: 1,
          lastUpdated: DateTime.now(),
        ).toMap());
      } else {
        final data = PlayerModel.fromMap(snapshot.data()!);
        transaction.update(docRef, {
          'highScore': newScore > data.highScore ? newScore : data.highScore,
          'totalScore': data.totalScore + newScore,
          'wins': isWin ? data.wins + 1 : data.wins,
          'totalGames': data.totalGames + 1,
          'lastUpdated': DateTime.now(),
        });
      }
    });
  }

  Future<List<PlayerModel>> getLeaderboard({String orderBy = 'highScore'}) async {
    final querySnapshot = await _db.collection('players')
        .orderBy(orderBy, descending: true) // ממיין לפי הפרמטר שנעביר
        .limit(10)
        .get();

    return querySnapshot.docs.map((doc) => PlayerModel.fromMap(doc.data())).toList();
  }
}