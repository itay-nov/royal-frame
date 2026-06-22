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

  // Per-player stats written at game end
  final int? hostTime;    // elapsed seconds
  final int? guestTime;
  final int? hostRoyals;  // royalsPlacedCorrect
  final int? guestRoyals;

  // Rematch coordination: keyed by uid → true when that player is ready
  final Map<String, bool> rematchReady;

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
    this.hostTime,
    this.guestTime,
    this.hostRoyals,
    this.guestRoyals,
    this.rematchReady = const {},
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
      hostTime: (data['hostTime'] as num?)?.toInt(),
      guestTime: (data['guestTime'] as num?)?.toInt(),
      hostRoyals: (data['hostRoyals'] as num?)?.toInt(),
      guestRoyals: (data['guestRoyals'] as num?)?.toInt(),
      rematchReady: Map<String, bool>.from(
          (data['rematchReady'] as Map?) ?? {}),
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
        'hostTime': hostTime,
        'guestTime': guestTime,
        'hostRoyals': hostRoyals,
        'guestRoyals': guestRoyals,
        'rematchReady': rematchReady,
      };

  bool get isFinished => status == DuelStatus.finished;
  bool get isActive   => status == DuelStatus.active;
  bool get isWaiting  => status == DuelStatus.waiting;

  bool get bothRematchReady =>
      hostUid.isNotEmpty &&
      (guestUid?.isNotEmpty ?? false) &&
      (rematchReady[hostUid] == true) &&
      (rematchReady[guestUid] == true);
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
  static Future<void> markFinished(
    String duelId,
    int finalScore, {
    required int elapsedSeconds,
    required int royalsPlaced,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _db.runTransaction((tx) async {
      final ref = _duels.doc(duelId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data()!;
      final isHost = data['hostUid'] == uid;

      final updates = <String, dynamic>{
        isHost ? 'hostScore'    : 'guestScore':    finalScore,
        isHost ? 'hostFinished' : 'guestFinished': true,
        isHost ? 'hostTime'     : 'guestTime':     elapsedSeconds,
        isHost ? 'hostRoyals'   : 'guestRoyals':   royalsPlaced,
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

  // ── Rematch ────────────────────────────────────────────────────────────────

  /// Signals that this player is ready for a rematch.
  /// Host also provides a new seed. When both players signal, the doc is
  /// reset in-place so the stream fires and both clients start the new game.
  static Future<void> signalRematch(
    String duelId, {
    required bool isHost,
    int? newSeed,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _db.runTransaction((tx) async {
      final ref = _duels.doc(duelId);
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data()!;
      final currentReady = Map<String, bool>.from(
          (data['rematchReady'] as Map?) ?? {});
      currentReady[uid] = true;

      final hostUid  = data['hostUid']  as String? ?? '';
      final guestUid = data['guestUid'] as String? ?? '';
      final bothReady = hostUid.isNotEmpty &&
          guestUid.isNotEmpty &&
          (currentReady[hostUid] == true) &&
          (currentReady[guestUid] == true);

      if (bothReady) {
        // Both ready — reset the doc for the new round
        final seed = isHost
            ? (newSeed ?? Random().nextInt(0x7FFFFFFF))
            : (data['seed'] as num?)?.toInt() ?? Random().nextInt(0x7FFFFFFF);
        tx.update(ref, {
          'status':        DuelStatus.active.name,
          'seed':          seed,
          'hostScore':     0,
          'guestScore':    0,
          'hostFinished':  false,
          'guestFinished': false,
          'hostTime':      FieldValue.delete(),
          'guestTime':     FieldValue.delete(),
          'hostRoyals':    FieldValue.delete(),
          'guestRoyals':   FieldValue.delete(),
          'winnerId':      FieldValue.delete(),
          'rematchReady':  {},
        });
      } else {
        // Just mark this player as ready (+ write new seed if host)
        final updates = <String, dynamic>{
          'rematchReady': currentReady,
        };
        if (isHost && newSeed != null) {
          updates['seed'] = newSeed;
        }
        tx.update(ref, updates);
      }
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
