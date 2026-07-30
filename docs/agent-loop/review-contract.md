# Agent-loop review contract

The orchestrator runs one writable worker followed by one new, read-only
supervisor in each review cycle. A cycle ends when the supervisor emits one
structured verdict. Four cycles is the hard maximum.

## Evidence contract

Every supervisor cycle must independently:

1. Read `AGENTS.md`.
2. Read the complete immutable feature specification.
3. Inspect `git status`, the actual tracked diff, and every untracked source
   file in the assigned worktree.
4. Inspect the command/test events captured from the worker's Codex JSONL
   stream. The worker's prose summary is not review evidence.
5. Check correctness, regressions, unnecessary scope, release safety,
   localization, platform isolation, test quality, protected files, and manual
   validation.

The read-only supervisor may inspect files and run read-only Git commands. It
must not edit files. It does not rerun test commands because many test runners
write caches or build artifacts; it reviews the actual command events and
outputs captured during the writable worker run.

## Supervisor output

The final response must be one JSON object with exactly these fields:

```json
{
  "verdict": "PASS | CHANGES_REQUESTED | BLOCKED",
  "must_fix": ["release-blocking finding"],
  "should_fix": ["important non-blocking improvement"],
  "optional": ["truly optional improvement"],
  "tests_required": ["missing or additional automated validation"],
  "manual_validation_required": ["remaining manual validation"],
  "reason": "concise evidence-based rationale"
}
```

All six list fields must be JSON arrays of strings, including when empty.
`reason` must be a non-empty string. Additional fields are rejected.

### `PASS`

Use only when the implementation and automated evidence satisfy the
specification. `must_fix` and `tests_required` must be empty. Manual validation
that can only happen on a device or external release track remains listed in
`manual_validation_required`; PASS never claims that unperformed manual work
was completed.

### `CHANGES_REQUESTED`

Use when the worker can address the findings without a new product decision.
Put every release blocker in `must_fix`. Keep finding wording stable across
cycles so the orchestrator can detect a repeated normalized must-fix.

### `BLOCKED`

Use when safe progress requires a product decision, unavailable external state,
missing access, an unsafe architecture change, or a protected-boundary change.
The loop stops immediately and does not send another worker turn.

## Automatic handoff and stop rules

For a revision cycle, the orchestrator passes the complete supervisor JSON
object—and no worker summary, hidden commentary, or raw supervisor transcript—
to a fresh worker invocation. The worker also receives only the invariant
worker contract, specification path, branch/worktree identity, and baseline
commit.

The loop stops on:

- `PASS`;
- `BLOCKED`;
- a worker-reported product decision;
- a worker or required validation failure;
- malformed structured output;
- a branch, HEAD, specification, protected-file, or worktree-integrity change;
- an unrelated dirty snapshot observed between agent invocations;
- the same normalized `must_fix` string appearing in two reviews; or
- four completed supervisor reviews without PASS.

No stop state performs a commit, merge, push, deployment, release, reset, stash,
force operation, or branch deletion.
