# Tasks: ShovelerDB MVP SQL Vector Memory Kernel

**Mission**: `mvp-sql-vector-memory-kernel-01KT1MHB`
**Planning branch**: `main`
**Merge target**: `main`
**Generated**: 2026-06-01

## Overview

This task set hands the whole MVP kernel milestone to Spec Kitty in eight
focused work packages. Each package owns a narrow file surface, maps back to
stable requirements in `spec.md`, and includes a standalone prompt under the
flat `tasks/` directory.

## Subtask Index

| ID | Description | WP | Parallel |
| --- | --- | --- | --- |
| T001 | Add MVP SQL AST types | WP01 | No |
| T002 | Implement parser shell and statement dispatch | WP01 | No |
| T003 | Parse DDL, transaction, and mutation statements | WP01 | No |
| T004 | Parse query/view/procedure/vector expression syntax | WP01 | No |
| T005 | Preserve policy-first rejection tests | WP01 | No |
| T006 | Define scalar/vector value representation | WP02 | Yes |
| T007 | Define column and table metadata | WP02 | Yes |
| T008 | Implement catalog object lifecycle | WP02 | Yes |
| T009 | Add catalog/type diagnostics and tests | WP02 | Yes |
| T010 | Build table row storage primitives | WP03 | No |
| T011 | Add transaction-local mutation tracking | WP03 | No |
| T012 | Implement begin, commit, and rollback visibility | WP03 | No |
| T013 | Add multi-session transaction tests | WP03 | No |
| T014 | Implement SELECT scan/projection/filter/order/limit | WP04 | No |
| T015 | Implement INSERT, UPDATE, and DELETE execution | WP04 | No |
| T016 | Implement simple view registration and execution | WP04 | No |
| T017 | Implement constrained procedure registration and CALL | WP04 | No |
| T018 | Add executor diagnostics and integration tests | WP04 | No |
| T019 | Implement vector distance functions | WP05 | Yes |
| T020 | Implement exact vector search helpers | WP05 | Yes |
| T021 | Add vector validation and ordering tests | WP05 | Yes |
| T022 | Define durable file format and version checks | WP06 | No |
| T023 | Implement atomic snapshot write and reopen | WP06 | No |
| T024 | Add invalid/truncated file recovery tests | WP06 | No |
| T025 | Add embedded database open/close API surface | WP06 | No |
| T026 | Add CLI parse/execute/benchmark command surfaces | WP07 | No |
| T027 | Promote MariaDB-derived native fixtures | WP07 | No |
| T028 | Update reference-test docs and classification workflow | WP07 | No |
| T029 | Add scalar/vector benchmark reporting | WP07 | No |
| T030 | Wire library exports and build/test integration | WP08 | No |
| T031 | Add end-to-end acceptance tests | WP08 | No |
| T032 | Run acceptance commands and fix integration gaps | WP08 | No |
| T033 | Keep Spec Kitty system notes report-ready | WP08 | No |

## Work Packages

### WP01 - Parser, AST, and Policy Boundary

**Prompt**: `tasks/WP01-parser-ast-policy-boundary.md`
**Priority**: P0 foundation
**Requirement Refs**: FR-001, FR-002, FR-017, FR-018, FR-019, FR-020
**Dependencies**: none
**Independent test**: parser/policy unit tests pass for accepted MVP syntax and rejected non-goals.
**Estimated prompt size**: about 230 lines

- [ ] T001 Add MVP SQL AST types (WP01)
- [ ] T002 Implement parser shell and statement dispatch (WP01)
- [ ] T003 Parse DDL, transaction, and mutation statements (WP01)
- [ ] T004 Parse query/view/procedure/vector expression syntax (WP01)
- [ ] T005 Preserve policy-first rejection tests (WP01)

Implementation notes: start from the existing tokenizer and policy modules.
Do not widen SQL acceptance before parser tests lock the new behavior.

### WP02 - Catalog, Types, and Values

**Prompt**: `tasks/WP02-catalog-types-values.md`
**Priority**: P0 foundation
**Requirement Refs**: FR-003, FR-004, FR-005
**Dependencies**: none
**Independent test**: catalog/value unit tests cover table metadata, vector dimensions, and typed diagnostics.
**Estimated prompt size**: about 220 lines

- [ ] T006 Define scalar/vector value representation (WP02)
- [ ] T007 Define column and table metadata (WP02)
- [ ] T008 Implement catalog object lifecycle (WP02)
- [ ] T009 Add catalog/type diagnostics and tests (WP02)

Implementation notes: do not entangle catalog storage with parser internals.
This package should be usable by later executor, transaction, and persistence
packages.

### WP03 - In-Memory Row Store and Transactions

**Prompt**: `tasks/WP03-in-memory-row-store-transactions.md`
**Priority**: P0 foundation
**Requirement Refs**: FR-008, FR-009
**Dependencies**: WP02
**Independent test**: two-session transaction tests prove rollback and commit visibility.
**Estimated prompt size**: about 230 lines

- [ ] T010 Build table row storage primitives (WP03)
- [ ] T011 Add transaction-local mutation tracking (WP03)
- [ ] T012 Implement begin, commit, and rollback visibility (WP03)
- [ ] T013 Add multi-session transaction tests (WP03)

Implementation notes: correctness before concurrency cleverness. Coarse write
serialization is acceptable for MVP if visibility semantics are precise.

### WP04 - SQL Executor, Views, and Procedures

**Prompt**: `tasks/WP04-sql-executor-views-procedures.md`
**Priority**: P1 behavior
**Requirement Refs**: FR-007, FR-021, FR-022
**Dependencies**: WP01, WP02, WP03
**Independent test**: executor tests cover DDL/DML/query/view/procedure happy paths and typed errors.
**Estimated prompt size**: about 280 lines

- [ ] T014 Implement SELECT scan/projection/filter/order/limit (WP04)
- [ ] T015 Implement INSERT, UPDATE, and DELETE execution (WP04)
- [ ] T016 Implement simple view registration and execution (WP04)
- [ ] T017 Implement constrained procedure registration and CALL (WP04)
- [ ] T018 Add executor diagnostics and integration tests (WP04)

Implementation notes: keep procedures constrained. Reject unsupported stored
program syntax clearly instead of building a full MariaDB stored-program VM.

### WP05 - Vector Functions and Exact Search

**Prompt**: `tasks/WP05-vector-functions-search.md`
**Priority**: P1 behavior
**Requirement Refs**: FR-005, FR-006
**Dependencies**: WP02
**Independent test**: vector distance helpers produce exact expected distances and ordering.
**Estimated prompt size**: about 200 lines

- [ ] T019 Implement vector distance functions (WP05)
- [ ] T020 Implement exact vector search helpers (WP05)
- [ ] T021 Add vector validation and ordering tests (WP05)

Implementation notes: exact scan only. ANN indexes are intentionally deferred.

### WP06 - Persistence, Reopen, and Recovery

**Prompt**: `tasks/WP06-persistence-reopen-recovery.md`
**Priority**: P1 durability
**Requirement Refs**: FR-010, FR-011
**Dependencies**: WP02, WP03
**Independent test**: committed state can be written, reopened, queried, and invalid files are rejected.
**Estimated prompt size**: about 230 lines

- [ ] T022 Define durable file format and version checks (WP06)
- [ ] T023 Implement atomic snapshot write and reopen (WP06)
- [ ] T024 Add invalid/truncated file recovery tests (WP06)
- [ ] T025 Add embedded database open/close API surface (WP06)

Implementation notes: use the smallest recoverable format that satisfies the
spec. Version and validate the file format immediately.

### WP07 - Reference Fixtures, CLI, and Benchmarks

**Prompt**: `tasks/WP07-reference-fixtures-cli-benchmarks.md`
**Priority**: P2 validation
**Requirement Refs**: FR-012, FR-013, FR-014, FR-015
**Dependencies**: WP01, WP02, WP03, WP04, WP05, WP06
**Independent test**: CLI smoke commands and benchmark command run locally.
**Estimated prompt size**: about 260 lines

- [ ] T026 Add CLI parse/execute/benchmark command surfaces (WP07)
- [ ] T027 Promote MariaDB-derived native fixtures (WP07)
- [ ] T028 Update reference-test docs and classification workflow (WP07)
- [ ] T029 Add scalar/vector benchmark reporting (WP07)

Implementation notes: keep `references/mariadb/` immutable. Put native adapted
fixtures under `tests/fixtures/mariadb-adapted/`.

### WP08 - Acceptance Hardening and Spec Kitty Notes

**Prompt**: `tasks/WP08-acceptance-hardening-system-notes.md`
**Priority**: P2 acceptance
**Requirement Refs**: FR-011, FR-016
**Dependencies**: WP01, WP02, WP03, WP04, WP05, WP06, WP07
**Independent test**: full acceptance command list passes or failures are documented with focused fixes.
**Estimated prompt size**: about 230 lines

- [ ] T030 Wire library exports and build/test integration (WP08)
- [ ] T031 Add end-to-end acceptance tests (WP08)
- [ ] T032 Run acceptance commands and fix integration gaps (WP08)
- [ ] T033 Keep Spec Kitty system notes report-ready (WP08)

Implementation notes: this is the final integration package. It should not
rewrite earlier components unless required to make the acceptance suite pass.

## Parallelization

Initial parallel candidates:

- WP01 and WP02 can start together.
- WP05 can start after WP02 and before the executor is complete.
- WP03 and WP06 are sequential around transaction/persistence semantics.
- WP07 and WP08 are deliberately late integration packages.

## Acceptance Handoff

After task finalization, the natural next command is:

```
spec-kitty next --agent codex --mission mvp-sql-vector-memory-kernel-01KT1MHB
```

If the runtime reports implementation WPs, use:

```
spec-kitty agent action implement <WPID> --agent codex
```
