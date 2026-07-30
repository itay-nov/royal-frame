# Royal Frame agent guidance

These instructions apply to the entire repository.

## Repository

Royal Frame is a Flutter application. Inspect the existing architecture before
editing. Prefer small, platform-isolated services and widgets over adding more
responsibility to `lib/screens/board_screen.dart`.

`lib/models/game_model.dart` is a locked gameplay-engine boundary. Its
characterization tests describe existing behavior. Do not change that file for
UI, platform integration, release tooling, or capture-mode work. If a feature
appears to require an engine change, stop and request a product/architecture
decision.

## Specifications

Feature work run through `tool/agent_loop/orchestrator.py` is specification
driven. On every worker or supervisor iteration:

1. Read this file.
2. Read the entire selected feature specification.
3. Preserve its non-goals, stop conditions, and protected-file list.
4. Inspect the actual worktree and Git diff rather than relying on summaries.

Do not change a feature specification while implementing that feature.

## Safety boundaries

- Work only in the assigned feature worktree and branch.
- Never commit, merge, rebase, push, deploy, release, delete branches, force a
  Git operation, reset, or stash from an agent loop.
- Never read or print authentication data, signing secrets, keystores, API
  keys, access tokens, or unrelated environment variables.
- Never modify `android/key.properties`, keystores, provisioning profiles,
  certificates, or other signing files.
- Do not weaken the Android forced-update gate.
- Do not add a paid service or an OpenAI API dependency. The local loop uses the
  installed Codex CLI and its saved login.
- Leave all feature changes uncommitted for human review.

## Validation

Run the narrowest relevant tests while iterating, followed by the broader
Flutter tests required by the feature specification. Report the exact commands,
results, and any manual validation still required. Infrastructure-only changes
are validated with:

```sh
python3 -m unittest -v tool.agent_loop.test_orchestrator
```

Treat a failing required test, a needed product decision, an unrelated dirty
tracked file, or a protected-boundary change as a stop condition rather than
working around it.
