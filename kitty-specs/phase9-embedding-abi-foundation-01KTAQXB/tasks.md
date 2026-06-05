# Tasks: Phase 9 Embedding ABI Foundation

**Mission**: `phase9-embedding-abi-foundation-01KTAQXB`  
**Planning branch**: `main`  
**Merge target**: `main`  
**Generated**: 2026-06-05

## Overview

This task set turns ShovelerDB from a Zig-only embedded engine into a
connector-ready library by defining and implementing the first stable C ABI
boundary. The work stops at the shared ABI contract and fixture; full language
packages remain follow-up missions.

## Subtask Index

| ID | Description | WP | Parallel |
| --- | --- | --- | --- |
| T001 | Document ABI lifecycle, ownership, diagnostics, vectors, and connector fixture contract | WP01 | No |
| T002 | Add checked-in C header for the first ABI surface | WP01 | No |
| T003 | Refresh roadmap and README to mark Phase 9 ABI foundation active | WP01 | No |
| T004 | Add ABI handle types and open-or-create/close/checkpoint functions | WP02 | No |
| T005 | Bridge ABI SQL execution to the existing executor/persistence surfaces | WP02 | No |
| T006 | Wire ABI modules into the public Zig library surface | WP02 | No |
| T007 | Add result metadata and row/value iteration helpers | WP03 | No |
| T008 | Expose scalar, text/blob, and vector value accessors tied to result lifetime | WP03 | No |
| T009 | Add explicit result/string release behavior and lifecycle tests | WP03 | No |
| T010 | Centralize ABI diagnostic/status code mapping | WP04 | No |
| T011 | Add ABI acceptance smoke for SQL, transactions, vectors, persistence, and typed errors | WP04 | No |
| T012 | Wire ABI integration tests into `zig build test` | WP04 | No |
| T013 | Add shared connector fixture documentation | WP05 | No |
| T014 | Add Phase 9 acceptance evidence document | WP05 | No |
| T015 | Run full validation and record Spec Kitty workflow notes if new anomalies appear | WP05 | No |

## Work Packages

### WP01 - ABI Contract and Roadmap Docs

**Prompt**: `tasks/WP01-abi-contract-roadmap-docs.md`  
**Priority**: P0 contract  
**Requirement Refs**: FR-001, FR-002, FR-009, FR-011  
**Dependencies**: none

- [x] T001 Document ABI lifecycle, ownership, diagnostics, vectors, and connector fixture contract.
- [x] T002 Add checked-in C header for the first ABI surface.
- [x] T003 Refresh roadmap and README to mark Phase 9 ABI foundation active.

### WP02 - Handle Lifecycle and SQL Execution

**Prompt**: `tasks/WP02-handle-lifecycle-sql-execution.md`  
**Priority**: P0 implementation  
**Requirement Refs**: FR-003, FR-004, FR-006, FR-010  
**Dependencies**: WP01

- [ ] T004 Add ABI handle types and open-or-create/close/checkpoint functions.
- [ ] T005 Bridge ABI SQL execution to the existing executor/persistence surfaces.
- [ ] T006 Wire ABI modules into the public Zig library surface.

### WP03 - Result Iteration and Value Access

**Prompt**: `tasks/WP03-result-iteration-value-access.md`  
**Priority**: P1 data access  
**Requirement Refs**: FR-005, FR-006, FR-010  
**Dependencies**: WP01, WP02

- [ ] T007 Add result metadata and row/value iteration helpers.
- [ ] T008 Expose scalar, text/blob, and vector value accessors tied to result lifetime.
- [ ] T009 Add explicit result/string release behavior and lifecycle tests.

### WP04 - Diagnostics and ABI Acceptance Smoke

**Prompt**: `tasks/WP04-diagnostics-abi-acceptance-smoke.md`  
**Priority**: P1 validation  
**Requirement Refs**: FR-007, FR-008, FR-010  
**Dependencies**: WP01, WP02, WP03

- [ ] T010 Centralize ABI diagnostic/status code mapping.
- [ ] T011 Add ABI acceptance smoke for SQL, transactions, vectors, persistence, and typed errors.
- [ ] T012 Wire ABI integration tests into `zig build test`.

### WP05 - Connector Fixture Handoff and Acceptance

**Prompt**: `tasks/WP05-connector-fixture-handoff-acceptance.md`  
**Priority**: P2 acceptance  
**Requirement Refs**: FR-001, FR-008, FR-009, FR-010, FR-011  
**Dependencies**: WP01, WP02, WP03, WP04

- [ ] T013 Add shared connector fixture documentation.
- [ ] T014 Add Phase 9 acceptance evidence document.
- [ ] T015 Run full validation and record Spec Kitty workflow notes if new anomalies appear.

## Acceptance Handoff

Natural runtime command:

```sh
spec-kitty next --agent codex:gpt-5:implementer-ivan:implementer --mission phase9-embedding-abi-foundation-01KTAQXB
```

If protected-main safe commits fail, use the manual commit fallback documented
in `docs/spec-kitty-system-notes.md`.
