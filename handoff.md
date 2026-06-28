# Session Handoff — Royal Frame MVP

## Goal
Polish Royal Frame's UX: difficulty system, game-over overlays, Easy mode, leaderboard, streak sync, and tutorial replay flow.

---

## Files Actively Being Edited

| File | What changed |
|------|-------------|
| `lib/screens/board_screen.dart` | Win/loss overlay buttons, difficulty switches, Easy mode fill-phase selection, label updates |
| `lib/screens/main_menu_screen.dart` | Leaderboard: added "Most Wins" tab |
| `lib/models/game_model.dart` | Added `easy` enum value, `findEasyAutoPairs`, `autoRemoveFoundPairs`, `toggleSelectForClear` fix |
| `lib/services/streak_service.dart` | Firestore sync with `debugPrint` instrumentation |
| `lib/services/db_service.dart` | `saveStreak()` and `loadStreak()` methods |
| `lib/widgets/rules_dialog.dart` | `onReplayTutorial` callback, debug print removal |
| `lib/widgets/tutorial_overlay.dart` | `_getRect` ancestor bug fix, debug print removal |
| `lib/utils/localization.dart` | `btnReplayTutorial` label update |

---

## TODO List Status

| # | Item | Status |
|---|------|--------|
| 1 | Remove debug prints (tutorial replay, tutorial overlay) | ✅ Fixed |
| 2 | Streak Firestore sync — `saveStreak`/`loadStreak` in `db_service.dart` | ✅ Fixed |
| 3 | Streak sync `debugPrint` instrumentation for testing | ✅ Fixed |
| 4 | Win/loss overlay button hierarchy (primary/secondary/tertiary) | ✅ Fixed |
| 5 | Win/loss overlay button order (Try Again → Change Difficulty → Share Score → Main Menu) | ✅ Fixed |
| 6 | "Try Again" — outlined style with amber semi-transparent fill | ✅ Fixed |
| 7 | "Main Menu" — plain TextButton, no border | ✅ Fixed |
| 8 | Difficulty rename: Hard → Classic, Extreme → Expert | ✅ Fixed |
| 9 | Add Easy difficulty (no kings, fill-phase pair clearing) | ✅ Fixed |
| 10 | Easy mode — correct behavior: manual pair selection during fill phase (not auto-clear) | ✅ Fixed |
| 11 | Easy mode — blue selection highlight during fill phase | ✅ Fixed |
| 12 | Leaderboard: add "Most Wins" tab between High Score and Total Score | ✅ Fixed |
| 13 | Verify streak sync on Android and web with real account | ⏳ Not started |
| 14 | Test tutorial replay end-to-end | ⏳ Not started |
| 15 | Test difficulty picker timing (first-launch: picker before tutorial) | ⏳ Not started |
| 16 | Consider removing `font_awesome_flutter` from pubspec (unused, ~1MB web bundle) | ⏳ Not started |
| 17 | Winner/Game Over overlay layout QA on small phones (5.0") | ⏳ Not started |

---

## What Failed / Dead Ends

### Easy mode auto-clear (item #9 → corrected by #10)
- **First attempt:** After each card placement in fill phase, auto-find and animate all 11-pairs to the clear pile (`_easyAutoRemovePairs`).
- **Root cause:** The design intent was manual clearing, not automatic. Auto-clear was built based on a misread of the spec.
- **Fix:** Removed `_easyAutoRemovePairs` entirely. Tapping an occupied numOrAce cell during fill phase in Easy mode routes to the same `toggleSelectForClear` → `_doClear` flow as the clear phase. Fixed `toggleSelectForClear` in `game_model.dart` to allow selection during fill phase when `difficulty == GameDifficulty.easy`.

### Blue highlight missing in Easy fill phase (item #11)
- **Root cause:** Highlight rendering in `board_screen.dart` (~line 2037) was gated on `game.phase == Phase.clear`. Selection state was being set correctly but never rendered.
- **Fix:** Extended condition to `selected && (game.phase == Phase.clear || (game.phase == Phase.fill && game.difficulty == GameDifficulty.easy))`.

---

## Next Steps

1. **Commit and push** `main_menu_screen.dart` (Most Wins tab) on `ai-playground`, merge to `master`.
2. **Verify streak sync** — hot restart on Android and web with a signed-in account; confirm `[STREAK] load:` prints show correct source; confirm `players/{uid}` in Firestore has `streak` + `streakLastDate`.
3. **Test Easy mode end-to-end** — select Easy, place cards, tap a numOrAce to get blue highlight, tap its pair (sum=11) to clear both; confirm no auto-clearing.
4. **Test Most Wins leaderboard tab** — open leaderboard, confirm Most Wins tab loads and sorts by `wins` field. If it errors in production, check Firebase console for a missing composite index on the `wins` field.
5. **Test tutorial replay** — Rules dialog → "Interactive Tutorial" → overlay appears → complete Phase A → confirm `TutorialManager.complete()` fires → cold launch does not re-trigger tutorial.
6. **Remove `font_awesome_flutter`** from `pubspec.yaml`/`pubspec.lock` if no usage found elsewhere (~1MB web bundle saving).
7. **QA win/loss overlay on small screen** — 5.0" device or emulator; check buttons don't overflow.

---

## Workflow Reminders

- Planning in Claude.ai → code in Claude Code (Windows terminal; `cls` to clear)
- Always specify model + effort before each prompt
- **Hot reload** sufficient for UI/widget changes; **hot restart** required for state/logic/enum changes
- Flutter web infinite loop: close the tab and reopen if it gets stuck
- Branch workflow: work on `ai-playground` → merge to `master` before each release
- Netlify: auto-deploys on push to `master`
- Firestore: new `orderBy: 'wins'` query may need a composite index — if leaderboard tab errors in production, check Firebase console for an index creation prompt
