import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rating_invitation_platform.dart';

const Duration ratingInvitationCooldown = Duration(days: 30);
const int ratingInvitationMinimumSessions = 2;
const int ratingInvitationMinimumVictories = 2;
const int ratingInvitationMaximumAttempts = 3;
const bool _ratingInvitationDebugDefine = bool.fromEnvironment(
  'DEBUG_RATING_INVITATION',
);

typedef RatingInvitationClock = DateTime Function();

/// Stable owner for one real gameplay session's opaque rating identifier.
///
/// The owner can exist before gameplay starts, but the identifier is created
/// only at [startNew]. Mutable or cloned game state never becomes the identity.
class RatingGameplaySession {
  Object? _identifier;

  Object? get identifier => _identifier;

  Object startIfNeeded() => _identifier ??= Object();

  Object startNew() => _identifier = Object();
}

@immutable
class RatingInvitationState {
  final int sessionCount;
  final int victoryCount;
  final DateTime? lastAttemptAt;
  final int attemptCount;
  final bool webPlayStoreLaunchSucceeded;

  const RatingInvitationState({
    this.sessionCount = 0,
    this.victoryCount = 0,
    this.lastAttemptAt,
    this.attemptCount = 0,
    this.webPlayStoreLaunchSucceeded = false,
  });

  RatingInvitationState copyWith({
    int? sessionCount,
    int? victoryCount,
    DateTime? lastAttemptAt,
    int? attemptCount,
    bool? webPlayStoreLaunchSucceeded,
  }) {
    return RatingInvitationState(
      sessionCount: sessionCount ?? this.sessionCount,
      victoryCount: victoryCount ?? this.victoryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      attemptCount: attemptCount ?? this.attemptCount,
      webPlayStoreLaunchSucceeded:
          webPlayStoreLaunchSucceeded ?? this.webPlayStoreLaunchSucceeded,
    );
  }
}

abstract interface class RatingInvitationStore {
  Future<RatingInvitationState> load();
  Future<void> save(RatingInvitationState state);
}

class SharedPreferencesRatingInvitationStore implements RatingInvitationStore {
  static const String _sessionCountKey = 'ratingInvitationSessionCount';
  static const String _victoryCountKey = 'ratingInvitationVictoryCount';
  static const String _lastAttemptKey = 'ratingInvitationLastAttemptUtc';
  static const String _attemptCountKey = 'ratingInvitationAttemptCount';
  static const String _webLaunchSucceededKey =
      'ratingInvitationWebPlayStoreLaunchSucceeded';

  @override
  Future<RatingInvitationState> load() async {
    final preferences = await SharedPreferences.getInstance();
    return RatingInvitationState(
      sessionCount: _nonNegativeInt(preferences.get(_sessionCountKey)),
      victoryCount: _nonNegativeInt(preferences.get(_victoryCountKey)),
      lastAttemptAt: _dateTime(preferences.get(_lastAttemptKey)),
      attemptCount: _nonNegativeInt(preferences.get(_attemptCountKey)),
      webPlayStoreLaunchSucceeded:
          preferences.get(_webLaunchSucceededKey) is bool
          ? preferences.get(_webLaunchSucceededKey) as bool
          : false,
    );
  }

  @override
  Future<void> save(RatingInvitationState state) async {
    final preferences = await SharedPreferences.getInstance();
    final results = await Future.wait<bool>([
      preferences.setInt(_sessionCountKey, state.sessionCount),
      preferences.setInt(_victoryCountKey, state.victoryCount),
      preferences.setInt(_attemptCountKey, state.attemptCount),
      preferences.setBool(
        _webLaunchSucceededKey,
        state.webPlayStoreLaunchSucceeded,
      ),
      if (state.lastAttemptAt != null)
        preferences.setString(
          _lastAttemptKey,
          state.lastAttemptAt!.toUtc().toIso8601String(),
        )
      else
        preferences.remove(_lastAttemptKey),
    ]);
    if (results.any((succeeded) => !succeeded)) {
      throw StateError('Could not persist rating invitation state');
    }
  }

  static int _nonNegativeInt(Object? value) {
    if (value is int && value >= 0) return value;
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null && parsed >= 0) return parsed;
    }
    return 0;
  }

  static DateTime? _dateTime(Object? value) {
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    if (value is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      } on RangeError {
        return null;
      }
    }
    return null;
  }
}

@immutable
class RatingInvitationEligibility {
  final bool isEligible;
  final bool usesDebugOverride;

  const RatingInvitationEligibility({
    required this.isEligible,
    required this.usesDebugOverride,
  });
}

class RatingInvitationPolicy {
  final RatingInvitationClock clock;
  final bool isDebugBuild;
  final bool debugDefineEnabled;

  const RatingInvitationPolicy({
    required this.clock,
    required this.isDebugBuild,
    required this.debugDefineEnabled,
  });

  factory RatingInvitationPolicy.production() {
    return RatingInvitationPolicy(
      clock: DateTime.now,
      isDebugBuild: kDebugMode,
      debugDefineEnabled: _ratingInvitationDebugDefine,
    );
  }

  RatingInvitationEligibility evaluate(
    RatingInvitationState state,
    RatingInvitationPlatform platform,
  ) {
    if (platform == RatingInvitationPlatform.unsupported) {
      return const RatingInvitationEligibility(
        isEligible: false,
        usesDebugOverride: false,
      );
    }

    final now = clock().toUtc();
    final lastAttempt = state.lastAttemptAt?.toUtc();
    final cooldownComplete =
        lastAttempt == null ||
        !now.isBefore(lastAttempt.add(ratingInvitationCooldown));
    final webCanInvite =
        platform != RatingInvitationPlatform.web ||
        !state.webPlayStoreLaunchSucceeded;
    final productionEligible =
        state.sessionCount >= ratingInvitationMinimumSessions &&
        state.victoryCount >= ratingInvitationMinimumVictories &&
        state.attemptCount < ratingInvitationMaximumAttempts &&
        cooldownComplete &&
        webCanInvite;
    final debugEligible = isDebugBuild && debugDefineEnabled;

    return RatingInvitationEligibility(
      isEligible: productionEligible || debugEligible,
      usesDebugOverride: debugEligible,
    );
  }
}

enum RatingInvitationDispatch { none, androidRequested, webReadyToPresent }

class RatingInvitationCoordinator {
  final RatingInvitationStore _store;
  final RatingInvitationPolicy _policy;
  final RatingInvitationPlatformAdapter _platformAdapter;

  RatingInvitationState? _state;
  final Expando<Future<bool>> _sessionStarts = Expando<Future<bool>>();
  Future<void> _sessionStartQueue = Future<void>.value();
  final Object _implicitSessionToken = Object();
  bool _pendingInvitation = false;
  bool _webInvitationPendingPresentation = false;
  bool _webInvitationActive = false;
  bool _activeWebInvitationUsesDebugOverride = false;
  int _pendingGeneration = 0;

  RatingInvitationCoordinator({
    RatingInvitationStore? store,
    RatingInvitationPolicy? policy,
    RatingInvitationPlatformAdapter? platformAdapter,
  }) : _store = store ?? SharedPreferencesRatingInvitationStore(),
       _policy = policy ?? RatingInvitationPolicy.production(),
       _platformAdapter =
           platformAdapter ?? createRatingInvitationPlatformAdapter();

  RatingInvitationPlatform get platform => _platformAdapter.platform;

  Future<bool> beginGameplaySession({Object? sessionToken}) {
    final token = sessionToken ?? _implicitSessionToken;
    final existing = _sessionStarts[token];
    if (existing != null) return existing;

    final start = _sessionStartQueue.then((_) => _beginGameplaySession());
    _sessionStarts[token] = start;
    _sessionStartQueue = start.then<void>((_) {});
    return start;
  }

  Future<bool> _beginGameplaySession() async {
    try {
      final loaded = await _store.load();
      final updated = loaded.copyWith(sessionCount: loaded.sessionCount + 1);
      await _store.save(updated);
      _state = updated;
      final eligibility = _policy.evaluate(updated, _platformAdapter.platform);
      if (eligibility.usesDebugOverride) {
        _pendingInvitation = true;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> recordCompletedFrameVictory({Object? sessionToken}) async {
    final generation = _pendingGeneration;
    if (await beginGameplaySession(sessionToken: sessionToken) != true ||
        _state == null) {
      return false;
    }
    try {
      final updated = _state!.copyWith(victoryCount: _state!.victoryCount + 1);
      await _store.save(updated);
      _state = updated;
      if (generation != _pendingGeneration) return false;
      _pendingInvitation = _policy
          .evaluate(updated, _platformAdapter.platform)
          .isEligible;
      return _pendingInvitation;
    } catch (_) {
      return false;
    }
  }

  Future<RatingInvitationDispatch> dispatchPendingInvitation({
    required bool gameplayUnblocked,
  }) async {
    if (!gameplayUnblocked || !_pendingInvitation || _state == null) {
      return RatingInvitationDispatch.none;
    }

    final eligibility = _policy.evaluate(_state!, _platformAdapter.platform);
    if (!eligibility.isEligible) {
      _pendingInvitation = false;
      return RatingInvitationDispatch.none;
    }

    switch (_platformAdapter.platform) {
      case RatingInvitationPlatform.android:
        _pendingInvitation = false;
        bool requestCompleted;
        try {
          requestCompleted = await _platformAdapter.requestAndroidReview();
        } catch (_) {
          requestCompleted = false;
        }
        if (!requestCompleted) return RatingInvitationDispatch.none;
        if (!eligibility.usesDebugOverride) {
          final saved = await _recordAttempt();
          if (!saved) {
            return RatingInvitationDispatch.none;
          }
        }
        return RatingInvitationDispatch.androidRequested;
      case RatingInvitationPlatform.web:
        _pendingInvitation = false;
        _webInvitationPendingPresentation = true;
        _activeWebInvitationUsesDebugOverride = eligibility.usesDebugOverride;
        return RatingInvitationDispatch.webReadyToPresent;
      case RatingInvitationPlatform.unsupported:
        _pendingInvitation = false;
        return RatingInvitationDispatch.none;
    }
  }

  Future<bool> confirmWebInvitationPresented() async {
    if (!_webInvitationPendingPresentation ||
        _platformAdapter.platform != RatingInvitationPlatform.web ||
        _state == null) {
      return false;
    }

    _webInvitationPendingPresentation = false;
    _webInvitationActive = true;
    if (_activeWebInvitationUsesDebugOverride) {
      return true;
    }

    final saved = await _recordAttempt();
    if (!saved) {
      _webInvitationActive = false;
      _activeWebInvitationUsesDebugOverride = false;
      return false;
    }
    return true;
  }

  void cancelWebInvitationPresentation({bool retry = true}) {
    if (!_webInvitationPendingPresentation) {
      return;
    }

    _webInvitationPendingPresentation = false;
    _webInvitationActive = false;
    _activeWebInvitationUsesDebugOverride = false;
    if (retry) {
      _pendingInvitation = true;
    }
  }

  Future<bool> _recordAttempt() async {
    if (_state == null) return false;
    final updated = _state!.copyWith(
      attemptCount: _state!.attemptCount + 1,
      lastAttemptAt: _policy.clock().toUtc(),
    );
    try {
      await _store.save(updated);
      _state = updated;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Must be called directly from the Web invitation's positive tap handler.
  Future<bool> launchWebPlayStore() {
    if (!_webInvitationActive ||
        _platformAdapter.platform != RatingInvitationPlatform.web) {
      return Future<bool>.value(false);
    }

    // Start the browser operation before any await so mobile Safari sees it as
    // part of the user's gesture.
    late final Future<bool> launch;
    try {
      launch = _platformAdapter.launchWebListing();
    } catch (_) {
      _webInvitationActive = false;
      _activeWebInvitationUsesDebugOverride = false;
      return Future<bool>.value(false);
    }
    _webInvitationActive = false;
    return launch
        .then((didLaunch) async {
          if (didLaunch &&
              !_activeWebInvitationUsesDebugOverride &&
              _state != null) {
            final updated = _state!.copyWith(webPlayStoreLaunchSucceeded: true);
            _state = updated;
            try {
              await _store.save(updated);
            } catch (_) {
              // The destination already opened. Persistence failure must not affect
              // gameplay or trigger a tight retry.
            }
          }
          _activeWebInvitationUsesDebugOverride = false;
          return didLaunch;
        })
        .catchError((_) {
          _activeWebInvitationUsesDebugOverride = false;
          return false;
        });
  }

  void dismissWebInvitation() {
    _webInvitationActive = false;
    _activeWebInvitationUsesDebugOverride = false;
  }

  void discardPendingInvitation() {
    _pendingGeneration++;
    _pendingInvitation = false;
    _webInvitationPendingPresentation = false;
    dismissWebInvitation();
  }
}
