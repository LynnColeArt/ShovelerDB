# Tasks: Phase 6 Scalable Concurrency

**Mission**: `phase6-scalable-concurrency-01KT53SK`
**Planning branch**: `main`
**Merge target**: `main`
**Generated**: 2026-06-02

## Overview

This task set finishes the remaining Phase 6 concurrency model after the first
MVCC correctness slice. It preserves stable reader snapshots and ordered writer
commits while making snapshots cheaper, adding bounded write pressure handling,
coordinating checkpoints, and preparing vector overlay behavior for future index
workers.

## Subtask Index

| ID | Description | WP | Parallel |
| --- | --- | --- | --- |
| T001 | Document concurrency contract and roadmap status | WP01 | No |
| T002 | Add concurrency acceptance/stress harness skeleton | WP01 | No |
| T003 | Define typed concurrency diagnostics | WP01 | No |
| T004 | Introduce committed generation/snapshot handle model | WP02 | No |
| T005 | Replace clone-on-BEGIN reader snapshots with cheap handles | WP02 | No |
| T006 | Prove reader cleanup releases snapshot generations | WP02 | No |
| T007 | Add ordered commit queue structure | WP03 | No |
| T008 | Route writer commits through the queue | WP03 | No |
| T009 | Add bounded queue configuration and backpressure diagnostics | WP03 | No |
| T010 | Preserve rollback semantics under write pressure | WP03 | No |
| T011 | Add checkpoint worker coordination contract | WP04 | No |
| T012 | Prove checkpoints do not mutate active reader generations | WP04 | No |
| T013 | Add vector overlay delta contract | WP04 | No |
| T014 | Prove exact vector scans include committed overlay deltas | WP04 | No |
| T015 | Extend benchmark with Phase 6 concurrency metrics | WP05 | No |
| T016 | Add multi-reader/writer/checkpoint stress tests | WP05 | No |
| T017 | Refresh acceptance evidence and Spec Kitty notes | WP05 | No |
| T018 | Run full validation and close implementation gaps | WP05 | No |

## Work Packages

### WP01 - Concurrency Contract and Harness

**Prompt**: `tasks/WP01-concurrency-contract-harness.md`
**Priority**: P0 foundation
**Requirement Refs**: FR-001, FR-011, FR-013, FR-014
**Dependencies**: none

- [x] T001 Document concurrency contract and roadmap status.
- [x] T002 Add concurrency acceptance/stress harness skeleton.
- [x] T003 Define typed concurrency diagnostics.

### WP02 - Cheap Snapshot Generations

**Prompt**: `tasks/WP02-cheap-snapshot-generations.md`
**Priority**: P0 behavior
**Requirement Refs**: FR-002, FR-003, FR-006, FR-013
**Dependencies**: WP01

- [ ] T004 Introduce committed generation/snapshot handle model.
- [ ] T005 Replace clone-on-BEGIN reader snapshots with cheap handles.
- [ ] T006 Prove reader cleanup releases snapshot generations.

### WP03 - Commit Queue and Backpressure

**Prompt**: `tasks/WP03-commit-queue-backpressure.md`
**Priority**: P0 behavior
**Requirement Refs**: FR-004, FR-005, FR-006, FR-013
**Dependencies**: WP02

- [ ] T007 Add ordered commit queue structure.
- [ ] T008 Route writer commits through the queue.
- [ ] T009 Add bounded queue configuration and backpressure diagnostics.
- [ ] T010 Preserve rollback semantics under write pressure.

### WP04 - Checkpoint and Vector Overlay Coordination

**Prompt**: `tasks/WP04-checkpoint-vector-overlay.md`
**Priority**: P1 coordination
**Requirement Refs**: FR-007, FR-008, FR-009, FR-010, FR-013
**Dependencies**: WP03

- [ ] T011 Add checkpoint worker coordination contract.
- [ ] T012 Prove checkpoints do not mutate active reader generations.
- [ ] T013 Add vector overlay delta contract.
- [ ] T014 Prove exact vector scans include committed overlay deltas.

### WP05 - Stress Benchmarks and Acceptance

**Prompt**: `tasks/WP05-stress-benchmarks-acceptance.md`
**Priority**: P1 acceptance
**Requirement Refs**: FR-011, FR-012, FR-013, FR-014
**Dependencies**: WP03, WP04

- [ ] T015 Extend benchmark with Phase 6 concurrency metrics.
- [ ] T016 Add multi-reader/writer/checkpoint stress tests.
- [ ] T017 Refresh acceptance evidence and Spec Kitty notes.
- [ ] T018 Run full validation and close implementation gaps.

## Acceptance Handoff

Natural runtime command:

```sh
spec-kitty next --agent codex:gpt-5:implementer-ivan:implementer --mission phase6-scalable-concurrency-01KT53SK
```

If protected-main safe commits fail, use the manual commit fallback documented
in `docs/spec-kitty-system-notes.md`.
