# Feature: In-app review prompt

Status: Ready for implementation

Target branch: `codex/in-app-review-prompt`

## Goal

After a player has shown sustained, legitimate engagement—two valid
completed-frame victories in a second-or-later gameplay session—invite an
honest Google Play rating without interrupting normal gameplay. Android uses
the official Google Play In-App Review API; Web uses a clearly labeled Royal
Frame invitation to the Android game's Google Play listing.

## User-visible behavior

### Shared eligibility

- Production eligibility requires at least two lifetime valid completed-frame
  victories, session two or later, no active cooldown, and fewer than three
  lifetime invitation attempts. Session one and the first victory are always
  ineligible.
- A loss, illegal move, startup failure, error, crash recovery, forced-update
  state, duel abandonment, or merely opening a winner overlay must not create
  eligibility.
- The invitation must not appear while any blocking dialog or overlay is active,
  including a winner/loss overlay or the forced-update gate. A qualifying event
  may be queued only until normal gameplay is unblocked; discard it if the
  player is no longer eligible then.
- Use a 30-day cooldown after every invitation attempt and a lifetime maximum
  of three attempts. These must be centralized named constants with injectable
  time for tests.
- Never offer coins, XP, features, gameplay advantages, or any other reward.
  Never ask for a specifically positive or five-star rating.
- Closing, dismissing, or declining the Web invitation immediately returns focus
  to normal gameplay. Persist dismissal state as needed to enforce the attempt
  and cooldown policy.

### Android

- Use the official Google Play In-App Review API on Android only, and only when
  shared eligibility is met. Do not use a custom pre-screen, opinion question,
  permanent rate button, or custom imitation of the native dialog.
- Do not assume the native review dialog will appear. There is no reliable
  indication that it appeared or that the user submitted a review.
- A completed Android review API request counts as one invitation attempt, even
  if Google suppresses or does not show its dialog. Persist the attempt and
  apply the 30-day cooldown and three-attempt lifetime limit.
- API failure, quota suppression, unavailable Play services, request failure,
  launch failure, or an exception must have no gameplay effect. Do not retry in
  a tight loop or show an error to the player.
- Never permanently mark a player as reviewed merely because an Android review
  request completed.

### Web

- Show a lightweight, localized Royal Frame rating invitation after shared
  eligibility is met. It must clearly say that the action rates the Android game
  on Google Play.
- The positive action must open exactly
  `https://play.google.com/store/apps/details?id=com.itay.royalframegame` in a
  new browser tab through a user-gesture-safe path.
- The invitation must work in mobile Safari on an iPhone. It must not imitate,
  embed, or be described as the native Google Play review dialog.
- Rendering the Web invitation counts as one invitation attempt. A browser
  launch failure must leave gameplay usable and must not permanently suppress
  future eligibility (the normal cooldown and lifetime-attempt policy still
  applies).
- If the Google Play destination launches successfully, persist that success and
  never show the Web invitation again for that install.

### Debug support

- Add a compile-time debug-only override, such as
  `DEBUG_RATING_INVITATION=true`, that makes the invitation immediately eligible
  for local testing without manually changing stored production state.
- The override must support testing the Web prompt from mobile Safari on an
  iPhone and Android eligibility/action dispatch even when Google elects not to
  display the native dialog.
- The override is unavailable and ignored in profile/release builds unless
  normal production eligibility is independently met. It must not rewrite or
  weaken persisted production policy state.

## Non-goals

- No implementation for iOS, macOS, Windows, Linux, ChromeOS-specific UI, or a
  custom Android rating dialog.
- No backend, analytics service, cloud eligibility, remote configuration,
  reward, review sentiment gate, or paid dependency.
- No attempt to detect whether the native dialog appeared, which rating was
  chosen, or whether a review was submitted.
- No changes to win/loss rules, scoring, XP, ads, duel results, onboarding, or
  the Android forced-update policy.
- No feature implementation on the infrastructure branch.

## Platform scope

Production Android and Flutter Web only. Android dispatch must compile and run
only on Android. Web launch/UI code must compile and run only on Web. All other
platforms receive a no-op adapter and no invitation UI.

Android application ID and listing ID are `com.itay.royalframegame`. The worker
must verify the current official integration instructions before selecting a
dependency or bridge.

## Release visibility

The normal eligibility flow is a production feature on Android and Web.
Debug-only forcing is visible only in debug builds. Profile/release artifacts
must behave as though the debug define were absent unless normal production
eligibility independently allows an invitation.

## Architecture constraints

- Add a pure, platform-neutral eligibility policy/service with injected clock
  and local persistence. Keep platform actions behind interfaces/adapters so
  eligibility tests do not invoke Play Core or a browser.
- Observe the existing legitimate transition to `Phase.winner` in `BoardScreen`;
  do not change `lib/models/game_model.dart`. Deduplicate repeated end-state
  checks so one victory produces at most one victory count and invitation flow.
- Keep the invitation subordinate to gameplay. Do not delay confetti, audio,
  XP, score reporting, navigation, or Play Again.
- Use `SharedPreferences` for non-sensitive local state. Persist at least:
  session count, lifetime victory count, last attempt date, lifetime attempt
  count, any dismissal state needed for enforcement, and successful Web Google
  Play launch state. Defensively parse malformed or old stored data.
- Implement one shared policy and separate Android/Web actions using conditional
  imports or equivalent compile-time platform isolation.
- Android delegates to the official Google Play In-App Review API. Follow
  [Google's request, design, and quota guidance](https://developer.android.com/guide/playcore/in-app-review).
- Web may reuse `url_launcher`; a launch must request a new tab/window and
  expose a testable success/failure result.
- Add English and Hebrew copy through the existing `L` localization surface.
  Hebrew needs correct directionality, semantic labels, and usable touch targets.
- Do not add an OpenAI API dependency, paid service, remote data store, or any
  signing/authentication access.
- The forced-update gate remains earlier and authoritative. Prompt
  initialization/session counting must not occur on `UpdateRequiredScreen`.

## Acceptance criteria

- [ ] Android and Web share one eligibility policy and dispatch different,
  correct platform actions.
- [ ] Session one never triggers a prompt, including after a valid victory.
- [ ] The first victory never triggers a prompt; two valid victories in session
  two or later can make the player eligible.
- [ ] Loss, startup failure, error, crash recovery, forced update, and
  duel-abandonment paths cannot create eligibility.
- [ ] A 30-day cooldown and three-attempt lifetime maximum persist across
  restarts.
- [ ] Android completion counts as an attempt but never proves that a dialog
  appeared or a review was submitted.
- [ ] Android API failure, unavailability, or suppression leaves gameplay
  unchanged.
- [ ] Web clearly labels Google Play/Android, opens the exact listing in a new
  tab, supports mobile Safari, and fails safely when browser launch fails.
- [ ] Successful Web listing launch permanently suppresses future Web prompts;
  browser-launch failure does not permanently suppress future eligibility.
- [ ] No invitation appears over a forced-update gate or another blocking
  dialog/overlay.
- [ ] The debug override cannot weaken release behavior.
- [ ] Normal gameplay, winner/loss flows, and the forced-update gate remain
  behaviorally unchanged.

## Required automated tests

- First session never triggers an invitation.
- First victory never triggers an invitation; two valid victories in session two
  or later can make the player eligible.
- Losses do not make the player eligible.
- The exact 30-day cooldown boundary and three-attempt lifetime limit work and
  persist across reloads.
- Android and Web dispatch only their correct platform-specific actions.
- A completed Android review request counts as an attempt but cannot be read as
  proof that the dialog appeared or a review was submitted.
- Android API failure fails safely without changing gameplay.
- Successful Web listing launch permanently suppresses Web invitations; browser
  launch failure does not permanently suppress future eligibility and gameplay
  remains usable.
- No prompt appears over a forced-update gate or another blocking overlay.
- The debug override works in debug but has no effect on release eligibility.
- Existing normal-gameplay and forced-update tests remain unchanged. Run
  `flutter test` after the focused suite.

## Required manual tests

- Android physical device: verify no prompt in the first session or after only
  one victory, then verify eligibility after two valid victories in a later
  session without depending on Google choosing to display its dialog.
- Google Play Internal Testing: use an appropriately versioned build and follow
  [Google's in-app review testing guide](https://developer.android.com/guide/playcore/in-app-review/test).
  Record device/account prerequisites and outcome; dialog absence alone is not
  an implementation failure.
- Android with the debug override: verify eligibility/action dispatch and safe
  behavior with unavailable Play services or an injected failing adapter.
- Web on a physical iPhone in mobile Safari: use the debug override, verify the
  localized invitation, exact listing in a new tab from a direct tap, safe
  dismissal, safe blocked-popup behavior, and permanent suppression after a
  successful destination launch.
- Release/profile Android and Web smoke tests with the debug define supplied:
  verify it does not bypass production eligibility. Verify forced-update and
  blocking overlays never present an invitation.

## Stop conditions

- Stop for a product decision if the definition of a valid victory/session,
  successful Web destination launch, 30-day cooldown, three-attempt maximum,
  copy, or listing URL must change.
- Stop if the official Android integration cannot be used safely in this
  Flutter/Android setup without an unsupported or unmaintained bridge.
- Stop if implementation requires changing the locked game engine, weakening
  the forced-update gate, reading signing/authentication data, or adding a
  backend/paid dependency.
- Stop if Android/Web cannot be compile-time isolated or release builds cannot
  prove the debug override is ignored.
- Stop if required automated tests fail or a physical-device/Internal Testing
  prerequisite is unavailable; do not claim external validation passed.

## Files or systems that must not be modified

- `AGENTS.md`
- `docs/agent-loop/`
- `docs/features/in-app-review-prompt.md`
- `docs/features/marketing-capture-mode.md`
- `tool/agent_loop/`
- `lib/models/game_model.dart`
- Android forced-update policy/behavior in `lib/services/update_service.dart`,
  `lib/screens/update_required_screen.dart`,
  `tool/add_minimum_supported_build.dart`, `netlify.toml`, and
  `docs/android-force-update.md`
- Firebase projects, Firestore rules/data, App Check settings, Play Console
  production rollout state, and Netlify deployment configuration
- `android/key.properties`, `*.jks`, `*.keystore`, `*.p12`, `*.pfx`,
  `*.mobileprovision`, certificates, provisioning profiles, and signing
  configuration/material
- Version/build numbers, release notes, deployment files, and release branches
