# Tasks: MySQL-Style Syntax Completion

**Mission**: `mysql-style-syntax-completion-01KT2G5Z`
**Planning branch**: `main`
**Merge target**: `main`
**Generated**: 2026-06-01

## Overview

This task set completes the SQL syntax gaps left after the MVP kernel mission.
The packages deliberately start with executable function calls because that
unblocks SQL-level vector ranking immediately, then move through query-source
generalization, aggregation, DDL compatibility, procedures, and adapted
MariaDB fixture execution.

## Subtask Index

| ID | Description | WP | Parallel |
| --- | --- | --- | --- |
| T001 | Mark completed roadmap phases and document remaining syntax scope | WP01 | No |
| T002 | Add MTR-lite runner skeleton and unsupported-directive diagnostics | WP01 | No |
| T003 | Add executor support for built-in scalar/vector function calls | WP02 | No |
| T004 | Support vector distance functions in projection, WHERE, and ORDER BY | WP02 | No |
| T005 | Add vector-ranking integration tests and CLI smoke coverage | WP02 | No |
| T006 | Add projection aliases and qualified identifiers to AST/parser | WP03 | No |
| T007 | Add row-source AST for base sources, joins, derived tables, and CTEs | WP03 | No |
| T008 | Add parser tests for MySQL-style query syntax | WP03 | No |
| T009 | Implement row environments and alias resolution | WP04 | No |
| T010 | Execute inner/cross/left joins with ON predicates | WP04 | No |
| T011 | Execute non-recursive CTEs and derived tables | WP04 | No |
| T012 | Expand view execution over richer SELECT sources | WP04 | No |
| T013 | Implement aggregate functions, GROUP BY, and HAVING | WP05 | No |
| T014 | Add grouped-query diagnostics and tests | WP05 | No |
| T015 | Parse and store useful MySQL DDL modifiers | WP06 | No |
| T016 | Implement ordinary index metadata and DDL diagnostics | WP06 | No |
| T017 | Parse procedure parameters and body statements | WP07 | No |
| T018 | Execute DECLARE, SET, IF, bounded WHILE, and SQL body statements | WP07 | No |
| T019 | Classify unsupported stored-program features explicitly | WP07 | No |
| T020 | Promote adapted MariaDB syntax fixtures into executable coverage | WP08 | No |
| T021 | Refresh reference corpus snapshot and fixture docs | WP08 | No |
| T022 | Run full acceptance, update benchmarks, and fix integration gaps | WP09 | No |
| T023 | Keep Spec Kitty system notes current | WP09 | No |

## Work Packages

### WP01 - Roadmap Truth and MTR-Lite Skeleton

**Prompt**: `tasks/WP01-roadmap-mtr-lite-skeleton.md`
**Priority**: P0 foundation
**Requirement Refs**: FR-001, FR-002, FR-017, FR-018, FR-020
**Dependencies**: none

- [x] T001 Mark completed roadmap phases and document remaining syntax scope.
- [x] T002 Add MTR-lite runner skeleton and unsupported-directive diagnostics.

### WP02 - SQL Function Execution and Vector Ranking

**Prompt**: `tasks/WP02-sql-functions-vector-ranking.md`
**Priority**: P0 behavior
**Requirement Refs**: FR-003, FR-004, FR-005, FR-016, FR-019
**Dependencies**: none

- [x] T003 Add executor support for built-in scalar/vector function calls.
- [x] T004 Support vector distance functions in projection, WHERE, and ORDER BY.
- [x] T005 Add vector-ranking integration tests and CLI smoke coverage.

### WP03 - Query Syntax AST Generalization

**Prompt**: `tasks/WP03-query-syntax-ast-generalization.md`
**Priority**: P0 foundation
**Requirement Refs**: FR-006, FR-007, FR-008, FR-010, FR-018
**Dependencies**: WP02

- [x] T006 Add projection aliases and qualified identifiers to AST/parser.
- [x] T007 Add row-source AST for base sources, joins, derived tables, and CTEs.
- [x] T008 Add parser tests for MySQL-style query syntax.

### WP04 - Row-Source Executor

**Prompt**: `tasks/WP04-row-source-executor.md`
**Priority**: P1 behavior
**Requirement Refs**: FR-007, FR-009, FR-010, FR-012, FR-016
**Dependencies**: WP03

- [x] T009 Implement row environments and alias resolution.
- [x] T010 Execute inner/cross/left joins with ON predicates.
- [x] T011 Execute non-recursive CTEs and derived tables.
- [x] T012 Expand view execution over richer SELECT sources.

### WP05 - Aggregates and Grouping

**Prompt**: `tasks/WP05-aggregates-grouping.md`
**Priority**: P1 behavior
**Requirement Refs**: FR-011, FR-016, FR-019
**Dependencies**: WP04

- [x] T013 Implement aggregate functions, GROUP BY, and HAVING.
- [x] T014 Add grouped-query diagnostics and tests.

### WP06 - MySQL DDL Compatibility and Index Metadata

**Prompt**: `tasks/WP06-mysql-ddl-index-metadata.md`
**Priority**: P1 compatibility
**Requirement Refs**: FR-013, FR-018
**Dependencies**: WP03

- [x] T015 Parse and store useful MySQL DDL modifiers.
- [x] T016 Implement ordinary index metadata and DDL diagnostics.

### WP07 - Stored Procedure Control Flow

**Prompt**: `tasks/WP07-stored-procedure-control-flow.md`
**Priority**: P1 behavior
**Requirement Refs**: FR-014, FR-015, FR-016, FR-018
**Dependencies**: WP02, WP04, WP06

- [x] T017 Parse procedure parameters and body statements.
- [x] T018 Execute DECLARE, SET, IF, bounded WHILE, and SQL body statements.
- [x] T019 Classify unsupported stored-program features explicitly.

### WP08 - Adapted MariaDB Fixture Execution

**Prompt**: `tasks/WP08-adapted-mariadb-fixture-execution.md`
**Priority**: P2 validation
**Requirement Refs**: FR-002, FR-017, FR-018
**Dependencies**: WP01, WP02, WP04, WP05, WP06, WP07

- [x] T020 Promote adapted MariaDB syntax fixtures into executable coverage.
- [x] T021 Refresh reference corpus snapshot and fixture docs.

### WP09 - Acceptance Hardening

**Prompt**: `tasks/WP09-acceptance-hardening.md`
**Priority**: P2 acceptance
**Requirement Refs**: FR-016, FR-019, FR-020
**Dependencies**: WP01, WP02, WP03, WP04, WP05, WP06, WP07, WP08

- [x] T022 Run full acceptance, update benchmarks, and fix integration gaps.
- [x] T023 Keep Spec Kitty system notes current.

## Acceptance Handoff

Natural runtime command:

```sh
spec-kitty next --agent codex --mission mysql-style-syntax-completion-01KT2G5Z
```

If protected-branch safe commits fail again, use the documented manual commit
fallback and update `docs/spec-kitty-system-notes.md`.
