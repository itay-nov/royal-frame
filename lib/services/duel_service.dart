import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DUEL SERVICE — Firestore-backed code-based matchmaking for 1v1 duels
// ─────────────────────────────────────────────────────────────────────────────

enum DuelStatus { waiting, active, finished }

class DuelSession {
  final String duelId;
  final String code;
  final String hostUid;
  final String? guestUid;
  final String hostName;
  final String? guestName;
  final int hostScore;
  final int guestScore;
  final DuelStatus status;
  final String? winnerId;
  final DateTime createdAt;
  final int seed;

  const DuelSession({
    required this.duelId,
    required this.code,
    required this.hostUid,
    this.guestUid,
    required this.hostName,
    this.guestName,
    required this.hostScore,
    required this.guestScore,
    required this.status,
    this.winnerId,
    required this.createdAt,
    required this.seed,
  });

  factory DuelSession.fromMap(String id, Map<String, dynamic> data) {
    DuelStatus parseStatus(String? s) {
      return switch (s) {
        'active'   => DuelStatus.active,
        'finished' => DuelStatus.finished,
        _          => DuelStatus.waiting,
      };
    }

    return DuelSession(
      duelId: id,
      code: (data['code'] as String?) ?? '',
      hostUid: (data['hostUid'] as String?) ?? '',
      guestUid: data['guestUid'] as String?,
      hostName: (data['hostName'] as String?) ?? 'Host',
      guestName: data['guestName'] as String?,
      hostScore: (data['hostScore'] as num?)?.toInt() ?? 0,
      guestScore: (data['guestScore'] as num?)?.toInt() ?? 0,
      status: parseStatus(data['status'] as String?),
      winnerId: data['winnerId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      seed: (data['seed'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'code': code,
        'hostUid': hostUid,
        'guestUid': guestUid,
        'hostName': hostName,
        'guestName': guestName,
        'hostScore': hostScore,
        'guestScore': guestScore,
        'status': status.name,
        'winnerId': winnerId,
        'createdAt': Timestamp.fromDate(createdAt),
        'seed': seed,
      };

  bool get isFinished => status == DuelStatus.finished;
  bool get isActive   => status == DuelStatus.active;
  bool get isWaiting  => status == DuelStatus.waiting;
}

class DuelService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static CollectionReference<Map<String, dynamic>> get _duels =>
      _db.collection('duels');

  // ── Code generation ────────────────────────────────────────────────────────

  static String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Host: create duel ──────────────────────────────────────────────────────

  /// Creates a new duel session and returns it. The host waits for a guest.
  static Future<DuelSession> createDuel() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final code = _generateCode();
    final seed = Random().nextInt(0x7FFFFFFF);

    final data = DuelSession(
      duelId: '',
      code: code,
      hostUid: user.uid,
      hostName: user.displayName ?? 'Host',
      hostScore: 0,
      guestScore: 0,
      status: DuelStatus.waiting,
      createdAt: DateTime.now(),
      seed: seed,
    ).toMap();

    final ref = await _duels.add(data);
    return DuelSession.fromMap(ref.id, data);
  }

  // ── Guest: join duel ───────────────────────────────────────────────────────

  /// Finds a waiting duel by 6-char code and joins it as guest.
  /// Throws if code is invalid or duel is already active/finished.
  static Future<DuelSession> joinDuel(String code) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final trimmed = code.trim().toUpperCase();

    final snap = await _duels
        .where('code', isEqualTo: trimmed)
        .where('status', isEqualTo: 'waiting')
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      throw Exception('No active duel found for code "$trimmed"');
    }

    final doc = snap.docs.first;
    if (doc.data()['hostUid'] == user.uid) {
      throw Exception('You cannot join your own duel');
    }

    await doc.reference.update({
      'guestUid':   user.uid,
      'guestName':  user.displayName ?? 'Guest',
      'status':     DuelStatus.active.name,
    });

    final updated = await doc.reference.get();
    return DuelSession.fromMap(doc.id, updated.data()!);
  }

  // ── Score sync ─────────────────────────────────────────────────────────────

  /// Writes the calling player's current score to Firestore.
  static Future<void> syncScore(String duelId, int score) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final doc = await _duels.doc(duelId).get();
    if (!doc.exists) return;

    final isHost = doc.data()!['hostUid'] == uid;
    await _duels.doc(duelId).update(
      isHost ? {'hostScore': score} : {'guestScore': score},
    );
  }

  // ── Mark finished ──────────────────────────────────────────────────────────

  /// Marks this player's game as finished. Once both players have finished,
  /// the higher-score player is recorded as winner.
  static Future<void> markFinished(String duelId, int finalScore) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _db.runTransaction((tx) async {
      final ref = _duels.doc(duelId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data()!;
      final isHost = data['hostUid'] == uid;

      final updates = <String, dynamic>{
        isHost ? 'hostScore' : 'guestScore': finalScore,
        isHost ? 'hostFinished' : 'guestFinished': true,
      };

      final hostFinished  = (data['hostFinished']  as bool?) ?? false;
      final guestFinished = (data['guestFinished'] as bool?) ?? false;

      final otherFinished = isHost ? guestFinished : hostFinished;

      if (otherFinished) {
        // Both done — determine winner
        final hostScore  = isHost ? finalScore : (data['hostScore']  as num?)?.toInt() ?? 0;
        final guestScore = isHost ? (data['guestScore'] as num?)?.toInt() ?? 0 : finalScore;
        final winnerId = hostScore >= guestScore
            ? data['hostUid'] as String
            : data['guestUid'] as String;
        updates['status']   = DuelStatus.finished.name;
        updates['winnerId'] = winnerId;
      }

      tx.update(ref, updates);
    });
  }

  // ── Stream helpers ─────────────────────────────────────────────────────────

  /// Live stream for a specific duel document.
  static Stream<DuelSession?> watchDuel(String duelId) {
    return _duels.doc(duelId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return DuelSession.fromMap(snap.id, snap.data()!);
    });
  }
}
