from __future__ import annotations

from pathlib import Path
import tempfile
import unittest

from tool.agent_loop.orchestrator import (
    AgentRun,
    LoopError,
    ReviewLoop,
    StatusSnapshot,
    _validate_target_branch,
)


def worker_payload(
    *,
    status: str = "READY_FOR_REVIEW",
    validations: list[dict[str, str]] | None = None,
    reason: str = "Ready for independent review.",
) -> dict:
    return {
        "status": status,
        "changed_files": [],
        "validation_results": validations or [],
        "reason": reason,
    }


def review_payload(
    verdict: str,
    *,
    must_fix: list[str] | None = None,
    tests_required: list[str] | None = None,
    reason: str | None = None,
) -> dict:
    return {
        "verdict": verdict,
        "must_fix": must_fix or [],
        "should_fix": [],
        "optional": [],
        "tests_required": tests_required or [],
        "manual_validation_required": [],
        "reason": reason or verdict,
    }


class FakeWorkspace:
    def __init__(
        self,
        branch: str = "codex/test-feature",
        entries: tuple[str, ...] = (),
    ):
        self.target_branch = branch
        self.worktree = Path("/tmp/fake-feature-worktree")
        self.baseline_head = "a" * 40
        self.entries = entries
        self.integrity_error: str | None = None
        self.protected: tuple[str, ...] = ()

    def snapshot(self) -> StatusSnapshot:
        return StatusSnapshot(self.entries)

    def assert_static_integrity(self) -> None:
        if self.integrity_error:
            raise RuntimeError(self.integrity_error)

    def protected_changes(self, snapshot: StatusSnapshot) -> tuple[str, ...]:
        return self.protected


class FakeBackend:
    def __init__(
        self,
        worker_runs: list[AgentRun],
        supervisor_runs: list[AgentRun],
    ):
        self.worker_runs = list(worker_runs)
        self.supervisor_runs = list(supervisor_runs)
        self.worker_findings: list[dict | None] = []
        self.worker_calls = 0
        self.supervisor_calls = 0

    def run_worker(
        self,
        iteration: int,
        supervisor_findings: dict | None,
    ) -> AgentRun:
        self.worker_calls += 1
        self.worker_findings.append(supervisor_findings)
        return self.worker_runs.pop(0)

    def run_supervisor(self, cycle: int, worker_run: AgentRun) -> AgentRun:
        self.supervisor_calls += 1
        return self.supervisor_runs.pop(0)


def successful_worker(payload: dict | None = None) -> AgentRun:
    return AgentRun(
        returncode=0,
        payload=payload or worker_payload(),
        structured_error=None,
    )


def successful_review(payload: dict) -> AgentRun:
    return AgentRun(
        returncode=0,
        payload=payload,
        structured_error=None,
    )


class ReviewLoopTests(unittest.TestCase):
    def run_loop(
        self,
        workspace: FakeWorkspace,
        backend: FakeBackend,
        *,
        max_cycles: int = 4,
    ):
        with tempfile.TemporaryDirectory() as directory:
            return ReviewLoop(
                workspace=workspace,
                backend=backend,
                log_dir=Path(directory),
                max_cycles=max_cycles,
            ).run()

    def test_pass_on_first_review(self):
        backend = FakeBackend(
            [successful_worker()],
            [successful_review(review_payload("PASS"))],
        )

        result = self.run_loop(FakeWorkspace(), backend)

        self.assertEqual(result.status, "PASS")
        self.assertEqual(result.worker_iterations, 1)
        self.assertEqual(result.review_cycles, 1)
        self.assertEqual(backend.worker_findings, [None])

    def test_one_requested_revision_then_pass(self):
        requested = review_payload(
            "CHANGES_REQUESTED",
            must_fix=["Handle browser launch failure."],
        )
        backend = FakeBackend(
            [successful_worker(), successful_worker()],
            [
                successful_review(requested),
                successful_review(review_payload("PASS")),
            ],
        )

        result = self.run_loop(FakeWorkspace(), backend)

        self.assertEqual(result.status, "PASS")
        self.assertEqual(result.worker_iterations, 2)
        self.assertEqual(result.review_cycles, 2)
        self.assertIsNone(backend.worker_findings[0])
        self.assertEqual(
            backend.worker_findings[1],
            requested,
            "only the structured supervisor findings are handed to revision",
        )

    def test_repeated_identical_failure_stops(self):
        backend = FakeBackend(
            [successful_worker(), successful_worker()],
            [
                successful_review(
                    review_payload(
                        "CHANGES_REQUESTED",
                        must_fix=["Persist dismissal state!"],
                    )
                ),
                successful_review(
                    review_payload(
                        "CHANGES_REQUESTED",
                        must_fix=["persist dismissal state"],
                    )
                ),
            ],
        )

        result = self.run_loop(FakeWorkspace(), backend)

        self.assertEqual(result.status, "REPEATED_MUST_FIX")
        self.assertEqual(result.review_cycles, 2)
        self.assertEqual(result.worker_iterations, 2)

    def test_blocked_verdict_stops_immediately(self):
        backend = FakeBackend(
            [successful_worker()],
            [
                successful_review(
                    review_payload(
                        "BLOCKED",
                        must_fix=["Product owner must select copy."],
                    )
                )
            ],
        )

        result = self.run_loop(FakeWorkspace(), backend)

        self.assertEqual(result.status, "BLOCKED")
        self.assertEqual(backend.worker_calls, 1)
        self.assertEqual(backend.supervisor_calls, 1)

    def test_maximum_cycle_stop(self):
        backend = FakeBackend(
            [successful_worker() for _ in range(4)],
            [
                successful_review(
                    review_payload(
                        "CHANGES_REQUESTED",
                        must_fix=[f"Unique finding {index}"],
                    )
                )
                for index in range(4)
            ],
        )

        result = self.run_loop(FakeWorkspace(), backend)

        self.assertEqual(result.status, "MAX_CYCLES")
        self.assertEqual(result.review_cycles, 4)
        self.assertEqual(result.worker_iterations, 4)

    def test_attempted_execution_on_master_is_rejected(self):
        with self.assertRaisesRegex(LoopError, "protected branch"):
            _validate_target_branch("master")

    def test_unrelated_dirty_files_are_rejected_before_agents(self):
        workspace = FakeWorkspace(entries=(" M lib/unrelated.dart",))
        backend = FakeBackend([], [])

        result = self.run_loop(workspace, backend)

        self.assertEqual(result.status, "DIRTY_WORKTREE")
        self.assertIn("lib/unrelated.dart", result.reason)
        self.assertEqual(backend.worker_calls, 0)
        self.assertEqual(backend.supervisor_calls, 0)

    def test_malformed_supervisor_output_stops(self):
        malformed = {"verdict": "PASS"}
        backend = FakeBackend(
            [successful_worker()],
            [successful_review(malformed)],
        )

        result = self.run_loop(FakeWorkspace(), backend)

        self.assertEqual(result.status, "MALFORMED_SUPERVISOR_OUTPUT")
        self.assertEqual(result.review_cycles, 1)

    def test_worker_process_failure_stops_before_review(self):
        backend = FakeBackend(
            [
                AgentRun(
                    returncode=1,
                    payload=None,
                    structured_error=None,
                    failure_reason="fake worker failed",
                )
            ],
            [],
        )

        result = self.run_loop(FakeWorkspace(), backend)

        self.assertEqual(result.status, "WORKER_FAILED")
        self.assertEqual(backend.supervisor_calls, 0)

    def test_required_test_failure_stops_before_review(self):
        failed_test = {
            "command": "flutter test test/example_test.dart",
            "status": "FAIL",
            "summary": "Expected true, found false.",
        }
        backend = FakeBackend(
            [
                successful_worker(
                    worker_payload(validations=[failed_test])
                )
            ],
            [],
        )

        result = self.run_loop(FakeWorkspace(), backend)

        self.assertEqual(result.status, "TEST_FAILED")
        self.assertIn("flutter test", result.reason)
        self.assertEqual(backend.supervisor_calls, 0)


if __name__ == "__main__":
    unittest.main()
