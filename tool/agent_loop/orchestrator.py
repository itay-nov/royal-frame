#!/usr/bin/env python3
"""Bounded, local Codex worker/supervisor review loop.

The orchestrator creates or validates a feature worktree, runs a fresh writable
worker and a fresh read-only supervisor per cycle, and leaves all feature
changes uncommitted for a human. It uses only Python's standard library, Git,
and the locally installed Codex CLI.
"""

from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import textwrap
import time
import unicodedata
from typing import Any, Iterable, Protocol, Sequence


MAX_REVIEW_CYCLES = 4
DEFAULT_AGENT_TIMEOUT_SECONDS = 1800
REJECTED_BRANCHES = {"master", "main"}

SPEC_HEADINGS = (
    "Goal",
    "User-visible behavior",
    "Non-goals",
    "Platform scope",
    "Release visibility",
    "Architecture constraints",
    "Acceptance criteria",
    "Required automated tests",
    "Required manual tests",
    "Stop conditions",
    "Files or systems that must not be modified",
)

PROTECTED_PATH_PREFIXES = (
    "AGENTS.md",
    "docs/agent-loop/",
    "docs/features/",
    "tool/agent_loop/",
)

SIGNING_OR_CREDENTIAL_NAMES = {
    "key.properties",
    "google-services.json",
    "googleservice-info.plist",
}

SIGNING_SUFFIXES = {
    ".cer",
    ".der",
    ".entitlements",
    ".jks",
    ".keystore",
    ".mobileprovision",
    ".p12",
    ".pem",
    ".pfx",
}

WORKER_SCHEMA: dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
        "status": {
            "type": "string",
            "enum": [
                "READY_FOR_REVIEW",
                "BLOCKED",
                "PRODUCT_DECISION_REQUIRED",
            ],
        },
        "changed_files": {
            "type": "array",
            "items": {"type": "string"},
        },
        "validation_results": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "command": {"type": "string"},
                    "status": {
                        "type": "string",
                        "enum": ["PASS", "FAIL", "NOT_RUN"],
                    },
                    "summary": {"type": "string"},
                },
                "required": ["command", "status", "summary"],
                "additionalProperties": False,
            },
        },
        "reason": {"type": "string"},
    },
    "required": [
        "status",
        "changed_files",
        "validation_results",
        "reason",
    ],
    "additionalProperties": False,
}

SUPERVISOR_SCHEMA: dict[str, Any] = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
        "verdict": {
            "type": "string",
            "enum": ["PASS", "CHANGES_REQUESTED", "BLOCKED"],
        },
        "must_fix": {"type": "array", "items": {"type": "string"}},
        "should_fix": {"type": "array", "items": {"type": "string"}},
        "optional": {"type": "array", "items": {"type": "string"}},
        "tests_required": {"type": "array", "items": {"type": "string"}},
        "manual_validation_required": {
            "type": "array",
            "items": {"type": "string"},
        },
        "reason": {"type": "string"},
    },
    "required": [
        "verdict",
        "must_fix",
        "should_fix",
        "optional",
        "tests_required",
        "manual_validation_required",
        "reason",
    ],
    "additionalProperties": False,
}


class LoopError(RuntimeError):
    """Base error for a safe loop stop."""


class GitError(LoopError):
    """A fixed, non-destructive Git command failed."""


class IntegrityError(LoopError):
    """The worktree identity or contents changed outside an allowed worker run."""


class StructuredOutputError(LoopError):
    """An agent final response did not satisfy the local contract."""


def _json_dump(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False)


def _sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def _inside(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def _branch_leaf(branch: str) -> str:
    normalized = branch.removeprefix("refs/heads/").removeprefix("origin/")
    return normalized


def _validate_target_branch(branch: str) -> None:
    normalized = _branch_leaf(branch)
    if normalized in REJECTED_BRANCHES:
        raise LoopError(f"refusing to run on protected branch: {branch}")
    if branch != normalized:
        raise LoopError(
            "target branch must be a local short branch name, not a ref or "
            f"remote name: {branch}"
        )


def _validate_spec_text(text: str) -> None:
    missing = [
        heading
        for heading in SPEC_HEADINGS
        if not re.search(
            rf"^##\s+{re.escape(heading)}\s*$",
            text,
            flags=re.MULTILINE,
        )
    ]
    if missing:
        raise LoopError(
            "feature specification is missing required headings: "
            + ", ".join(missing)
        )


def _default_log_root() -> Path:
    configured = os.environ.get("XDG_STATE_HOME")
    state_root = Path(configured).expanduser() if configured else Path.home() / ".local" / "state"
    return state_root / "royal-frame" / "agent-loop"


def _safe_slug(value: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-")
    return slug or "run"


def _is_protected_path(path: str) -> bool:
    normalized = path.replace("\\", "/").lstrip("./")
    lower_name = PurePosixPath(normalized).name.casefold()
    suffix = PurePosixPath(normalized).suffix.casefold()
    if lower_name in SIGNING_OR_CREDENTIAL_NAMES or suffix in SIGNING_SUFFIXES:
        return True
    return any(
        normalized == prefix.rstrip("/") or normalized.startswith(prefix)
        for prefix in PROTECTED_PATH_PREFIXES
    )


@dataclasses.dataclass(frozen=True)
class StatusSnapshot:
    entries: tuple[str, ...]

    @property
    def paths(self) -> tuple[str, ...]:
        return tuple(entry[3:] for entry in self.entries if len(entry) >= 4)

    @property
    def is_clean(self) -> bool:
        return not self.entries


@dataclasses.dataclass(frozen=True)
class AgentRun:
    returncode: int
    payload: dict[str, Any] | None
    structured_error: str | None
    command_evidence: tuple[dict[str, Any], ...] = ()
    usage: dict[str, int] = dataclasses.field(default_factory=dict)
    log_dir: str | None = None
    failure_reason: str | None = None


@dataclasses.dataclass(frozen=True)
class LoopResult:
    status: str
    reason: str
    branch: str
    worktree: str
    log_dir: str
    review_cycles: int
    worker_iterations: int
    total_usage: dict[str, int]
    supervisor_findings: dict[str, Any] | None = None

    @property
    def passed(self) -> bool:
        return self.status == "PASS"


class Workspace(Protocol):
    target_branch: str
    worktree: Path
    baseline_head: str

    def snapshot(self) -> StatusSnapshot: ...

    def assert_static_integrity(self) -> None: ...

    def protected_changes(self, snapshot: StatusSnapshot) -> tuple[str, ...]: ...


class AgentBackend(Protocol):
    def run_worker(
        self,
        iteration: int,
        supervisor_findings: dict[str, Any] | None,
    ) -> AgentRun: ...

    def run_supervisor(
        self,
        cycle: int,
        worker_run: AgentRun,
    ) -> AgentRun: ...


class GitRepository:
    """Fixed, non-destructive Git operations used before agent execution."""

    def __init__(self, repo_root: Path):
        self.repo_root = repo_root.resolve()

    def git(
        self,
        *args: str,
        cwd: Path | None = None,
        check: bool = True,
    ) -> subprocess.CompletedProcess[str]:
        completed = subprocess.run(
            ["git", *args],
            cwd=str((cwd or self.repo_root).resolve()),
            text=True,
            capture_output=True,
            check=False,
        )
        if check and completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip()
            raise GitError(f"git {' '.join(args)} failed: {detail}")
        return completed

    def primary_root(self) -> Path:
        common = self.git(
            "rev-parse",
            "--path-format=absolute",
            "--git-common-dir",
        ).stdout.strip()
        common_path = Path(common)
        if not common_path.is_absolute():
            common_path = self.repo_root / common_path
        return common_path.resolve().parent

    def current_branch(self, cwd: Path | None = None) -> str:
        branch = self.git("branch", "--show-current", cwd=cwd).stdout.strip()
        if not branch:
            raise GitError("detached HEAD is not supported by the agent loop")
        return branch

    def head(self, cwd: Path | None = None) -> str:
        return self.git("rev-parse", "HEAD", cwd=cwd).stdout.strip()

    def branch_exists(self, branch: str) -> bool:
        return (
            self.git(
                "show-ref",
                "--verify",
                "--quiet",
                f"refs/heads/{branch}",
                check=False,
            ).returncode
            == 0
        )

    def worktrees(self) -> dict[str, Path]:
        output = self.git("worktree", "list", "--porcelain").stdout
        result: dict[str, Path] = {}
        current_path: Path | None = None
        for line in output.splitlines():
            if line.startswith("worktree "):
                current_path = Path(line.removeprefix("worktree ")).resolve()
            elif line.startswith("branch refs/heads/") and current_path:
                branch = line.removeprefix("branch refs/heads/")
                result[branch] = current_path
            elif not line:
                current_path = None
        return result

    def validate_branch_name(self, branch: str) -> None:
        result = self.git(
            "check-ref-format",
            "--branch",
            branch,
            check=False,
        )
        if result.returncode != 0:
            raise GitError(f"invalid target branch name: {branch}")

    def prepare_worktree(
        self,
        target_branch: str,
        requested_path: Path | None,
        base_branch: str | None,
    ) -> Path:
        _validate_target_branch(target_branch)
        self.validate_branch_name(target_branch)

        existing = self.worktrees()
        if target_branch in existing:
            worktree = existing[target_branch]
            if requested_path and requested_path.resolve() != worktree:
                raise GitError(
                    f"{target_branch} is already checked out at {worktree}, "
                    f"not {requested_path.resolve()}"
                )
            return worktree

        primary = self.primary_root()
        default_path = (
            primary.parent
            / f"{primary.name}-worktrees"
            / _safe_slug(target_branch)
        )
        worktree = (requested_path or default_path).expanduser().resolve()

        for registered in self.worktrees().values():
            if worktree == registered or _inside(worktree, registered):
                raise GitError(
                    f"new worktree path must be outside registered worktrees: {worktree}"
                )
        if worktree.exists():
            raise GitError(
                f"refusing to reuse an unregistered existing path: {worktree}"
            )

        worktree.parent.mkdir(parents=True, exist_ok=True)
        if self.branch_exists(target_branch):
            self.git("worktree", "add", str(worktree), target_branch)
        else:
            base = base_branch or self.current_branch()
            if _branch_leaf(base) in REJECTED_BRANCHES:
                # A feature branch may be based on master, but the caller must
                # opt in explicitly so an infrastructure checkout cannot
                # silently create feature branches from master.
                if base_branch is None:
                    raise GitError(
                        "current branch is master/main; pass an explicit "
                        "--base branch or run from the reviewed infrastructure branch"
                    )
            self.git(
                "rev-parse",
                "--verify",
                f"{base}^{{commit}}",
            )
            self.git(
                "worktree",
                "add",
                "-b",
                target_branch,
                str(worktree),
                base,
            )
        return worktree


class GitWorkspace:
    def __init__(
        self,
        repository: GitRepository,
        worktree: Path,
        target_branch: str,
        spec_relative_path: Path,
        original_spec_hash: str,
    ):
        self.repository = repository
        self.worktree = worktree.resolve()
        self.target_branch = target_branch
        self.spec_relative_path = spec_relative_path
        self.original_spec_hash = original_spec_hash
        self.baseline_head = repository.head(self.worktree)

    def snapshot(self) -> StatusSnapshot:
        raw = self.repository.git(
            "-c",
            "status.renames=false",
            "status",
            "--porcelain=v1",
            "--untracked-files=all",
            "-z",
            cwd=self.worktree,
        ).stdout
        entries = tuple(sorted(part for part in raw.split("\0") if part))
        return StatusSnapshot(entries)

    def assert_static_integrity(self) -> None:
        branch = self.repository.current_branch(self.worktree)
        if branch != self.target_branch:
            raise IntegrityError(
                f"worktree branch changed from {self.target_branch} to {branch}"
            )
        head = self.repository.head(self.worktree)
        if head != self.baseline_head:
            raise IntegrityError(
                "HEAD changed during the loop; commits and history changes are forbidden"
            )
        spec_path = (self.worktree / self.spec_relative_path).resolve()
        if not spec_path.is_file():
            raise IntegrityError(f"feature specification disappeared: {spec_path}")
        current_hash = _sha256_text(spec_path.read_text(encoding="utf-8"))
        if current_hash != self.original_spec_hash:
            raise IntegrityError("the original feature specification was modified")

    def protected_changes(self, snapshot: StatusSnapshot) -> tuple[str, ...]:
        return tuple(sorted(path for path in snapshot.paths if _is_protected_path(path)))


def _validate_string_list(value: Any, field: str) -> list[str]:
    if not isinstance(value, list) or any(
        not isinstance(item, str) or not item.strip() for item in value
    ):
        raise StructuredOutputError(
            f"{field} must be an array of non-empty strings"
        )
    return value


def validate_worker_payload(payload: Any) -> dict[str, Any]:
    required = {
        "status",
        "changed_files",
        "validation_results",
        "reason",
    }
    if not isinstance(payload, dict) or set(payload) != required:
        raise StructuredOutputError(
            "worker output must contain exactly: " + ", ".join(sorted(required))
        )
    if payload["status"] not in {
        "READY_FOR_REVIEW",
        "BLOCKED",
        "PRODUCT_DECISION_REQUIRED",
    }:
        raise StructuredOutputError(f"unsupported worker status: {payload['status']}")
    _validate_string_list(payload["changed_files"], "changed_files")
    if len(payload["changed_files"]) != len(set(payload["changed_files"])):
        raise StructuredOutputError("changed_files contains duplicates")
    results = payload["validation_results"]
    if not isinstance(results, list):
        raise StructuredOutputError("validation_results must be an array")
    for index, result in enumerate(results):
        if not isinstance(result, dict) or set(result) != {
            "command",
            "status",
            "summary",
        }:
            raise StructuredOutputError(
                f"validation_results[{index}] has invalid fields"
            )
        if result["status"] not in {"PASS", "FAIL", "NOT_RUN"}:
            raise StructuredOutputError(
                f"validation_results[{index}] has invalid status"
            )
        for key in ("command", "summary"):
            if not isinstance(result[key], str) or not result[key].strip():
                raise StructuredOutputError(
                    f"validation_results[{index}].{key} must be non-empty"
                )
    if not isinstance(payload["reason"], str) or not payload["reason"].strip():
        raise StructuredOutputError("worker reason must be non-empty")
    return payload


def validate_supervisor_payload(payload: Any) -> dict[str, Any]:
    required = {
        "verdict",
        "must_fix",
        "should_fix",
        "optional",
        "tests_required",
        "manual_validation_required",
        "reason",
    }
    if not isinstance(payload, dict) or set(payload) != required:
        raise StructuredOutputError(
            "supervisor output must contain exactly: "
            + ", ".join(sorted(required))
        )
    verdict = payload["verdict"]
    if verdict not in {"PASS", "CHANGES_REQUESTED", "BLOCKED"}:
        raise StructuredOutputError(f"unsupported supervisor verdict: {verdict}")
    for field in (
        "must_fix",
        "should_fix",
        "optional",
        "tests_required",
        "manual_validation_required",
    ):
        values = _validate_string_list(payload[field], field)
        if len(values) != len(set(values)):
            raise StructuredOutputError(f"{field} contains duplicates")
    if not isinstance(payload["reason"], str) or not payload["reason"].strip():
        raise StructuredOutputError("supervisor reason must be non-empty")
    if verdict == "PASS" and (
        payload["must_fix"] or payload["tests_required"]
    ):
        raise StructuredOutputError(
            "PASS requires empty must_fix and tests_required arrays"
        )
    if verdict == "CHANGES_REQUESTED" and not (
        payload["must_fix"] or payload["tests_required"]
    ):
        raise StructuredOutputError(
            "CHANGES_REQUESTED requires must_fix or tests_required findings"
        )
    return payload


def _normalized_finding(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value).casefold()
    return " ".join(re.findall(r"\w+", normalized, flags=re.UNICODE))


def _sum_usage(total: dict[str, int], current: dict[str, int]) -> None:
    for key, value in current.items():
        if isinstance(value, int):
            total[key] = total.get(key, 0) + value


class ReviewLoop:
    """Pure loop policy; tests supply fake workspace and agent responses."""

    def __init__(
        self,
        workspace: Workspace,
        backend: AgentBackend,
        log_dir: Path,
        max_cycles: int = MAX_REVIEW_CYCLES,
        max_observed_tokens: int | None = None,
    ):
        if max_cycles < 1 or max_cycles > MAX_REVIEW_CYCLES:
            raise ValueError(
                f"max_cycles must be between 1 and {MAX_REVIEW_CYCLES}"
            )
        self.workspace = workspace
        self.backend = backend
        self.log_dir = log_dir
        self.max_cycles = max_cycles
        self.max_observed_tokens = max_observed_tokens

    def _result(
        self,
        status: str,
        reason: str,
        cycles: int,
        workers: int,
        usage: dict[str, int],
        findings: dict[str, Any] | None = None,
    ) -> LoopResult:
        return LoopResult(
            status=status,
            reason=reason,
            branch=self.workspace.target_branch,
            worktree=str(self.workspace.worktree),
            log_dir=str(self.log_dir),
            review_cycles=cycles,
            worker_iterations=workers,
            total_usage=dict(sorted(usage.items())),
            supervisor_findings=findings,
        )

    def _token_limit_reached(self, usage: dict[str, int]) -> bool:
        if self.max_observed_tokens is None:
            return False
        observed = usage.get("input_tokens", 0) + usage.get("output_tokens", 0)
        return observed >= self.max_observed_tokens

    def run(self) -> LoopResult:
        _validate_target_branch(self.workspace.target_branch)
        total_usage: dict[str, int] = {}
        workers = 0
        reviews = 0
        supervisor_findings: dict[str, Any] | None = None
        seen_must_fix: set[str] = set()

        try:
            self.workspace.assert_static_integrity()
            expected_snapshot = self.workspace.snapshot()
        except IntegrityError as exc:
            return self._result(
                "INTEGRITY_STOP", str(exc), reviews, workers, total_usage
            )

        if not expected_snapshot.is_clean:
            return self._result(
                "DIRTY_WORKTREE",
                "target worktree must start clean; unrelated dirty files: "
                + ", ".join(expected_snapshot.paths),
                reviews,
                workers,
                total_usage,
            )

        for cycle in range(1, self.max_cycles + 1):
            try:
                self.workspace.assert_static_integrity()
                if self.workspace.snapshot() != expected_snapshot:
                    raise IntegrityError(
                        "unrelated worktree changes appeared before the worker run"
                    )
            except IntegrityError as exc:
                return self._result(
                    "INTEGRITY_STOP",
                    str(exc),
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )

            worker_run = self.backend.run_worker(cycle, supervisor_findings)
            workers += 1
            _sum_usage(total_usage, worker_run.usage)
            try:
                self.workspace.assert_static_integrity()
                observed_snapshot = self.workspace.snapshot()
                protected = self.workspace.protected_changes(observed_snapshot)
                if protected:
                    raise IntegrityError(
                        "worker modified protected/signing files: "
                        + ", ".join(protected)
                    )
            except IntegrityError as exc:
                return self._result(
                    "INTEGRITY_STOP",
                    str(exc),
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )
            if worker_run.returncode != 0:
                return self._result(
                    "WORKER_FAILED",
                    worker_run.failure_reason
                    or f"worker process exited {worker_run.returncode}",
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )
            if worker_run.structured_error:
                return self._result(
                    "MALFORMED_WORKER_OUTPUT",
                    worker_run.structured_error,
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )
            try:
                worker_payload = validate_worker_payload(worker_run.payload)
                expected_snapshot = observed_snapshot
            except StructuredOutputError as exc:
                return self._result(
                    "MALFORMED_WORKER_OUTPUT",
                    str(exc),
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )

            actual_paths = set(expected_snapshot.paths)
            reported_paths = set(worker_payload["changed_files"])
            if actual_paths != reported_paths:
                return self._result(
                    "WORKER_REPORT_MISMATCH",
                    "worker changed_files does not match git status; actual="
                    + repr(sorted(actual_paths))
                    + ", reported="
                    + repr(sorted(reported_paths)),
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )

            if worker_payload["status"] == "PRODUCT_DECISION_REQUIRED":
                return self._result(
                    "PRODUCT_DECISION_REQUIRED",
                    worker_payload["reason"],
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )
            if worker_payload["status"] == "BLOCKED":
                return self._result(
                    "BLOCKED",
                    worker_payload["reason"],
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )
            failed_validation = [
                item
                for item in worker_payload["validation_results"]
                if item["status"] == "FAIL"
            ]
            if failed_validation:
                return self._result(
                    "TEST_FAILED",
                    "worker reported failed validation: "
                    + "; ".join(
                        f"{item['command']}: {item['summary']}"
                        for item in failed_validation
                    ),
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )
            if self._token_limit_reached(total_usage):
                return self._result(
                    "USAGE_LIMIT",
                    "observed Codex token limit reached after worker run",
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )

            supervisor_run = self.backend.run_supervisor(cycle, worker_run)
            reviews += 1
            _sum_usage(total_usage, supervisor_run.usage)
            try:
                self.workspace.assert_static_integrity()
                if self.workspace.snapshot() != expected_snapshot:
                    raise IntegrityError(
                        "read-only supervisor or another process changed the worktree"
                    )
            except IntegrityError as exc:
                return self._result(
                    "INTEGRITY_STOP",
                    str(exc),
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )
            if supervisor_run.returncode != 0:
                return self._result(
                    "SUPERVISOR_FAILED",
                    supervisor_run.failure_reason
                    or f"supervisor process exited {supervisor_run.returncode}",
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )
            if supervisor_run.structured_error:
                return self._result(
                    "MALFORMED_SUPERVISOR_OUTPUT",
                    supervisor_run.structured_error,
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )
            try:
                review = validate_supervisor_payload(supervisor_run.payload)
            except StructuredOutputError as exc:
                return self._result(
                    "MALFORMED_SUPERVISOR_OUTPUT",
                    str(exc),
                    reviews,
                    workers,
                    total_usage,
                    supervisor_findings,
                )

            supervisor_findings = review
            verdict = review["verdict"]
            if verdict == "PASS":
                return self._result(
                    "PASS",
                    review["reason"],
                    reviews,
                    workers,
                    total_usage,
                    review,
                )
            if verdict == "BLOCKED":
                return self._result(
                    "BLOCKED",
                    review["reason"],
                    reviews,
                    workers,
                    total_usage,
                    review,
                )

            current_must_fix = {
                _normalized_finding(finding) for finding in review["must_fix"]
            }
            repeated = sorted(
                value for value in current_must_fix if value in seen_must_fix
            )
            if repeated:
                return self._result(
                    "REPEATED_MUST_FIX",
                    "a normalized must-fix finding appeared in two reviews: "
                    + "; ".join(repeated),
                    reviews,
                    workers,
                    total_usage,
                    review,
                )
            seen_must_fix.update(current_must_fix)

            if self._token_limit_reached(total_usage):
                return self._result(
                    "USAGE_LIMIT",
                    "observed Codex token limit reached after supervisor run",
                    reviews,
                    workers,
                    total_usage,
                    review,
                )
            if cycle == self.max_cycles:
                return self._result(
                    "MAX_CYCLES",
                    f"stopped after {self.max_cycles} review cycles without PASS",
                    reviews,
                    workers,
                    total_usage,
                    review,
                )

        raise AssertionError("review loop exhausted without a terminal result")


def _event_usage_and_commands(
    stdout: str,
) -> tuple[dict[str, int], tuple[dict[str, Any], ...]]:
    usage: dict[str, int] = {}
    commands: list[dict[str, Any]] = []
    for line in stdout.splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get("type") == "turn.completed" and isinstance(
            event.get("usage"), dict
        ):
            _sum_usage(usage, event["usage"])
        item = event.get("item")
        if not isinstance(item, dict) or item.get("type") not in {
            "command_execution",
            "commandExecution",
        }:
            continue
        if event.get("type") not in {"item.completed", "item.failed"}:
            continue
        keep = {
            key: item[key]
            for key in (
                "id",
                "type",
                "command",
                "status",
                "exit_code",
                "aggregated_output",
                "output",
            )
            if key in item
        }
        keep["event_type"] = event.get("type")
        commands.append(keep)
    return usage, tuple(commands)


class CodexBackend:
    def __init__(
        self,
        codex_binary: str,
        workspace: GitWorkspace,
        spec_path: Path,
        spec_hash: str,
        run_log_dir: Path,
        worker_prompt: str,
        supervisor_prompt: str,
        worker_model: str | None,
        supervisor_model: str | None,
        worker_reasoning: str | None,
        supervisor_reasoning: str | None,
        timeout_seconds: int,
    ):
        self.codex_binary = codex_binary
        self.workspace = workspace
        self.spec_path = spec_path
        self.spec_hash = spec_hash
        self.run_log_dir = run_log_dir
        self.worker_prompt = worker_prompt
        self.supervisor_prompt = supervisor_prompt
        self.worker_model = worker_model
        self.supervisor_model = supervisor_model
        self.worker_reasoning = worker_reasoning
        self.supervisor_reasoning = supervisor_reasoning
        self.timeout_seconds = timeout_seconds

        schema_dir = run_log_dir / "schemas"
        schema_dir.mkdir(parents=True, exist_ok=True)
        self.worker_schema_path = schema_dir / "worker.schema.json"
        self.supervisor_schema_path = schema_dir / "supervisor.schema.json"
        self.worker_schema_path.write_text(
            _json_dump(WORKER_SCHEMA) + "\n",
            encoding="utf-8",
        )
        self.supervisor_schema_path.write_text(
            _json_dump(SUPERVISOR_SCHEMA) + "\n",
            encoding="utf-8",
        )

    def preflight(self) -> str:
        root_help = subprocess.run(
            [self.codex_binary, "--help"],
            text=True,
            capture_output=True,
            check=False,
        )
        exec_help = subprocess.run(
            [self.codex_binary, "exec", "--help"],
            text=True,
            capture_output=True,
            check=False,
        )
        if root_help.returncode != 0 or exec_help.returncode != 0:
            raise LoopError("unable to inspect installed Codex CLI help")
        root_required = (
            "--ask-for-approval",
            "--sandbox",
            "--cd",
            "--model",
        )
        exec_required = (
            "--json",
            "--ignore-user-config",
            "--output-schema",
            "--output-last-message",
        )
        missing = [
            flag
            for flag in root_required
            if flag not in root_help.stdout
        ] + [
            flag
            for flag in exec_required
            if flag not in exec_help.stdout
        ]
        if missing:
            raise LoopError(
                "installed Codex CLI lacks required flags: " + ", ".join(missing)
            )
        version = subprocess.run(
            [self.codex_binary, "--version"],
            text=True,
            capture_output=True,
            check=False,
        )
        if version.returncode != 0:
            raise LoopError("unable to read installed Codex CLI version")
        version_text = version.stdout.strip()
        (self.run_log_dir / "codex-version.txt").write_text(
            version_text + "\n",
            encoding="utf-8",
        )
        return version_text

    def _command(
        self,
        sandbox: str,
        schema_path: Path,
        output_path: Path,
        model: str | None,
        reasoning: str | None,
    ) -> list[str]:
        command = [
            self.codex_binary,
            "--ask-for-approval",
            "never",
            "--sandbox",
            sandbox,
            "--cd",
            str(self.workspace.worktree),
            "--config",
            'shell_environment_policy.inherit="core"',
            "--config",
            "allow_login_shell=false",
            "--config",
            "sandbox_workspace_write.network_access=false",
        ]
        if model:
            command.extend(["--model", model])
        if reasoning:
            command.extend(
                ["--config", f'model_reasoning_effort="{reasoning}"']
            )
        command.extend(
            [
                "exec",
                "--json",
                "--ignore-user-config",
                "--output-schema",
                str(schema_path),
                "--output-last-message",
                str(output_path),
                "-",
            ]
        )
        return command

    def _run(
        self,
        role: str,
        number: int,
        prompt: str,
        sandbox: str,
        schema_path: Path,
        model: str | None,
        reasoning: str | None,
    ) -> AgentRun:
        invocation_dir = self.run_log_dir / f"{role}-{number:02d}"
        invocation_dir.mkdir(parents=True, exist_ok=False)
        prompt_path = invocation_dir / "prompt.md"
        stdout_path = invocation_dir / "events.jsonl"
        stderr_path = invocation_dir / "stderr.txt"
        output_path = invocation_dir / "final.json"
        command_path = invocation_dir / "command.json"
        prompt_path.write_text(prompt, encoding="utf-8")

        command = self._command(
            sandbox,
            schema_path,
            output_path,
            model,
            reasoning,
        )
        command_path.write_text(
            _json_dump(command) + "\n",
            encoding="utf-8",
        )
        started = time.monotonic()
        try:
            completed = subprocess.run(
                command,
                input=prompt,
                text=True,
                capture_output=True,
                check=False,
                timeout=self.timeout_seconds,
            )
            stdout = completed.stdout
            stderr = completed.stderr
            returncode = completed.returncode
            failure_reason = None
        except subprocess.TimeoutExpired as exc:
            stdout = exc.stdout or ""
            stderr = exc.stderr or ""
            if isinstance(stdout, bytes):
                stdout = stdout.decode("utf-8", errors="replace")
            if isinstance(stderr, bytes):
                stderr = stderr.decode("utf-8", errors="replace")
            returncode = 124
            failure_reason = (
                f"{role} exceeded {self.timeout_seconds} seconds"
            )
        stdout_path.write_text(stdout, encoding="utf-8")
        stderr_path.write_text(stderr, encoding="utf-8")
        (invocation_dir / "duration-seconds.txt").write_text(
            f"{time.monotonic() - started:.3f}\n",
            encoding="utf-8",
        )

        usage, commands = _event_usage_and_commands(stdout)
        payload: dict[str, Any] | None = None
        structured_error: str | None = None
        if returncode == 0:
            if not output_path.is_file():
                structured_error = "Codex did not write the structured final output"
            else:
                try:
                    raw = json.loads(output_path.read_text(encoding="utf-8"))
                    if not isinstance(raw, dict):
                        raise ValueError("final JSON is not an object")
                    payload = raw
                except (OSError, json.JSONDecodeError, ValueError) as exc:
                    structured_error = f"could not parse structured final output: {exc}"

        return AgentRun(
            returncode=returncode,
            payload=payload,
            structured_error=structured_error,
            command_evidence=commands,
            usage=usage,
            log_dir=str(invocation_dir),
            failure_reason=failure_reason,
        )

    def run_worker(
        self,
        iteration: int,
        supervisor_findings: dict[str, Any] | None,
    ) -> AgentRun:
        feedback = (
            _json_dump(supervisor_findings)
            if supervisor_findings is not None
            else "null (initial implementation iteration)"
        )
        prompt = (
            self.worker_prompt
            + "\n\n"
            + textwrap.dedent(
                f"""
                # Runtime context

                - Assigned worktree: `{self.workspace.worktree}`
                - Required branch: `{self.workspace.target_branch}`
                - Immutable baseline commit: `{self.workspace.baseline_head}`
                - Original specification: `{self.spec_path}`
                - Specification SHA-256: `{self.spec_hash}`
                - Worker iteration: `{iteration}` of at most `{MAX_REVIEW_CYCLES}`

                ## Supervisor findings from the preceding review

                ```json
                {feedback}
                ```

                The JSON above is the only review feedback for this iteration.
                Read the original specification in full even when findings are
                supplied.
                """
            )
        )
        return self._run(
            "worker",
            iteration,
            prompt,
            "workspace-write",
            self.worker_schema_path,
            self.worker_model,
            self.worker_reasoning,
        )

    def run_supervisor(
        self,
        cycle: int,
        worker_run: AgentRun,
    ) -> AgentRun:
        evidence = _json_dump(list(worker_run.command_evidence))
        if len(evidence) > 120_000:
            evidence = (
                evidence[:120_000]
                + "\n... inline evidence truncated; inspect the complete JSONL log path above ..."
            )
        prompt = (
            self.supervisor_prompt
            + "\n\n"
            + textwrap.dedent(
                f"""
                # Runtime context

                - Assigned worktree: `{self.workspace.worktree}`
                - Required branch: `{self.workspace.target_branch}`
                - Immutable baseline commit: `{self.workspace.baseline_head}`
                - Original specification: `{self.spec_path}`
                - Specification SHA-256: `{self.spec_hash}`
                - Review cycle: `{cycle}` of at most `{MAX_REVIEW_CYCLES}`
                - Complete worker JSONL log:
                  `{Path(worker_run.log_dir or "") / "events.jsonl"}`

                ## Captured worker command and test evidence

                This is extracted directly from Codex command-completion events,
                not from the worker's final summary:

                ```json
                {evidence}
                ```

                Inspect the actual Git status, diff, and untracked source files
                yourself before deciding the verdict.
                """
            )
        )
        return self._run(
            "supervisor",
            cycle,
            prompt,
            "read-only",
            self.supervisor_schema_path,
            self.supervisor_model,
            self.supervisor_reasoning,
        )


def _resolve_repo_root(start: Path) -> Path:
    completed = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=str(start.resolve()),
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        raise LoopError("orchestrator must be run from inside a Git repository")
    return Path(completed.stdout.strip()).resolve()


def _resolve_spec(repo_root: Path, supplied: str) -> tuple[Path, Path, str]:
    candidate = Path(supplied).expanduser()
    source_path = (
        candidate.resolve()
        if candidate.is_absolute()
        else (repo_root / candidate).resolve()
    )
    if not _inside(source_path, repo_root):
        raise LoopError("feature specification must be inside the source repository")
    if not source_path.is_file():
        raise LoopError(f"feature specification does not exist: {source_path}")
    relative = source_path.relative_to(repo_root)
    text = source_path.read_text(encoding="utf-8")
    _validate_spec_text(text)
    return source_path, relative, text


def _create_run_log_dir(
    log_root: Path,
    repo_root: Path,
    worktree: Path,
    branch: str,
) -> Path:
    root = log_root.expanduser().resolve()
    if _inside(root, repo_root) or _inside(root, worktree):
        raise LoopError("log root must be outside tracked repository worktrees")
    root.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = root / f"{stamp}-{os.getpid()}-{_safe_slug(branch)}"
    run_dir.mkdir(parents=False, exist_ok=False)
    return run_dir


def _write_summary(run_dir: Path, result: LoopResult) -> None:
    (run_dir / "summary.json").write_text(
        _json_dump(dataclasses.asdict(result)) + "\n",
        encoding="utf-8",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Run a bounded local Codex worker/read-only-supervisor loop in an "
            "isolated Git worktree."
        )
    )
    parser.add_argument("--spec", required=True, help="repository-relative feature specification")
    parser.add_argument("--branch", required=True, help="target local feature branch")
    parser.add_argument(
        "--base",
        help=(
            "base commit/branch when creating the target branch; defaults to "
            "the current non-master branch"
        ),
    )
    parser.add_argument(
        "--worktree",
        type=Path,
        help="explicit isolated worktree path; defaults beside the primary checkout",
    )
    parser.add_argument(
        "--log-root",
        type=Path,
        default=_default_log_root(),
        help="persistent log root outside the repository",
    )
    parser.add_argument(
        "--codex-binary",
        default="codex",
        help="installed Codex CLI executable name/path",
    )
    parser.add_argument("--worker-model", help="Codex model override for workers")
    parser.add_argument("--supervisor-model", help="Codex model override for supervisors")
    reasoning_choices = ("minimal", "low", "medium", "high", "xhigh")
    parser.add_argument(
        "--worker-reasoning",
        choices=reasoning_choices,
        help="model_reasoning_effort override for workers",
    )
    parser.add_argument(
        "--supervisor-reasoning",
        choices=reasoning_choices,
        help="model_reasoning_effort override for supervisors",
    )
    parser.add_argument(
        "--max-cycles",
        type=int,
        choices=range(1, MAX_REVIEW_CYCLES + 1),
        default=MAX_REVIEW_CYCLES,
        help=f"review-cycle bound (1-{MAX_REVIEW_CYCLES})",
    )
    parser.add_argument(
        "--agent-timeout-seconds",
        type=int,
        default=DEFAULT_AGENT_TIMEOUT_SECONDS,
        help="wall-clock limit for each worker or supervisor invocation",
    )
    parser.add_argument(
        "--max-observed-tokens",
        type=int,
        help=(
            "optional best-effort cumulative input+output token stop checked "
            "between invocations; not a hard per-invocation token ceiling"
        ),
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        _validate_target_branch(args.branch)
        if args.agent_timeout_seconds < 1:
            raise LoopError("--agent-timeout-seconds must be positive")
        if args.max_observed_tokens is not None and args.max_observed_tokens < 1:
            raise LoopError("--max-observed-tokens must be positive")

        repo_root = _resolve_repo_root(Path.cwd())
        source_spec, spec_relative, spec_text = _resolve_spec(repo_root, args.spec)
        spec_hash = _sha256_text(spec_text)

        repository = GitRepository(repo_root)
        worktree = repository.prepare_worktree(
            args.branch,
            args.worktree,
            args.base,
        )
        target_spec = (worktree / spec_relative).resolve()
        if not target_spec.is_file():
            raise LoopError(
                "target branch does not contain the selected specification; "
                "base it on the reviewed infrastructure branch"
            )
        target_text = target_spec.read_text(encoding="utf-8")
        if _sha256_text(target_text) != spec_hash:
            raise LoopError(
                "target worktree specification differs from the original source"
            )

        run_dir = _create_run_log_dir(
            args.log_root,
            repo_root,
            worktree,
            args.branch,
        )
        (run_dir / "original-specification.md").write_text(
            spec_text,
            encoding="utf-8",
        )
        (run_dir / "run-context.json").write_text(
            _json_dump(
                {
                    "source_repository": str(repo_root),
                    "source_specification": str(source_spec),
                    "target_branch": args.branch,
                    "target_worktree": str(worktree),
                    "base": args.base,
                    "specification_sha256": spec_hash,
                    "max_cycles": args.max_cycles,
                    "agent_timeout_seconds": args.agent_timeout_seconds,
                    "max_observed_tokens": args.max_observed_tokens,
                    "worker_model": args.worker_model,
                    "supervisor_model": args.supervisor_model,
                    "worker_reasoning": args.worker_reasoning,
                    "supervisor_reasoning": args.supervisor_reasoning,
                }
            )
            + "\n",
            encoding="utf-8",
        )

        workspace = GitWorkspace(
            repository,
            worktree,
            args.branch,
            spec_relative,
            spec_hash,
        )
        prompt_root = Path(__file__).resolve().parent
        worker_prompt = (prompt_root / "worker_prompt.md").read_text(
            encoding="utf-8"
        )
        supervisor_prompt = (prompt_root / "supervisor_prompt.md").read_text(
            encoding="utf-8"
        )

        codex_binary = shutil.which(args.codex_binary)
        if codex_binary is None:
            raise LoopError(f"Codex CLI not found: {args.codex_binary}")
        backend = CodexBackend(
            codex_binary=codex_binary,
            workspace=workspace,
            spec_path=target_spec,
            spec_hash=spec_hash,
            run_log_dir=run_dir,
            worker_prompt=worker_prompt,
            supervisor_prompt=supervisor_prompt,
            worker_model=args.worker_model,
            supervisor_model=args.supervisor_model,
            worker_reasoning=args.worker_reasoning,
            supervisor_reasoning=args.supervisor_reasoning,
            timeout_seconds=args.agent_timeout_seconds,
        )
        backend.preflight()

        result = ReviewLoop(
            workspace=workspace,
            backend=backend,
            log_dir=run_dir,
            max_cycles=args.max_cycles,
            max_observed_tokens=args.max_observed_tokens,
        ).run()
        _write_summary(run_dir, result)
        print(_json_dump(dataclasses.asdict(result)))
        return 0 if result.passed else 2
    except (LoopError, OSError) as exc:
        error = {"status": "SETUP_FAILED", "reason": str(exc)}
        print(_json_dump(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
