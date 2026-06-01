---
work_package_id: WP02
title: Catalog, Types, and Values
dependencies: []
requirement_refs:
- FR-003
- FR-004
- FR-005
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: kitty/mission-mvp-sql-vector-memory-kernel-01KT1MHB
base_commit: 3bc400f1426e8c8205a72beb05fe559e8843eca4
created_at: '2026-06-01T14:15:51.891048+00:00'
subtasks:
- T006
- T007
- T008
- T009
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
- src/db/value.zig
- src/db/catalog.zig
role: implementer
tags: []
---

# Work Package Prompt: WP02 - Catalog, Types, and Values

## ⚡ Do This First: Load Agent Profile

Use the `/ad-hoc-profile-load` skill to load the agent profile specified in the frontmatter, and behave according to its guidance before parsing the rest of this prompt.

- **Profile**: `implementer-ivan`
- **Role**: `implementer`
- **Agent/tool**: `codex`

If no profile is specified, run `spec-kitty profiles list` and select the best match for this work package's `task_type` and `authoritative_surface`.

---

## Objective

Create the typed catalog and value layer used by rows, transactions, executor,
vectors, and persistence. Keep it independent from parser internals so later
packages can use it as the kernel's semantic model.

Implementation command:

```
spec-kitty agent action implement WP02 --agent codex
```

## Context

The plan calls for a typed catalog with tables, columns, views, procedures, and
vector metadata. This work package owns only `src/db/value.zig` and
`src/db/catalog.zig`.

### Subtask T006: Define scalar/vector value representation

**Purpose**: Represent runtime values without entangling them with SQL text.

**Steps**:

1. Create `src/db/value.zig`.
2. Define `Value` variants for null, integer, float, boolean, text, blob, and
   vector.
3. Define vector storage with explicit dimension and element type.
4. Add clone/deinit helpers where heap ownership is involved.
5. Add typed errors for type mismatch and vector dimension mismatch.

**Files**: `src/db/value.zig`

**Validation**: direct Zig tests cover scalar values, vector dimensions, clone,
and deinit behavior.

### Subtask T007: Define column and table metadata

**Purpose**: Give tables a structured schema.

**Steps**:

1. Define `ColumnType`, including scalar types and `vector(dimension)`.
2. Define `ColumnDef` with name, type, and nullable/default placeholders if
   useful for later extensions.
3. Define `TableDef` with table name and ordered columns.
4. Add helper lookups by column name and ordinal.

**Files**: `src/db/catalog.zig`, `src/db/value.zig`

**Validation**: tests cover column lookup, duplicate column detection, and
vector column metadata.

### Subtask T008: Implement catalog object lifecycle

**Purpose**: Track tables, views, and procedures by stable names.

**Steps**:

1. Define `DatabaseCatalog`.
2. Add create/drop/list/get operations for tables.
3. Add registration placeholders for views and procedures that can store a
   canonical name and body/reference representation.
4. Return typed errors for duplicate object, unknown object, and name conflicts.
5. Keep the API allocator-conscious.

**Files**: `src/db/catalog.zig`

**Validation**: tests cover create/drop/list/get and duplicate/missing errors.

### Subtask T009: Add catalog/type diagnostics and tests

**Purpose**: Make downstream executor errors stable.

**Steps**:

1. Define diagnostic categories that executor and persistence can reuse.
2. Assert that invalid vector dimensions fail before mutation.
3. Assert that object lifecycle errors are stable and typed.

**Files**: `src/db/catalog.zig`, `src/db/value.zig`

**Validation**: `zig test src/db/catalog.zig` and `zig test src/db/value.zig`.

## Definition of Done

- `Value`, `ColumnType`, `TableDef`, and `DatabaseCatalog` exist.
- Catalog can manage tables, views, and procedures at metadata depth.
- Vector dimensions are represented and validated.
- Tests cover ownership and typed errors.
- No files outside the owned surface are modified.

## Risks

- Overdesigning schema features can slow the MVP. Keep defaults and constraints
  minimal unless executor needs them.
- Heap ownership bugs can hide until integration. Prefer explicit clone/deinit
  tests now.

## Reviewer Guidance

Review the public shape of catalog/value APIs carefully. Later packages should
not need to know about raw parser tokens to use the catalog.

## Activity Log

- 2026-06-01T14:21:34Z – codex – shell_pid=1166952 – WP02 implementation committed in lane-b at 6546f7d; validation passed: zig test src/db/value.zig, zig test src/db/catalog.zig, zig build test, git diff --check.
- 2026-06-01T14:22:03Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Started review via action command
- 2026-06-01T14:22:39Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Review passed. API is allocator-conscious, parser-independent, and validates catalog/value/vector diagnostics for downstream WPs.
