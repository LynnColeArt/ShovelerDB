# Tasks: Agent Concurrency MVCC

**Mission**: `agent-concurrency-mvcc-01KT499P`
**Planning branch**: `main`
**Merge target**: `main`
**Generated**: 2026-06-02

## Overview

This task set backfills the formal Spec Kitty task surface for the already
landed MVCC concurrency slice. The implementation landed directly on `main` as
`865eb05 feat: Add first MVCC concurrency slice`; these tasks make the runtime
state machine represent that work instead of leaving the mission at
`not_started`.

## Subtask Index

| ID | Description | WP | Parallel |
| --- | --- | --- | --- |
| T001 | Create mission spec, plan, and acceptance scope | WP01 | No |
| T002 | Add session snapshot ownership and visibility routing | WP01 | No |
| T003 | Add serialized commit sequence tracking | WP01 | No |
| T004 | Handle overlapping writer internal row-id collisions | WP01 | No |
| T005 | Add stable reader and ordered writer tests | WP01 | No |
| T006 | Add benchmark metric for interleaved snapshot reads/writes | WP01 | No |
| T007 | Update project roadmap and acceptance notes | WP01 | No |
| T008 | Run `zig build test` and benchmark smoke | WP01 | No |

## Work Packages

### WP01 - MVCC Semantics Foundation

**Prompt**: `tasks/WP01-mvcc-semantics-foundation.md`
**Priority**: P0 foundation
**Requirement Refs**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008
**Dependencies**: none

- [x] T001 Create mission spec, plan, and acceptance scope.
- [x] T002 Add session snapshot ownership and visibility routing.
- [x] T003 Add serialized commit sequence tracking.
- [x] T004 Handle overlapping writer internal row-id collisions.
- [x] T005 Add stable reader and ordered writer tests.
- [x] T006 Add benchmark metric for interleaved snapshot reads/writes.
- [x] T007 Update project roadmap and acceptance notes.
- [x] T008 Run `zig build test` and benchmark smoke.

## Acceptance Handoff

Natural runtime command:

```sh
spec-kitty next --agent codex:gpt-5:implementer-ivan:implementer --mission agent-concurrency-mvcc-01KT499P
```

This mission used the protected-main manual landing pattern. Runtime task state
should therefore be treated as backfilled evidence for landed commit `865eb05`,
not as a separate pending implementation lane.
