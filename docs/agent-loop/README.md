# Bounded local agent-review loop

This workflow runs a feature implementation in an isolated Git worktree,
reviews the real uncommitted result with a separate read-only Codex invocation,
and automatically returns structured findings to a fresh worker. It never
commits or integrates the result.

## Architecture

`tool/agent_loop/orchestrator.py` has four layers:

1. **Git/worktree guard** — validates the target branch, creates or reuses its
   registered worktree with `git worktree add`, requires a clean starting
   snapshot, records the starting HEAD, and continuously verifies branch, HEAD,
   specification hash, status snapshot, protected paths, and signing paths.
2. **Codex backend** — invokes the locally installed `codex exec` with the
   saved Codex login. Workers use `workspace-write`; supervisors use
   `read-only`. Both use non-interactive approval policy `never`,
   `--ignore-user-config` (saved authentication is still used), disabled
   workspace network access, core-only shell environment inheritance, JSONL
   events, a final-output JSON Schema, and a per-process timeout.
3. **Review policy** — alternates one fresh worker and one fresh supervisor,
   validates both structured responses locally, passes the complete supervisor
   JSON object to the next worker, detects repeated normalized must-fix strings,
   and enforces every stop condition.
4. **External evidence log** — stores the immutable specification snapshot,
   prompts, command line (without credentials), Codex JSONL events, stderr,
   final JSON, schemas, duration, usage, and run summary outside all tracked
   worktrees.

The worker and supervisor never share a Codex session. That is intentional:
each revision worker receives only the invariant worker contract, the original
specification identity, the current worktree/diff, and the prior supervisor's
structured JSON. Each supervisor starts without worker conversational context
and must inspect Git and captured command events itself.

## Why `codex exec` is used

This workflow was built against the locally installed
`codex-cli 0.146.0-alpha.3.1`. Its own `--help` output confirms support for:

- non-interactive `codex exec`;
- JSONL event output with usage;
- `--output-schema` and `--output-last-message`;
- saved sessions and `codex exec resume`;
- working-directory selection with `-C`/`--cd`;
- `--model` and `-c model_reasoning_effort=...`;
- `read-only` and `workspace-write` sandboxes; and
- explicit approval policies.

The orchestrator checks the flags it actually uses before starting agents. It
does not assume an undocumented command.

The installed `codex review` help exposes useful diff targets but does not
expose the structured-output flags required by this contract, so the supervisor
is a read-only `codex exec` with an explicit review prompt and schema.

The installed non-interactive CLI has no worktree-creation subcommand. Codex
worktree creation is documented as a desktop-app feature, so this local script
uses standard `git worktree add` and then points Codex at the checkout. It never
uses force, reset, stash, merge, push, branch deletion, or deployment commands.

## Provider scope

The current implementation invokes the locally installed Codex CLI only. Claude
Code is not invoked and is not needed for this workflow. A separate provider
adapter may be considered only after the installed Claude CLI has been inspected
for its actual non-interactive, structured-output, permission, and session
capabilities; this repository deliberately does not invent Claude commands or
assume they exist.

## Prerequisites and the immediate human gate

Review the infrastructure diff first. Because this infrastructure task must
remain uncommitted, a human must explicitly approve and commit it on
`codex/agent-loop-infrastructure` before a newly created feature worktree can
contain the orchestrator, prompts, and specifications. Do not create either
feature branch from the uncommitted infrastructure checkout.

Use Python 3, Git, and the installed Codex CLI. No API key, OpenAI API library,
paid service, or third-party orchestration service is required. `codex exec`
reuses the CLI's existing saved login; the script never reads, copies, or logs
authentication files or environment secrets.

Run the infrastructure tests before approval:

```sh
cd /Users/itay/Development/royal-frame-agent-loop-infrastructure
python3 -m unittest -v tool.agent_loop.test_orchestrator
```

## Start the future feature loops

After the reviewed infrastructure commit exists, check out its worktree and run
these exact commands. They use the configured Codex model and explicitly set
supported reasoning effort to `high` for both roles.

### In-app review prompt

```sh
cd /Users/itay/Development/royal-frame-agent-loop-infrastructure
python3 tool/agent_loop/orchestrator.py \
  --spec docs/features/in-app-review-prompt.md \
  --branch codex/in-app-review-prompt \
  --worker-reasoning high \
  --supervisor-reasoning high
```

### Marketing capture mode

```sh
cd /Users/itay/Development/royal-frame-agent-loop-infrastructure
python3 tool/agent_loop/orchestrator.py \
  --spec docs/features/marketing-capture-mode.md \
  --branch codex/marketing-capture-mode \
  --worker-reasoning high \
  --supervisor-reasoning high
```

When a target branch does not exist, the current reviewed infrastructure branch
is the default base. If running from `master`/`main`, the script refuses the
implicit base; pass an explicit reviewed `--base` or return to the
infrastructure worktree. The target branch itself may never be `master` or
`main`.

By default, new worktrees are created under:

```text
<primary-checkout-parent>/royal-frame-worktrees/<branch-slug>
```

An already registered worktree for the target branch is validated and reused
only if it starts clean. An unregistered existing path is never adopted.

## Model and reasoning settings

If `--worker-model` or `--supervisor-model` is omitted, that role uses the
Codex CLI/account default after user configuration is intentionally ignored.
Pin a model only after confirming it is available to the installed CLI:

```sh
python3 tool/agent_loop/orchestrator.py \
  --spec docs/features/in-app-review-prompt.md \
  --branch codex/in-app-review-prompt \
  --worker-model <available-model-id> \
  --supervisor-model <available-model-id> \
  --worker-reasoning high \
  --supervisor-reasoning xhigh
```

Reasoning is passed as the documented
`model_reasoning_effort` configuration override. This installed CLI documents
`minimal`, `low`, `medium`, `high`, and model-dependent `xhigh`.

## Usage bounds

- Hard maximum: four worker/supervisor review cycles.
- Hard invocation maximum: eight Codex invocations (four workers and four
  supervisors).
- Default wall-clock maximum: 1,800 seconds per invocation, configurable with
  `--agent-timeout-seconds`.
- A lower cycle limit may be selected with `--max-cycles 1..4`; a value above
  four is rejected.
- JSONL-reported input/output usage is totaled in `summary.json`.
- `--max-observed-tokens N` adds a best-effort cumulative stop between
  invocations.

The installed CLI does not expose a hard per-invocation token-budget flag.
Therefore `--max-observed-tokens` cannot prevent one already-running invocation
from crossing the threshold; it stops the next invocation. The hard cycle,
invocation, and timeout bounds remain enforced.

## Automatic behavior

The orchestrator automatically:

- creates or validates the isolated target worktree;
- rejects protected target branches and dirty starting worktrees;
- snapshots the original specification and verifies its SHA-256 every cycle;
- runs a writable worker that rereads `AGENTS.md` and the specification;
- captures actual command/test events from the worker's Codex JSONL stream;
- runs a new read-only supervisor that rereads the original specification,
  inspects the actual Git diff/untracked files, and reviews captured test
  evidence;
- validates the worker and supervisor JSON locally;
- forwards only the supervisor JSON to a fresh revision worker;
- stops on PASS, BLOCKED, product decision, failed validation, malformed output,
  protected changes, worktree-integrity changes, repeated must-fix, observed
  usage limit, timeout, or maximum cycles; and
- leaves every feature change uncommitted.

The script compares the worker's `changed_files` report with the complete Git
status paths. It also checks that a read-only supervisor did not change the
worktree. A status change between invocations is treated as unrelated concurrent
work and stops the loop.

## Logs

The default log root is:

```text
${XDG_STATE_HOME:-~/.local/state}/royal-frame/agent-loop/
```

Each run gets a timestamped directory. `--log-root` may select another location,
but the script rejects log roots inside the source checkout or feature
worktree. Logs can contain source diffs, test output, and agent text; treat them
as local development records. The command log contains no auth value, and the
script never reads Codex auth files.

## Human approval boundary

`PASS` means the structured code/test review found no release-blocking automated
issue. It does not commit or assert that physical-device, browser, Internal
Testing, signing, deployment, or release checks happened.

The one required handoff at loop completion is a human review of:

1. the uncommitted feature diff;
2. `summary.json` and relevant worker/supervisor logs;
3. automated test results; and
4. all `manual_validation_required` items.

Only the human may then explicitly choose a commit. Merge, push, deployment,
signing, and release remain separate human-authorized actions; the loop has no
code path for them.

## Stop-state recovery

Do not rerun over a dirty target worktree. Inspect the reported stop, the
uncommitted diff, and external logs. A human can decide whether to edit
manually, discard/recreate the feature worktree using an explicitly approved
Git operation, or revise the original specification on the infrastructure
branch. The orchestrator deliberately provides no reset, stash, cleanup,
branch-deletion, automatic retry, or restart command. Every started run writes
`summary.json` with its terminal status and reason; its JSONL event log records
the cycle and evidence that led to the stop. Setup failures are printed directly
and do not start a loop.
