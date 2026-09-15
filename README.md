# Royal Frame

Royal Frame is a Flutter card game inspired by classic patience games. Players build a 4x4 royal frame, place face cards in their matching positions, and clear number-card pairs while balancing speed, score, and limited board space.

The project targets Android and the web and includes persistent progression, online leaderboards, and real-time two-player duels backed by Firebase.

## Features

- Single-player game with Easy, Classic, and Expert difficulty modes
- Deterministic game model with scoring, phase transitions, win detection, and undo support
- Real-time 1v1 duels joined through six-character codes
- Anonymous, Google, and phone authentication through Firebase Auth
- Firestore-backed leaderboards with cursor pagination and player ranking
- XP, streaks, daily goals, badges, and cosmetic unlocks
- Interactive tutorial and in-game rules
- Hebrew and English localization
- Sound effects, haptic feedback, score sharing, and animated win/loss overlays
- Firebase App Check and secure local storage
- Android minimum-version enforcement through a remotely hosted manifest
- Android advertising integration

## Technology

| Area | Stack |
|---|---|
| Application | Flutter and Dart |
| Backend | Firebase Authentication and Cloud Firestore |
| Security | Firebase App Check, Firestore Security Rules, secure local storage |
| State and persistence | Testable Dart models, SharedPreferences, FlutterSecureStorage |
| Platform services | Google Sign-In, mobile ads, audio, haptics, sharing |
| Deployment | Android builds and Flutter Web on Netlify |
| Testing | Flutter unit and widget tests |

## Architecture

The game rules are concentrated in `GameModel`, independently of the Flutter UI. Screens coordinate user interaction, while focused services handle authentication, Firestore data, duels, progression systems, haptics, tutorials, and version checks.

The multiplayer flow stores a shared duel document in Firestore. A host creates a code, a guest joins it, both clients receive real-time updates, and transactional writes coordinate final scores and rematches.

## Technical challenges

- Modeling a multi-phase card game with difficulty-specific rules and reversible moves
- Keeping two independent game clients synchronized through Firestore
- Updating player statistics transactionally while supporting paginated leaderboards
- Persisting local progression and synchronizing selected data with authenticated accounts
- Supporting Android and web behavior from one Flutter codebase
- Keeping the full interface usable in both Hebrew RTL and English LTR
- Enforcing minimum supported Android builds without blocking users when the version service is unavailable

## Run locally

Requirements:

- Flutter with a Dart SDK compatible with `^3.9.2`
- An Android emulator/device or a supported web browser
- Access to a Firebase project when testing authentication, leaderboards, or duels

```bash
flutter pub get
flutter run
```

To choose a target explicitly:

```bash
flutter run -d chrome
flutter run -d android
```

Firebase client configuration is included for the original project. A separate deployment should use its own Firebase project and generated configuration.

## Tests

```bash
flutter analyze
flutter test
```

The test suite covers the core game model, completed-frame wins, reusable UI controls, minimum-build enforcement, and the required-update screen.

## Project status

The repository is actively developed and currently reports version `1.1.3+14`. Core gameplay, progression, authentication, leaderboards, and duels are implemented. Remaining device-specific UX checks should be completed before treating every platform flow as production-ready.
