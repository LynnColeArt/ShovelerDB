---
work_package_id: WP03
title: In-Memory Row Store and Transactions
dependencies:
- WP02
requirement_refs:
- FR-008
- FR-009
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: kitty/mission-mvp-sql-vector-memory-kernel-01KT1MHB
base_commit: 35f20183b7f64e8f64b7a3a507afbc6df915aaa4
created_at: '2026-06-01T14:23:05.832382+00:00'
subtasks:
- T010
- T011
- T012
- T013
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
- src/db/row_store.zig
- src/db/transaction.zig
role: implementer
tags: []
---

# Work Package Prompt: WP03 - In-Memory Row Store and Transactions

## ⚡ Do This First: Load Agent Profile

Use the `/ad-hoc-profile-load` skill to load the agent profile specified in the frontmatter, and behave according to its guidance before parsing the rest of this prompt.

- **Profile**: `implementer-ivan`
- **Role**: `implementer`
- **Agent/tool**: `codex`

If no profile is specified, run `spec-kitty profiles list` and select the best match for this work package's `task_type` and `authoritative_surface`.

---

## Objective

Implement the in-memory table state and transaction-local mutation model. The
goal is correct commit/rollback visibility first; high-concurrency optimization
can follow after baseline benchmarks exist.

Implementation command:

```
spec-kitty agent action implement WP03 --agent codex
```

## Context

This package depends on WP02's value and catalog types. It owns only
`src/db/row_store.zig` and `src/db/transaction.zig`.

### Subtask T010: Build table row storage primitives

**Purpose**: Store rows by stable IDs in memory.

**Steps**:

1. Create `src/db/row_store.zig`.
2. Define row ID allocation.
3. Store rows as ordered value arrays tied to table metadata.
4. Implement insert, update, delete, and scan primitives without SQL semantics.
5. Add tests for stable row IDs and mutation behavior.

**Files**: `src/db/row_store.zig`

**Validation**: direct Zig tests for row insert/update/delete/scan.

### Subtask T011: Add transaction-local mutation tracking

**Purpose**: Isolate uncommitted writes from committed state.

**Steps**:

1. Create `src/db/transaction.zig`.
2. Define transaction state: active, committed, rolled back.
3. Track local inserts, updates, deletes, and catalog mutations if needed.
4. Keep mutation replay deterministic.

**Files**: `src/db/transaction.zig`

**Validation**: tests prove local mutations do not alter the committed row store
until commit.

### Subtask T012: Implement begin, commit, and rollback visibility

**Purpose**: Encode the sacred transaction contract.

**Steps**:

1. Add begin/commit/rollback methods.
2. Ensure a transaction reads its own writes.
3. Ensure other sessions do not see uncommitted writes.
4. Ensure rollback discards every local mutation.
5. Ensure commit publishes a consistent in-memory state.

**Files**: `src/db/transaction.zig`, `src/db/row_store.zig`

**Validation**: transaction tests for begin, commit, rollback, double commit,
and rollback-after-commit errors.

### Subtask T013: Add multi-session transaction tests

**Purpose**: Guard the behavior agents will rely on.

**Steps**:

1. Model two sessions against a shared committed state.
2. Assert session A sees its own insert before commit.
3. Assert session B does not see A's insert before commit.
4. Assert B sees the row after A commits.
5. Assert rollback keeps B unchanged.

**Files**: `src/db/transaction.zig`

**Validation**: direct Zig tests; later WP08 wires them into `zig build test`.

## Definition of Done

- Row storage primitives are usable without SQL.
- Transaction state and mutation replay exist.
- Two-session visibility tests pass.
- Rollback is complete and deterministic.
- No files outside `src/db/row_store.zig` and `src/db/transaction.zig` are modified.

## Risks

- Snapshot copying may be slow. Accept simple correctness first and benchmark
  before optimizing.
- Transaction APIs can leak ownership. Keep allocator ownership explicit.

## Reviewer Guidance

Review visibility semantics more than raw speed. The MVP can be optimized later;
incorrect transaction behavior is not acceptable.

## Activity Log

- 2026-06-01T14:28:42Z – codex – shell_pid=1166952 – WP03 implementation committed in lane-c at 7f50fce after cherry-picking approved WP02 dependency 450d57f; validation passed: zig test src/db/row_store.zig, zig test src/db/transaction.zig, zig build test, git diff --check.
- 2026-06-01T14:29:00Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Started review via action command
- 2026-06-01T14:30:53Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Review passed after moving row-id reservation into transaction-local state. Validated with row_store/transaction direct tests, zig build test, and diff check.
