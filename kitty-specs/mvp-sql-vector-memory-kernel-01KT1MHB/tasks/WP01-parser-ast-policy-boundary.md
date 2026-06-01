---
work_package_id: WP01
title: Parser, AST, and Policy Boundary
dependencies: []
requirement_refs:
- FR-001
- FR-002
- FR-017
- FR-018
- FR-019
- FR-020
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
subtasks:
- T001
- T002
- T003
- T004
- T005
agent: codex
history:
- timestamp: '2026-06-01T13:10:41Z'
  agent: codex
  action: Prompt generated via Spec Kitty tasks planning
agent_profile: implementer-ivan
authoritative_surface: src/sql/
execution_mode: code_change
model: ''
owned_files:
- src/sql/ast.zig
- src/sql/parser.zig
- src/sql/policy.zig
- src/sql/tokenizer.zig
role: implementer
tags: []
---

# Work Package Prompt: WP01 - Parser, AST, and Policy Boundary

## ⚡ Do This First: Load Agent Profile

Use the `/ad-hoc-profile-load` skill to load the agent profile specified in the frontmatter, and behave according to its guidance before parsing the rest of this prompt.

- **Profile**: `implementer-ivan`
- **Role**: `implementer`
- **Agent/tool**: `codex`

If no profile is specified, run `spec-kitty profiles list` and select the best match for this work package's `task_type` and `authoritative_surface`.

---

## Objective

Add the structured SQL layer that turns the current policy gate into a real
parser boundary. Preserve the existing explicit non-goal rejections while adding
AST coverage for the MVP SQL statements needed by later work packages.

Implementation command:

```
spec-kitty agent action implement WP01 --agent codex
```

## Context

ShovelerDB already tokenizes SQL and rejects deliberate non-goals. The parser
must not weaken that boundary. Later catalog, executor, transaction, view, and
procedure work should consume structured AST values rather than re-parsing raw
strings.

Owned files are restricted to `src/sql/`. Do not modify CLI, catalog, executor,
or test fixture files from this package.

### Subtask T001: Add MVP SQL AST types

**Purpose**: Define the data structures shared by parser and executor.

**Steps**:

1. Create `src/sql/ast.zig`.
2. Define statement variants for create/drop table, insert, select, update,
   delete, begin, commit, rollback, create/drop view, create/drop procedure,
   and call.
3. Define expression variants for identifiers, literals, comparisons, boolean
   conjunction where needed, function calls, order keys, and limits.
4. Define column type variants for scalar MVP types and `vector` with dimension.
5. Add small construction/deinit tests that prove owned strings/vectors are
   allocator-safe.

**Files**: `src/sql/ast.zig`

**Validation**: `zig test src/sql/ast.zig`

### Subtask T002: Implement parser shell and statement dispatch

**Purpose**: Provide a parser entry point that runs after the policy gate and
dispatches by statement family.

**Steps**:

1. Create `src/sql/parser.zig`.
2. Add `parse(allocator, sql_text)` returning an AST statement or typed parser
   diagnostic.
3. Reuse tokenizer behavior where possible; do not duplicate comment/string
   skipping logic with ad hoc scanning.
4. Add location-aware errors for unexpected token, unexpected end, and unsupported
   but policy-accepted syntax.
5. Keep unsupported non-goals rejected by `policy.zig` before parser mutation.

**Files**: `src/sql/parser.zig`, `src/sql/tokenizer.zig`

**Validation**: parser tests for empty input, unknown statements, and basic
statement family dispatch.

### Subtask T003: Parse DDL, transaction, and mutation statements

**Purpose**: Cover the syntax needed to create tables and mutate rows.

**Steps**:

1. Parse `CREATE TABLE name (...)` with scalar columns and `VECTOR(N)`.
2. Parse `DROP TABLE name`.
3. Parse `INSERT INTO name [(columns)] VALUES (...)`.
4. Parse `UPDATE name SET column = expr [, ...] WHERE expr`.
5. Parse `DELETE FROM name WHERE expr`.
6. Parse `BEGIN`, `COMMIT`, and `ROLLBACK`.

**Files**: `src/sql/parser.zig`, `src/sql/ast.zig`

**Validation**: tests assert AST shape for each statement and typed errors for
malformed input.

### Subtask T004: Parse query, view, procedure, and vector expression syntax

**Purpose**: Provide enough structure for MVP reads, views, procedures, and
exact vector search.

**Steps**:

1. Parse `SELECT` with projection, single-table `FROM`, simple `WHERE`,
   `ORDER BY`, and `LIMIT`.
2. Parse function-call expressions such as `l2_distance(embedding, [1,2,3])`
   or the selected vector literal syntax.
3. Parse `CREATE VIEW name AS SELECT ...` and `DROP VIEW name`.
4. Parse `CREATE PROCEDURE name(...) BEGIN ... END` at the constrained MVP
   depth or a documented single-statement body form.
5. Parse `CALL name(...)`.

**Files**: `src/sql/parser.zig`, `src/sql/ast.zig`

**Validation**: tests cover view/procedure/vector statement parsing and reject
unsupported stored-program bodies cleanly.

### Subtask T005: Preserve policy-first rejection tests

**Purpose**: Ensure the new parser does not accidentally admit excluded MariaDB
surfaces.

**Steps**:

1. Add or update policy tests for foreign keys, references, temp tables,
   engine selection, plugins, replication/binlog, users, grants, and auth.
2. Add parser tests that demonstrate callers should run policy first.
3. Keep diagnostic categories stable enough for downstream tests.

**Files**: `src/sql/policy.zig`, `src/sql/parser.zig`

**Validation**: `zig build test` plus direct parser/policy tests.

## Definition of Done

- AST and parser modules exist.
- MVP syntax parses into typed AST values.
- Deliberate non-goals still reject through policy.
- Parser diagnostics are typed and tested.
- No files outside `src/sql/` are modified.

## Risks

- SQL grammar can sprawl. Keep only MVP syntax.
- Procedure syntax can explode. Constrain it and document unsupported bodies.
- String ownership can leak. Use Zig test allocator patterns.

## Reviewer Guidance

Reviewers should focus on grammar boundaries, allocation/deinit behavior, and
whether any non-goal can reach parser/executor as if it were supported.
