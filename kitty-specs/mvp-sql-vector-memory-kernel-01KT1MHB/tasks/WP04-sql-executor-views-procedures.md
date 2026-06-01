---
work_package_id: WP04
title: SQL Executor, Views, and Procedures
dependencies:
- WP01
- WP02
- WP03
requirement_refs:
- FR-007
- FR-021
- FR-022
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: kitty/mission-mvp-sql-vector-memory-kernel-01KT1MHB
base_commit: acfc57718f8db92df7f38c25c7e16ca3896647f4
created_at: '2026-06-01T14:31:31.987695+00:00'
subtasks:
- T014
- T015
- T016
- T017
- T018
agent: "codex:gpt-5:reviewer-renata:reviewer"
shell_pid: "1166952"
history:
- timestamp: '2026-06-01T13:10:41Z'
  agent: codex
  action: Prompt generated via Spec Kitty tasks planning
agent_profile: implementer-ivan
authoritative_surface: src/db/
execution_mode: code_change
model: ''
owned_files:
- src/db/executor.zig
- src/db/view.zig
- src/db/procedure.zig
role: implementer
tags: []
---

# Work Package Prompt: WP04 - SQL Executor, Views, and Procedures

## ⚡ Do This First: Load Agent Profile

Use the `/ad-hoc-profile-load` skill to load the agent profile specified in the frontmatter, and behave according to its guidance before parsing the rest of this prompt.

- **Profile**: `implementer-ivan`
- **Role**: `implementer`
- **Agent/tool**: `codex`

If no profile is specified, run `spec-kitty profiles list` and select the best match for this work package's `task_type` and `authoritative_surface`.

---

## Objective

Execute the MVP AST against the catalog, row store, and transaction model. Add
simple view and procedure behavior without expanding into full MariaDB stored
program compatibility.

Implementation command:

```
spec-kitty agent action implement WP04 --agent codex
```

## Context

This package depends on parser, catalog, and transaction surfaces. It owns
executor-related DB files only. Vector distance integration may call helpers
from WP05 when available, but exact vector helper implementation belongs there.

### Subtask T014: Implement SELECT scan/projection/filter/order/limit

**Purpose**: Query rows from a single table using the MVP expression model.

**Steps**:

1. Create `src/db/executor.zig`.
2. Add an execution context with catalog, transaction/session, and allocator.
3. Implement single-table scan.
4. Evaluate simple predicates and projections.
5. Support `ORDER BY` and `LIMIT`.
6. Return rows in a testable result structure.

**Files**: `src/db/executor.zig`

**Validation**: executor tests for select all, select projection, where, order,
and limit.

### Subtask T015: Implement INSERT, UPDATE, and DELETE execution

**Purpose**: Mutate tables through transaction context.

**Steps**:

1. Execute insert statements with type checks.
2. Execute update statements with simple predicate filtering.
3. Execute delete statements with simple predicate filtering.
4. Reject unknown table, unknown column, type mismatch, and vector dimension
   mismatch with typed diagnostics.

**Files**: `src/db/executor.zig`

**Validation**: tests cover mutation counts and transaction-local visibility.

### Subtask T016: Implement simple view registration and execution

**Purpose**: Keep views in the sacred SQL surface.

**Steps**:

1. Create `src/db/view.zig`.
2. Register a view over a supported `SELECT` AST.
3. Drop views by name.
4. Execute a view by expanding or delegating to the stored `SELECT`.
5. Reject unsupported recursive/nested cases clearly if outside MVP.

**Files**: `src/db/view.zig`, `src/db/executor.zig`

**Validation**: tests cover create view, query view, drop view, and missing view.

### Subtask T017: Implement constrained procedure registration and CALL

**Purpose**: Keep procedures in scope without building a full stored-program VM.

**Steps**:

1. Create `src/db/procedure.zig`.
2. Register procedures with a supported body shape.
3. Implement `CALL` for simple statement bodies.
4. Reject unsupported variables/control flow with typed diagnostics.
5. Document constraints in test names or comments.

**Files**: `src/db/procedure.zig`, `src/db/executor.zig`

**Validation**: tests cover create/call/drop procedure and unsupported body
syntax.

### Subtask T018: Add executor diagnostics and integration tests

**Purpose**: Make executor failures reviewable.

**Steps**:

1. Define or reuse typed executor diagnostic categories.
2. Add tests that assert categories rather than fragile message text.
3. Cover unknown object, type mismatch, transaction state, and unsupported
   procedure/view forms.

**Files**: `src/db/executor.zig`, `src/db/view.zig`, `src/db/procedure.zig`

**Validation**: direct Zig tests for the owned files.

## Definition of Done

- SELECT, INSERT, UPDATE, DELETE execute against the transaction model.
- Views and constrained procedures are supported at MVP depth.
- Unsupported view/procedure cases produce typed errors.
- Tests cover happy paths and diagnostics.
- No files outside the owned executor/view/procedure surface are modified.

## Risks

- Executor can become a second parser. Consume AST types, not raw SQL.
- Procedure support can expand too far. Keep control flow out unless already
  specified by the parser and tests.

## Reviewer Guidance

Review semantic correctness and boundaries. Make sure the executor does not
silently ignore unsupported clauses.

## Activity Log

- 2026-06-01T14:43:21Z – codex – shell_pid=1166952 – WP04 implementation committed in lane-d at 4c792fc after cherry-picking approved WP01/WP02/WP03 dependencies; validation passed: zig test src/db/procedure.zig, zig build test, git diff --check. Includes minimal src/lib.zig export wiring so executor/view/procedure tests run through the library build.
- 2026-06-01T14:43:36Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Started review via action command
