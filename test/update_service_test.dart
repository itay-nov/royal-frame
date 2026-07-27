import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:royal_frame/services/update_service.dart';
import 'package:royal_frame/utils/localization.dart';

void main() {
  VersionManifest manifest({
    Object? latestVersion = '1.1.1',
    Object? latestBuild = '10',
    Object? minimumSupportedBuild = 10,
  }) {
    return VersionManifest(
      latestVersion: latestVersion,
      latestBuild: latestBuild,
      minimumSupportedBuild: minimumSupportedBuild,
    );
  }

  group('minimum-supported Android build policy', () {
    test('blocks a build below minimumSupportedBuild', () {
      expect(
        UpdateService.shouldBlockForManifest(
          installedBuild: '9',
          manifest: manifest(),
        ),
        isTrue,
      );
    });

    test('allows a build equal to minimumSupportedBuild', () {
      expect(
        UpdateService.shouldBlockForManifest(
          installedBuild: '10',
          manifest: manifest(),
        ),
        isFalse,
      );
    });

    test('allows a build above minimumSupportedBuild', () {
      expect(
        UpdateService.shouldBlockForManifest(
          installedBuild: '11',
          manifest: manifest(),
        ),
        isFalse,
      );
    });

    test('a newer latest build does not force an update', () {
      final release = VersionManifest.fromJson({
        'version': '9.0.0',
        'build_number': '999',
        'minimumSupportedBuild': 10,
      });

      expect(release.latestVersion, '9.0.0');
      expect(release.latestBuild, '999');
      expect(
        UpdateService.shouldBlockForManifest(
          installedBuild: '10',
          manifest: release,
        ),
        isFalse,
      );
    });

    test('missing or invalid minimumSupportedBuild fails open', () {
      for (final invalidMinimum in <Object?>[
        null,
        '',
        'not-a-build',
        -1,
        10.5,
      ]) {
        expect(
          UpdateService.shouldBlockForManifest(
            installedBuild: '1',
            manifest: manifest(minimumSupportedBuild: invalidMinimum),
          ),
          isFalse,
          reason: 'minimumSupportedBuild=$invalidMinimum',
        );
      }
    });

    test('invalid installed build fails open', () {
      expect(
        UpdateService.shouldBlockForManifest(
          installedBuild: 'unknown',
          manifest: manifest(),
        ),
        isFalse,
      );
    });

    test('valid debug override replaces the remote minimum on Android', () {
      expect(
        UpdateService.shouldBlockForManifest(
          installedBuild: '10',
          manifest: manifest(minimumSupportedBuild: 1),
          buildMode: AppBuildMode.debug,
          platform: TargetPlatform.android,
          debugMinimumSupportedBuild: '11',
        ),
        isTrue,
      );
    });

    test('normal Android debug run uses the remote minimum', () {
      expect(
        UpdateService.shouldBlockForManifest(
          installedBuild: '10',
          manifest: manifest(minimumSupportedBuild: 10),
          buildMode: AppBuildMode.debug,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });

    test('absent, malformed, zero, or negative override has no effect', () {
      for (final invalidOverride in ['', 'invalid', '0', '-1']) {
        expect(
          UpdateService.shouldBlockForManifest(
            installedBuild: '10',
            manifest: manifest(minimumSupportedBuild: 10),
            buildMode: AppBuildMode.debug,
            platform: TargetPlatform.android,
            debugMinimumSupportedBuild: invalidOverride,
          ),
          isFalse,
          reason: 'DEBUG_MIN_SUPPORTED_BUILD=$invalidOverride',
        );
      }
    });

    test('iOS ignores the debug override', () {
      expect(
        UpdateService.shouldBlockForManifest(
          installedBuild: '10',
          manifest: manifest(minimumSupportedBuild: 10),
          buildMode: AppBuildMode.debug,
          platform: TargetPlatform.iOS,
          debugMinimumSupportedBuild: '11',
        ),
        isFalse,
      );
    });

    test('profile and release builds ignore the debug override', () {
      for (final buildMode in [AppBuildMode.profile, AppBuildMode.release]) {
        expect(
          UpdateService.shouldBlockForManifest(
            installedBuild: '10',
            manifest: manifest(minimumSupportedBuild: 10),
            buildMode: buildMode,
            platform: TargetPlatform.android,
            debugMinimumSupportedBuild: '11',
          ),
          isFalse,
          reason: 'buildMode=$buildMode',
        );
      }
    });
  });

  test('feature activates only for native Android', () {
    expect(
      UpdateService.supportsPlatform(
        isWeb: false,
        platform: TargetPlatform.android,
      ),
      isTrue,
    );
    expect(
      UpdateService.supportsPlatform(
        isWeb: true,
        platform: TargetPlatform.android,
      ),
      isFalse,
    );
    expect(
      UpdateService.supportsPlatform(
        isWeb: false,
        platform: TargetPlatform.iOS,
      ),
      isFalse,
    );
  });

  test('update-required copy and button are localized', () {
    expect(
      const L(AppLang.en).updateRequiredMessage,
      'Update the game to continue.',
    );
    expect(
      const L(AppLang.he).updateRequiredMessage,
      'עדכן את המשחק כדי להמשיך.',
    );
    expect(const L(AppLang.en).btnUpdate, 'Update');
    expect(const L(AppLang.he).btnUpdate, 'עדכון');
  });
}
