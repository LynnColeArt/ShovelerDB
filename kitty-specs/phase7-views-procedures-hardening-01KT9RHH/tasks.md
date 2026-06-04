# Tasks: Phase 7 Views and Procedures Hardening

**Mission**: `phase7-views-procedures-hardening-01KT9RHH`  
**Planning branch**: `main`  
**Merge target**: `main`  
**Generated**: 2026-06-04

## Overview

This task set hardens ShovelerDB views and procedures after the syntax
completion mission. The packages prioritize view correctness, persistence, and
procedure transaction behavior, then close with adapted fixtures and acceptance
evidence.

## Subtask Index

| ID | Description | WP | Parallel |
| --- | --- | --- | --- |
| T001 | Harden rich view expansion through the row-source executor | WP01 | No |
| T002 | Add view result metadata and lifecycle diagnostics | WP01 | No |
| T003 | Add view lifecycle integration coverage | WP01 | No |
| T004 | Prove persisted snapshots reopen executable views | WP02 | No |
| T005 | Promote richer view adapted fixture coverage | WP02 | No |
| T006 | Refresh view-related reference notes | WP02 | No |
| T007 | Harden procedure CALL argument binding | WP03 | No |
| T008 | Prove procedure writes share caller transaction semantics | WP03 | No |
| T009 | Add procedure rollback/commit integration coverage | WP03 | No |
| T010 | Harden procedure body diagnostics and loop guard behavior | WP04 | No |
| T011 | Preserve unsupported stored-program rejection coverage | WP04 | No |
| T012 | Prove no partial catalog mutation for rejected procedure bodies | WP04 | No |
| T013 | Update Phase 7 roadmap and dialect docs | WP05 | No |
| T014 | Add Phase 7 acceptance evidence document | WP05 | No |
| T015 | Run full validation and close integration gaps | WP05 | No |

## Work Packages

### WP01 - View Expansion and Lifecycle Diagnostics

**Prompt**: `tasks/WP01-view-expansion-lifecycle.md`  
**Priority**: P0 behavior  
**Requirement Refs**: FR-001, FR-002, FR-003, FR-011, FR-012  
**Dependencies**: none

- [x] T001 Harden rich view expansion through the row-source executor.
- [x] T002 Add view result metadata and lifecycle diagnostics.
- [x] T003 Add view lifecycle integration coverage.

### WP02 - View Persistence and Fixture Coverage

**Prompt**: `tasks/WP02-view-persistence-fixtures.md`  
**Priority**: P1 validation  
**Requirement Refs**: FR-001, FR-004, FR-009, FR-010, FR-011, FR-012  
**Dependencies**: WP01

- [x] T004 Prove persisted snapshots reopen executable views.
- [x] T005 Promote richer view adapted fixture coverage.
- [x] T006 Refresh view-related reference notes.

### WP03 - Procedure Call and Transaction Semantics

**Prompt**: `tasks/WP03-procedure-call-transactions.md`  
**Priority**: P0 behavior  
**Requirement Refs**: FR-005, FR-006, FR-007, FR-011, FR-012  
**Dependencies**: none

- [ ] T007 Harden procedure CALL argument binding.
- [ ] T008 Prove procedure writes share caller transaction semantics.
- [ ] T009 Add procedure rollback/commit integration coverage.

### WP04 - Procedure Diagnostics and Body Hardening

**Prompt**: `tasks/WP04-procedure-diagnostics-body-hardening.md`  
**Priority**: P1 safety  
**Requirement Refs**: FR-007, FR-008, FR-011, FR-012  
**Dependencies**: WP03

- [ ] T010 Harden procedure body diagnostics and loop guard behavior.
- [ ] T011 Preserve unsupported stored-program rejection coverage.
- [ ] T012 Prove no partial catalog mutation for rejected procedure bodies.

### WP05 - Phase 7 Acceptance and Roadmap Refresh

**Prompt**: `tasks/WP05-phase7-acceptance-roadmap.md`  
**Priority**: P2 acceptance  
**Requirement Refs**: FR-009, FR-010, FR-011, FR-012  
**Dependencies**: WP01, WP02, WP03, WP04

- [ ] T013 Update Phase 7 roadmap and dialect docs.
- [ ] T014 Add Phase 7 acceptance evidence document.
- [ ] T015 Run full validation and close integration gaps.

## Acceptance Handoff

Natural runtime command:

```sh
spec-kitty next --agent codex:gpt-5:implementer-ivan:implementer --mission phase7-views-procedures-hardening-01KT9RHH
```

If protected-main safe commits fail, use the manual commit fallback documented
in `docs/spec-kitty-system-notes.md`.
