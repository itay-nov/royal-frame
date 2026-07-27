import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

const String _debugMinimumSupportedBuild = String.fromEnvironment(
  'DEBUG_MIN_SUPPORTED_BUILD',
);

enum AppBuildMode { debug, profile, release }

/// The release metadata published in `/version.json`.
///
/// [latestVersion] and [latestBuild] remain available for future optional
/// update features. Only [minimumSupportedBuild] is used by the forced-update
/// policy.
@immutable
class VersionManifest {
  const VersionManifest({
    required this.latestVersion,
    required this.latestBuild,
    required this.minimumSupportedBuild,
  });

  factory VersionManifest.fromJson(Map<String, dynamic> json) {
    return VersionManifest(
      latestVersion: json['version'],
      latestBuild: json['build_number'],
      minimumSupportedBuild: json['minimumSupportedBuild'],
    );
  }

  final Object? latestVersion;
  final Object? latestBuild;
  final Object? minimumSupportedBuild;
}

/// Enforces the minimum supported Android build published in version.json.
class UpdateService {
  UpdateService._();

  static final Uri _versionManifestUri = Uri.parse(
    'https://royal-frame.netlify.app/version.json',
  );

  /// Returns false when the policy cannot be checked, so missing/invalid
  /// metadata or a network failure never locks a player out.
  static Future<bool> isUpdateRequired() async {
    if (!supportsPlatform(isWeb: kIsWeb, platform: defaultTargetPlatform)) {
      return false;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();

      // A valid debug override is intentionally independent of the remote
      // manifest so forced-update UI can be tested without network access.
      if (_currentBuildMode == AppBuildMode.debug) {
        final debugMinimum = _parsePositiveBuild(_debugMinimumSupportedBuild);
        if (debugMinimum != null) {
          return _isBelowMinimum(packageInfo.buildNumber, debugMinimum);
        }
      }

      final response = await http
          .get(
            _versionManifestUri,
            headers: const {'Cache-Control': 'no-cache'},
          )
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) return false;

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) return false;

      return shouldBlockForManifest(
        installedBuild: packageInfo.buildNumber,
        manifest: VersionManifest.fromJson(payload),
        buildMode: _currentBuildMode,
        platform: defaultTargetPlatform,
        debugMinimumSupportedBuild: _debugMinimumSupportedBuild,
      );
    } catch (error) {
      debugPrint('[UpdateService] Minimum-build check skipped: $error');
      return false;
    }
  }

  @visibleForTesting
  static bool supportsPlatform({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    return !isWeb && platform == TargetPlatform.android;
  }

  @visibleForTesting
  static bool shouldBlockForManifest({
    required Object? installedBuild,
    required VersionManifest manifest,
    AppBuildMode buildMode = AppBuildMode.release,
    TargetPlatform platform = TargetPlatform.android,
    String debugMinimumSupportedBuild = '',
  }) {
    final remoteMinimum = _parseBuild(manifest.minimumSupportedBuild);
    final debugMinimum =
        buildMode == AppBuildMode.debug && platform == TargetPlatform.android
        ? _parsePositiveBuild(debugMinimumSupportedBuild)
        : null;
    final minimum = debugMinimum ?? remoteMinimum;
    if (minimum == null) return false;
    return _isBelowMinimum(installedBuild, minimum);
  }

  static AppBuildMode get _currentBuildMode {
    if (kDebugMode) return AppBuildMode.debug;
    if (kProfileMode) return AppBuildMode.profile;
    return AppBuildMode.release;
  }

  static bool _isBelowMinimum(Object? installedBuild, int minimum) {
    final current = _parseBuild(installedBuild);
    return current != null && current < minimum;
  }

  static int? _parseBuild(Object? value) {
    final parsed = switch (value) {
      int build => build,
      String build => int.tryParse(build.trim()),
      _ => null,
    };
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  static int? _parsePositiveBuild(Object? value) {
    final parsed = _parseBuild(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
