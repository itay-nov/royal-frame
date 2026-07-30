# Feature: Marketing capture mode

Status: Ready for future implementation

Target branch: `codex/marketing-capture-mode`

## Goal

Provide a deterministic, local, development-only way to stage Royal Frame game
scenes for recording marketing clips without exposing capture controls to
normal users, changing production gameplay, or introducing a cloud or paid
dependency.

## User-visible behavior

- When a Flutter debug build is launched with
  `ENABLE_MARKETING_CAPTURE=true`, a hidden developer entry point exposes a
  capture-mode scene picker.
- The picker provides deterministic named scenes for: clean opening board,
  active clear phase with a valid pair, near-complete royal frame, completed
  victory/winner overlay, and game-over/loss overlay.
- Selecting the same scene always produces the same cards, board occupancy,
  phase, score inputs, language, and starting timer state. Resetting a scene
  returns it to that exact initial state.
- Capture mode is visually labeled as development tooling. It may offer
  deterministic scene reset and English/Hebrew selection, but it must not add
  production rewards, progression, accounts, or remote data.
- Banner ads are hidden while capture mode is actively presenting or recording
  a capture scene. Leaving capture mode restores the build's normal ad behavior.
- Without both Flutter debug mode and the exact compile-time define, there is no
  capture entry point, route, gesture, query parameter, deep link, or persisted
  flag available to normal users.

## Non-goals

- Do not implement this feature on the agent-loop infrastructure branch.
- No video recording, editing, encoding, upload, cloud rendering, asset
  generation, screenshot automation, or marketing-content management.
- No production cheat menu, God Mode expansion, gameplay balancing, new game
  rules, score changes, ad-policy changes, or analytics.
- No iOS, macOS, Windows, or Linux deliverable in this first version.
- No backend, Firebase document, remote config, API key, paid service, or new
  hosted dependency.

## Platform scope

Flutter debug builds on Android and Web. Android profile/release and Web
profile/release are explicit no-ops. All other platforms are out of scope and
must compile without capture-mode implementations being reachable.

## Release visibility

Development-only. Activation requires both `kDebugMode` and the compile-time
boolean `ENABLE_MARKETING_CAPTURE=true`. Supplying the define to profile or
release builds has no effect. Capture state is not migrated into normal local
preferences and cannot survive into a normal launch.

## Architecture constraints

- Put capture configuration, named scenario builders, and gating in a dedicated
  debug-oriented module outside `lib/models/game_model.dart`.
- Reuse the public `GameState.newGame(seed: ...)`, clone, and public state
  surfaces where safe. Do not alter engine rules or add capture branches to
  gameplay algorithms.
- Inject a selected prebuilt `GameState` through the existing
  `BoardScreen.existingGame` seam or another narrow UI-level seam. Production
  board creation must remain unchanged.
- Keep scenario definitions deterministic and local. Avoid wall-clock,
  randomness without a fixed seed, Firebase/auth, network, device identity, and
  persisted user data.
- Centralize activation in one immutable gate that is false unless both the
  compile-time define and `kDebugMode` are true. Do not use a runtime-only
  preference, URL parameter, remote flag, secret tap available in release, or
  assert-only security.
- Centralize ad visibility behind a capture-session state supplied to the
  existing ad host. Do not disable ad initialization or ads globally; hide only
  `buildBannerAd()` output while an active capture scene is mounted.
- Existing audio, animation, confetti, timer, and lifecycle behavior may run
  during recording, but each scene's initial state and timer origin must reset
  deterministically. Any extra freeze/step controls require a product decision.
- Provide English and Hebrew labels using the existing localization approach.
- No cloud service, paid dependency, API key, or OpenAI API integration.

## Acceptance criteria

- [ ] The five named scenes load and reset to byte-for-byte equivalent logical
  state for the same scenario definition.
- [ ] Capture controls exist only when `kDebugMode` and
  `ENABLE_MARKETING_CAPTURE=true` are both true.
- [ ] Android profile/release and Web profile/release ignore the define and
  expose no route, control, gesture, or persisted activation path.
- [ ] Normal users and normal debug launches see no capture entry point.
- [ ] Ads are hidden only while capture mode is active and normal ad behavior
  returns immediately after exit.
- [ ] Scene setup performs no Firebase, authentication, Firestore, App Check,
  analytics, or network operation.
- [ ] Normal new/resumed games, win/loss rules, XP, duel behavior, localization,
  onboarding, and the forced-update gate are unchanged.
- [ ] Android and Web debug builds compile; out-of-scope platforms keep their
  existing compile behavior.

## Required automated tests

- Pure gate tests for every combination of debug/profile/release and define
  true/false, proving only debug+true activates.
- Scenario determinism tests that build and reset each named scene twice and
  compare cards, draw pile, blocked slots, selected pair, phase, score inputs,
  language selection, and timer origin.
- Scenario invariant tests proving the clear scene has a valid 11-pair, the
  near-win scene is not already terminal, the victory scene satisfies existing
  win invariants, and the loss scene satisfies existing loss presentation
  inputs.
- Widget/navigation tests proving the entry point is absent when disabled,
  visible/labeled when enabled, loads each scene, exits cleanly, and does not
  leak state into a normal game.
- Ad tests proving normal mode still calls/renders the existing platform ad
  path, active capture mode returns no ad widget, and exiting capture restores
  normal behavior.
- Regression tests for existing game-engine, completed-frame win, update gate,
  and banner-ad platform behavior.
- Run `flutter test` after the focused suite, plus debug Web and Android compile
  checks feasible in the local environment.

## Required manual tests

- Android physical device, ordinary debug launch without the define: verify no
  capture entry point and unchanged ad behavior.
- Android physical device, debug launch with the define: enter every scene,
  record/reset each twice, compare layout/timer start, verify English/Hebrew,
  confirm ads are absent only inside capture mode, then exit and confirm normal
  ads/gameplay return.
- Build or inspect an Android profile and release artifact with the define
  supplied: verify no capture text, route, entry point, or activation behavior
  is reachable. Do not sign or publish from the agent loop.
- Web debug with and without the define: verify gating, deterministic reset,
  responsive capture layout, and no ad-state impact outside capture mode.
- Forced-update regression on Android: verify the gate remains authoritative and
  capture mode cannot bypass it.

## Stop conditions

- Stop for a product decision if additional scenes, frozen animations,
  frame-stepping, viewport locking, recording controls, or profile-build access
  are required.
- Stop if deterministic scenes require changing
  `lib/models/game_model.dart`, weakening its characterization tests, or
  altering production game rules.
- Stop if release exclusion cannot be proven with automated gate tests and an
  artifact/manual check.
- Stop if ad hiding cannot be scoped only to an active capture session.
- Stop if implementation requires a cloud/paid dependency, authentication or
  signing access, remote data, forced-update bypass, or unrelated release work.
- Stop on required test/compile failure rather than bypassing the gate.

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
- Firebase projects/configuration, Firestore data/rules, App Check, Google Play
  Console, ad account/ad unit configuration, and Netlify
- `android/key.properties`, `*.jks`, `*.keystore`, `*.p12`, `*.pfx`,
  `*.mobileprovision`, certificates, provisioning profiles, and signing
  configuration/material
- Version/build numbers, release notes, deployment files, and release branches
