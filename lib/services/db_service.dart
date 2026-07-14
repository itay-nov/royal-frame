import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/player_model.dart';
import '../utils/app_feedback.dart';
import 'auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LEADERBOARD PAGE — cursor-based pagination result
// ─────────────────────────────────────────────────────────────────────────────
class LeaderboardPage {
  final List<PlayerModel> players;
  // Null means no more data is available.
  final QueryDocumentSnapshot<Map<String, dynamic>>? lastDocument;

  const LeaderboardPage({required this.players, this.lastDocument});
}

// ─────────────────────────────────────────────────────────────────────────────
// DB SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class DbService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _auth = AuthService();

  // ── Write helpers ──────────────────────────────────────────────────────────

  static const int _kMaxScore = 500000;

  Future<void> updatePlayerStats(int newScore, bool isWin) async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (newScore < 0 || newScore > _kMaxScore) return;

    final docRef = _db.collection('players').doc(user.uid);

    try {
      await _db.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);

        if (!snapshot.exists) {
          transaction.set(
            docRef,
            PlayerModel(
              uid: user.uid,
              displayName: user.displayName ?? 'Player',
              highScore: newScore,
              totalScore: newScore,
              wins: isWin ? 1 : 0,
              totalGames: 1,
              lastUpdated: DateTime.now(),
            ).toMap(),
          );
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
    } catch (error, stack) {
      logError('player.updateStats', error, stack);
    }
  }

  /// Updates only the displayName field on an existing player document.
  /// If the document does not exist yet (user has not played a game),
  /// the write is silently skipped — the name will be persisted by
  /// updatePlayerStats when they complete their first game.
  Future<void> updateDisplayName(String uid, String displayName) async {
    final sanitized = displayName.trim();
    if (sanitized.isEmpty || sanitized.length > 30) return;
    try {
      await _db.collection('players').doc(uid).update({
        'displayName': sanitized,
      });
    } catch (_) {
      // Document doesn't exist yet — no-op is intentional.
    }
  }

  /// Creates players/{uid} with default stats if it doesn't exist yet.
  /// Merge-safe: never overwrites an existing document's stats.
  Future<void> ensurePlayerDoc(String uid, String displayName) async {
    final doc = await _db.collection('players').doc(uid).get();
    if (doc.exists) return;
    await _db
        .collection('players')
        .doc(uid)
        .set(
          PlayerModel(
            uid: uid,
            displayName: displayName,
            lastUpdated: DateTime.now(),
          ).toMap(),
          SetOptions(merge: true),
        );
  }

  // ── Read helpers ───────────────────────────────────────────────────────────

  /// Server-driven existence check for players/{uid}.
  /// Intentionally does NOT catch errors — callers must distinguish
  /// "document is missing" from "network/permission failure".
  Future<bool> playerDocExists(String uid) async {
    final doc = await _db
        .collection('players')
        .doc(uid)
        .get(const GetOptions(source: Source.server));
    return doc.exists;
  }

  /// Returns the authenticated user's Firestore player document, or null.
  Future<PlayerModel?> getCurrentUserData() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final doc = await _db.collection('players').doc(user.uid).get();
    if (!doc.exists) return null;
    return PlayerModel.fromMap(doc.data()!);
  }

  // ── Paginated leaderboard ──────────────────────────────────────────────────

  /// Fetches the first [limit] players sorted by [orderBy] descending.
  Future<LeaderboardPage> getLeaderboardPage({
    String orderBy = 'highScore',
    int limit = 10,
  }) async {
    final snapshot = await _db
        .collection('players')
        .orderBy(orderBy, descending: true)
        .limit(limit)
        .get();

    final players = snapshot.docs
        .map((doc) => PlayerModel.fromMap(doc.data()))
        .toList();

    return LeaderboardPage(
      players: players,
      lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
    );
  }

  /// Fetches up to [limit] players starting after [lastDocument].
  Future<LeaderboardPage> getLeaderboardNextPage({
    required QueryDocumentSnapshot<Map<String, dynamic>> lastDocument,
    String orderBy = 'highScore',
    int limit = 50,
  }) async {
    final snapshot = await _db
        .collection('players')
        .orderBy(orderBy, descending: true)
        .startAfterDocument(lastDocument)
        .limit(limit)
        .get();

    final players = snapshot.docs
        .map((doc) => PlayerModel.fromMap(doc.data()))
        .toList();

    return LeaderboardPage(
      players: players,
      lastDocument: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
    );
  }

  /// Returns the user's rank (1-based) by counting players with a strictly
  /// higher score than them. Uses a server-side AggregateQuery — no full
  /// collection download needed.
  ///
  /// Returns 0 if the user has no Firestore document yet.
  Future<int> getUserRank({
    required String uid,
    required String orderBy,
  }) async {
    final userDoc = await _db.collection('players').doc(uid).get();
    if (!userDoc.exists) return 0;

    final userScore = (userDoc.data()![orderBy] as num?)?.toInt() ?? 0;

    final countResult = await _db
        .collection('players')
        .where(orderBy, isGreaterThan: userScore)
        .count()
        .get();

    return (countResult.count ?? 0) + 1;
  }

  // ── Streak sync ───────────────────────────────────────────────────────────

  Future<void> saveStreak(int streak, String lastDate) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _db.collection('players').doc(user.uid).set({
        'streak': streak,
        'streakLastDate': lastDate,
      }, SetOptions(merge: true));
    } catch (error, stack) {
      logError('streak.save', error, stack);
    }
  }

  Future<Map<String, dynamic>?> loadStreak() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final doc = await _db.collection('players').doc(user.uid).get();
      if (!doc.exists) return null;
      final data = doc.data()!;
      if (!data.containsKey('streak')) return null;
      return {
        'streak': data['streak'],
        'streakLastDate': data['streakLastDate'] ?? '',
      };
    } catch (e) {
      return null;
    }
  }

  // ── Legacy compat ──────────────────────────────────────────────────────────

  Future<List<PlayerModel>> getLeaderboard({
    String orderBy = 'highScore',
  }) async {
    final page = await getLeaderboardPage(orderBy: orderBy, limit: 10);
    return page.players;
  }
}
