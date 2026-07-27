# Android forced updates

Royal Frame uses the deployed web `version.json` as an Android update-policy
manifest. Flutter continues to generate the existing latest release fields.
The following numbers are illustrative only and are not a statement about the
current Google Play Production release:

```json
{
  "app_name": "royal_frame",
  "version": "2.3.4",
  "build_number": "123",
  "package_name": "royal_frame",
  "minimumSupportedBuild": 120
}
```

`version` and `build_number` describe the latest web build and are reserved for
future informational or optional-update behavior. They never force an Android
update. Android is blocked only when its installed `versionCode` is less than
`minimumSupportedBuild`.

## Current rollout baseline

Google Play Production is currently Build 12. The first release that contains
this checker must use Build 13 or higher. Build 12 cannot be remotely forced to
update because it does not contain the checker.

Do not bump this feature branch's `pubspec.yaml` for that release yet. The Build
13-or-higher release bump belongs in the merged release work after the feature
branches are combined.

## Determine the real production build

Do not infer the production build from `pubspec.yaml`, Git, a local APK, or
`version.json`. Google Play is the source of truth.

1. Open Royal Frame in Google Play Console.
2. Open **Test and release > Production** and inspect the active release,
   including its rollout status and app bundles.
3. Confirm the production artifact's version code under **Test and release >
   Latest releases and bundles** using the version filter and release details.
4. If a rollout is staged, verify which version codes are actually available
   to the intended production audience before changing the minimum.

Google documents the current console flow in
[Prepare and roll out a release](https://support.google.com/googleplay/android-developer/answer/9859348)
and
[Inspect app versions](https://support.google.com/googleplay/android-developer/answer/9844279).

The Android package is `com.itay.royalframegame`. The production listing is:

<https://play.google.com/store/apps/details?id=com.itay.royalframegame>

## Normal releases

1. Choose a new Android build number greater than every version code already
   uploaded to Google Play.
2. Build, sign, test, and publish the Android App Bundle normally.
3. Confirm the actual Production release and rollout state in Play Console.
4. Leave `minimumSupportedBuild` unchanged.
5. Build and deploy the web app. Supply the unchanged minimum through the
   required manifest command:

   ```sh
   dart run tool/add_minimum_supported_build.dart --minimum <current-minimum>
   ```

The Netlify build expects `MINIMUM_SUPPORTED_ANDROID_BUILD` to hold that
verified policy value. A missing or invalid value fails the deployment rather
than publishing an ambiguous manifest.

## Mandatory update releases

There is no fixed number of supported builds. Compatibility determines the
minimum: backend or data-format changes, security requirements, broken clients,
and other concrete product constraints may require an update. A routine release
does not.

Leave `minimumSupportedBuild` unchanged while the older build remains safe and
compatible. Raise it only when all of the following are true:

- the replacement build has passed release testing;
- Google Play Production shows the intended version code as available;
- the rollout covers every user who will be blocked;
- the Play listing can install that build for supported devices; and
- rollback steps and the previous safe minimum are recorded.

For a mandatory release:

1. Publish the replacement build to Google Play.
2. Wait for review and the required Production rollout coverage.
3. Verify the real version code in Play Console.
4. Set `MINIMUM_SUPPORTED_ANDROID_BUILD` to the lowest build that remains safe.
   It does not have to equal the latest build.
5. Deploy the web app and verify `/version.json` contains the intended integer
   `minimumSupportedBuild`.
6. Test one build below the minimum and one build at or above it.

Never raise the minimum to a build that is only in a test track, still in
review, unavailable in some targeted countries, or not yet served to all users
covered by the mandatory update.

## Debug testing

The Android debug build supports a compile-time override without adding any
developer menu or production UI:

```sh
flutter run -d <device-id> \
  --dart-define=DEBUG_MIN_SUPPORTED_BUILD=<positive-build-above-installed>
```

Replace both placeholders before running the command.

This should show the blocking screen, prevent Android back navigation, and open
the Royal Frame Google Play listing from **Update**. Returning without
installing a newer build rechecks the policy and remains blocked.

The override is accepted only in Flutter debug mode on Android. It is ignored
on iOS and web, and in Android profile and release builds. An absent, malformed,
zero, or negative override has no effect; the remote minimum remains
authoritative. Run normally without the `--dart-define` to exercise the remote
policy.

## Rollback

If the minimum was raised incorrectly:

1. Identify the lowest build that is safe and actually available in Google Play
   Production.
2. Set `MINIMUM_SUPPORTED_ANDROID_BUILD` to that value.
3. Redeploy the web app immediately.
4. Verify the deployed `/version.json` directly.
5. Relaunch an affected Android build and confirm access is restored.

Removing the field or publishing an invalid value also fails open in the app,
but an explicit valid rollback value is safer and auditable.

## Local policy cache

There is no application-level cache today. Each native Android launch requests
`version.json` with `Cache-Control: no-cache`, keeps the parsed minimum only in
memory for that check, and then discards it. Nothing is written to shared
preferences, secure storage, or a file.

This means a network error, timeout, non-200 response, or invalid manifest fails
open even if the device fetched a valid minimum previously. It also means there
is no stale local policy that can prolong a bad forced update after a rollback.

The smallest safe future cache should:

1. store only a validated non-negative minimum and its fetch timestamp in
   Android shared preferences;
2. still try the network on every launch;
3. overwrite the cache when a valid remote value is received, including when
   the minimum is lowered for rollback;
4. clear and ignore the cache when a successful response deliberately omits or
   invalidates the field, preserving the documented fail-open behavior; and
5. use cached policy after transport failure only within an explicitly chosen
   maximum age, with tests for expiry and rollback.

A cache improves offline enforcement but creates a stale-policy window. The
maximum age is therefore a product and incident-response decision, not a value
to add implicitly.

## Known limitations

- Builds released before the forced-update checker was added do not fetch or
  enforce `minimumSupportedBuild`; the manifest cannot retroactively block
  them.
- The app currently does not persist the last valid minimum locally. Every
  Android launch fetches the manifest. Network errors, timeouts, non-200
  responses, and missing or invalid policy values fail open.
- Because the policy is fetched remotely, a first launch without network access
  cannot enforce a newly raised minimum.
