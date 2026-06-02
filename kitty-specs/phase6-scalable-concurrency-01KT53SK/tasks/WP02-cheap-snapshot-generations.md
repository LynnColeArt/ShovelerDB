---
work_package_id: WP02
title: Cheap Snapshot Generations
dependencies:
- WP01
requirement_refs:
- FR-002
- FR-003
- FR-006
- FR-013
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
base_commit: ced089145590a58c3640746c116820408c114e07
created_at: '2026-06-02T21:29:15Z'
subtasks:
- T004
- T005
- T006
agent: ''
history:
- timestamp: '2026-06-02T21:29:15Z'
  agent: codex
  action: Prompt generated for Phase 6 scalable concurrency planning.
agent_profile: implementer-ivan
authoritative_surface: src/db/snapshot.zig
execution_mode: code_change
model: ''
owned_files:
- src/db/snapshot.zig
- tests/integration/snapshot_generation_acceptance.zig
role: implementer
tags:
- phase6
- mvcc
---

# Work Package Prompt: WP02 - Cheap Snapshot Generations

## Objective

Replace row-store cloning at reader `BEGIN` with a cheap committed-generation
snapshot model while preserving stable reader visibility.

## Tasks

1. Add a committed generation or snapshot-handle module.
2. Refactor session begin/read paths so readers hold generation handles instead
   of cloning every row.
3. Preserve read-your-writes behavior for writer sessions.
4. Add cleanup tests so session commit, rollback, and deinit release snapshot
   state.
5. Keep existing SQL, view, procedure, vector, and MTR-lite tests passing.

## Integration Touchpoints

Likely integration files include `src/db/executor.zig`,
`src/db/transaction.zig`, and `src/db/row_store.zig`. Keep edits minimal and
document any ownership guard warnings.

## Definition of Done

- `zig build test` passes.
- Reader snapshots stay stable without clone-on-`BEGIN` row duplication.
- Snapshot cleanup is covered by tests.
