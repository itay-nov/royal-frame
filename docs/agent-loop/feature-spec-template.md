# Feature: <name>

Status: Draft

Target branch: `codex/<feature-name>`

Specification owner: <human owner>

## Goal

State the user or development outcome in one testable paragraph.

## User-visible behavior

Describe every state a user can see or interact with, including failure,
dismissal, retry, accessibility, and localization behavior.

## Non-goals

- List behavior that must not be added.
- List adjacent refactors or platforms that are out of scope.

## Platform scope

Name each supported platform and explicitly name excluded platforms. Describe
how platform-specific implementations must be isolated.

## Release visibility

State whether the feature is production, staged, debug-only, profile-only, or
otherwise gated. Define release-build behavior for every debug override.

## Architecture constraints

- Identify existing services, state transitions, or adapters that should be
  reused.
- Define persistence ownership and data shape.
- Define dependency and network constraints.
- Identify locked boundaries and compatibility requirements.

## Acceptance criteria

- [ ] Write independently observable, pass/fail criteria.
- [ ] Include success, dismissal, unavailability, and failure behavior.
- [ ] Include persistence, limits, platform isolation, and release gating.

## Required automated tests

- Name the unit, widget, integration, platform, and regression tests required.
- Include negative and failure-path coverage.

## Required manual tests

- Name the device/browser, build mode, setup, action, and expected result.
- Include release-like validation where a platform service requires it.

## Stop conditions

- List missing product decisions, unavailable dependencies, unsafe migrations,
  or architecture conflicts that require the loop to return `BLOCKED`.
- State which failures must not be bypassed.

## Files or systems that must not be modified

- `AGENTS.md`
- `docs/agent-loop/`
- This feature specification
- `tool/agent_loop/`
- Signing keys, keystores, certificates, provisioning profiles, and local
  signing configuration
- Add feature-specific protected files and systems here
