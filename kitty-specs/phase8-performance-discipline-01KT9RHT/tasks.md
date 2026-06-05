# Tasks: Phase 8 Performance Discipline

**Mission**: `phase8-performance-discipline-01KT9RHT`  
**Planning branch**: `main`  
**Merge target**: `main`  
**Generated**: 2026-06-04

## Overview

This task set turns the existing benchmark CLI into a disciplined measurement
surface: stable presets, structured output, allocation visibility, missing
product hot-path metrics, warn-only baselines, and acceptance evidence.

## Subtask Index

| ID | Description | WP | Parallel |
| --- | --- | --- | --- |
| T001 | Add benchmark preset option model | WP01 | No |
| T002 | Add structured benchmark metric schema and JSON output | WP01 | No |
| T003 | Preserve current human-readable benchmark output | WP01 | No |
| T004 | Add explicit allocation measurement helpers | WP02 | No |
| T005 | Attach allocation counts/bytes to benchmark metrics | WP02 | No |
| T006 | Add benchmark output shape tests | WP02 | No |
| T007 | Add point lookup benchmark metric | WP03 | No |
| T008 | Add hybrid filter/vector ranking metric | WP03 | No |
| T009 | Add persistence checkpoint/reopen benchmark smoke | WP03 | No |
| T010 | Preserve and validate Phase 6 concurrency metrics | WP03 | No |
| T011 | Add benchmark methodology docs | WP04 | No |
| T012 | Add warn-only baseline or threshold artifact | WP04 | No |
| T013 | Refresh roadmap performance status | WP04 | No |
| T014 | Add Phase 8 acceptance evidence document | WP05 | No |
| T015 | Run benchmark presets and full validation | WP05 | No |
| T016 | Close integration gaps and update Spec Kitty notes | WP05 | No |

## Work Packages

### WP01 - Benchmark Presets and Structured Output

**Prompt**: `tasks/WP01-benchmark-presets-structured-output.md`  
**Priority**: P0 foundation  
**Requirement Refs**: FR-002, FR-003, FR-008, FR-012  
**Dependencies**: none

- [x] T001 Add benchmark preset option model.
- [x] T002 Add structured benchmark metric schema and JSON output.
- [x] T003 Preserve current human-readable benchmark output.

### WP02 - Allocation Measurement and Output Tests

**Prompt**: `tasks/WP02-allocation-measurement-output-tests.md`  
**Priority**: P0 instrumentation  
**Requirement Refs**: FR-004, FR-009, FR-012  
**Dependencies**: WP01

- [x] T004 Add explicit allocation measurement helpers.
- [x] T005 Attach allocation counts/bytes to benchmark metrics.
- [x] T006 Add benchmark output shape tests.

### WP03 - Missing Workload Metrics

**Prompt**: `tasks/WP03-missing-workload-metrics.md`  
**Priority**: P1 coverage  
**Requirement Refs**: FR-005, FR-006, FR-007, FR-008, FR-009, FR-012  
**Dependencies**: WP01, WP02

- [ ] T007 Add point lookup benchmark metric.
- [ ] T008 Add hybrid filter/vector ranking metric.
- [ ] T009 Add persistence checkpoint/reopen benchmark smoke.
- [ ] T010 Preserve and validate Phase 6 concurrency metrics.

### WP04 - Methodology and Warn-Only Baselines

**Prompt**: `tasks/WP04-methodology-warn-only-baselines.md`  
**Priority**: P1 docs  
**Requirement Refs**: FR-001, FR-010, FR-011, FR-012  
**Dependencies**: WP01, WP02, WP03

- [ ] T011 Add benchmark methodology docs.
- [ ] T012 Add warn-only baseline or threshold artifact.
- [ ] T013 Refresh roadmap performance status.

### WP05 - Phase 8 Acceptance

**Prompt**: `tasks/WP05-phase8-acceptance.md`  
**Priority**: P2 acceptance  
**Requirement Refs**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011, FR-012  
**Dependencies**: WP01, WP02, WP03, WP04

- [ ] T014 Add Phase 8 acceptance evidence document.
- [ ] T015 Run benchmark presets and full validation.
- [ ] T016 Close integration gaps and update Spec Kitty notes.

## Acceptance Handoff

Natural runtime command:

```sh
spec-kitty next --agent codex:gpt-5:implementer-ivan:implementer --mission phase8-performance-discipline-01KT9RHT
```

If protected-main safe commits fail, use the manual commit fallback documented
in `docs/spec-kitty-system-notes.md`.
