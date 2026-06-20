import 'dart:math';
import 'secure_storage_service.dart';
import 'xp_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GOAL TYPE ENUM
// Each value maps to exactly one DailyGoal in the pool.
// Use this enum when calling DailyGoalService.addProgress().
// ─────────────────────────────────────────────────────────────────────────────
enum GoalType {
  clearPair,    // "Professional Cleaner" - clear 5 pairs
  placeRoyal,   // "Royal Family"         - place 4 royals correctly
  finishMatch,  // "Marathon"             - finish 3 matches (win or lose)
  scorePoints,  // "High Scorer"          - accumulate 3000 score points
  useUndo,      // "Tactician"            - use Undo 3 times
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA MODEL
// ─────────────────────────────────────────────────────────────────────────────
class DailyGoal {
  final String id;
  final String title;
  final String description;
  final int targetValue;
  int currentValue;
  bool isCompleted;

  DailyGoal({
    required this.id,
    required this.title,
    required this.description,
    required this.targetValue,
    this.currentValue = 0,
    this.isCompleted = false,
  });

  double get progress =>
      (currentValue / targetValue).clamp(0.0, 1.0);

  /// Human-readable progress string, e.g. "2 / 5".
  String get progressLabel => '$currentValue / $targetValue';
}

// ─────────────────────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────────────────────
class DailyGoalService {
  // SharedPreferences keys
  static const _keyGoalId        = 'dg_goal_id';
  static const _keyGoalProgress  = 'dg_goal_progress';
  static const _keyGoalCompleted = 'dg_goal_completed';
  static const _keyAssignedDate  = 'dg_assigned_date';

  // In-memory state (populated by load())
  static DailyGoal? _current;

  /// The currently active goal. Null until [load] has been awaited.
  static DailyGoal? get current => _current;

  // ── Goal pool ──────────────────────────────────────────────────────────────

  static final List<DailyGoal> _pool = [
    DailyGoal(
      id: 'professional_cleaner',
      title: 'Professional Cleaner',
      description: 'Clear 5 pairs of cards overall.',
      targetValue: 5,
    ),
    DailyGoal(
      id: 'royal_family',
      title: 'Royal Family',
      description: 'Place 4 Royal cards in their correct slots.',
      targetValue: 4,
    ),
    DailyGoal(
      id: 'marathon',
      title: 'Marathon',
      description: 'Finish 3 matches (win or lose).',
      targetValue: 3,
    ),
    DailyGoal(
      id: 'high_scorer',
      title: 'High Scorer',
      description: 'Accumulate 3,000 score points overall.',
      targetValue: 3000,
    ),
    DailyGoal(
      id: 'tactician',
      title: 'Tactician',
      description: 'Use the Undo button 3 times.',
      targetValue: 3,
    ),
  ];

  // ── Date helper ───────────────────────────────────────────────────────────

  static String _todayString() {
    final now = DateTime.now();
    final y   = now.year.toString().padLeft(4, '0');
    final m   = now.month.toString().padLeft(2, '0');
    final d   = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  // ── Init / Load ───────────────────────────────────────────────────────────

  /// Call this once at app start, inside [initState] of your first stateful
  /// widget (or inside [_BoardScreenState.initState]).
  ///
  /// It checks whether a new day has started and, if so, picks a fresh goal
  /// from the pool at random. Otherwise it restores the saved progress.
  static Future<void> load() async {
    final today        = _todayString();
    final assignedDate = await SecureStorageService.read(_keyAssignedDate) ?? '';
    final savedGoalId  = await SecureStorageService.read(_keyGoalId) ?? '';

    if (assignedDate != today || savedGoalId.isEmpty) {
      await _assignNewGoal(today, previousId: savedGoalId);
    } else {
      final savedProgress  = await SecureStorageService.readInt(_keyGoalProgress)  ?? 0;
      final savedCompleted = await SecureStorageService.readBool(_keyGoalCompleted) ?? false;

      final template = _pool.firstWhere(
        (g) => g.id == savedGoalId,
        orElse: () => _pool.first,
      );

      _current = DailyGoal(
        id:           template.id,
        title:        template.title,
        description:  template.description,
        targetValue:  template.targetValue,
        currentValue: savedProgress,
        isCompleted:  savedCompleted,
      );
    }
  }

  static Future<void> _assignNewGoal(
    String today, {
    String previousId = '',
  }) async {
    final candidates = _pool.length > 1
        ? _pool.where((g) => g.id != previousId).toList()
        : _pool;

    final chosen = candidates[Random().nextInt(candidates.length)];

    _current = DailyGoal(
      id:          chosen.id,
      title:       chosen.title,
      description: chosen.description,
      targetValue: chosen.targetValue,
    );

    await SecureStorageService.write(_keyGoalId,       chosen.id);
    await SecureStorageService.writeInt(_keyGoalProgress, 0);
    await SecureStorageService.writeBool(_keyGoalCompleted, false);
    await SecureStorageService.write(_keyAssignedDate, today);
  }

  // ── Progress update ───────────────────────────────────────────────────────

  /// Add [amount] progress units for [type].
  ///
  /// The call is a no-op when:
  ///   * the goal is already completed, or
  ///   * [type] does not match today's active goal.
  ///
  /// Awards 250 XP via [XpService] the first time the goal is completed.
  static Future<void> addProgress(GoalType type, int amount) async {
    final goal = _current;
    if (goal == null || goal.isCompleted) return;
    if (_goalTypeForId(goal.id) != type)  return;

    goal.currentValue = min(goal.currentValue + amount, goal.targetValue);
    final justCompleted = goal.currentValue >= goal.targetValue;
    if (justCompleted) {
      goal.isCompleted = true;
    }

    await SecureStorageService.writeInt(_keyGoalProgress,  goal.currentValue);
    await SecureStorageService.writeBool(_keyGoalCompleted, goal.isCompleted);

    // Award XP bonus when the goal is completed for the first time today.
    if (justCompleted) {
      await XpService.addXP(250);
    }
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  /// Maps each goal id back to its [GoalType] so that [addProgress] can filter
  /// calls that don't match the current goal, preventing cross-contamination.
  static GoalType? _goalTypeForId(String id) => switch (id) {
    'professional_cleaner' => GoalType.clearPair,
    'royal_family'         => GoalType.placeRoyal,
    'marathon'             => GoalType.finishMatch,
    'high_scorer'          => GoalType.scorePoints,
    'tactician'            => GoalType.useUndo,
    _                      => null,
  };

  static Future<void> reset() async {
    _current = null;
    await SecureStorageService.delete(_keyGoalId);
    await SecureStorageService.delete(_keyGoalProgress);
    await SecureStorageService.delete(_keyGoalCompleted);
    await SecureStorageService.delete(_keyAssignedDate);
  }
}
