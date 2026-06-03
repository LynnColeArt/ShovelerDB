---
work_package_id: WP04
title: Checkpoint and Vector Overlay Coordination
dependencies:
- WP03
requirement_refs:
- FR-007
- FR-008
- FR-009
- FR-010
- FR-013
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
base_commit: bb817424e80f336a35efc949a2d0ea8dcbcd55cd
created_at: '2026-06-03T03:44:11.691961+00:00'
subtasks:
- T011
- T012
- T013
- T014
agent: "codex"
shell_pid: '1166952'
history:
- timestamp: '2026-06-02T21:29:15Z'
  agent: codex
  action: Prompt generated for Phase 6 scalable concurrency planning.
agent_profile: implementer-ivan
authoritative_surface: src/db/checkpoint_worker.zig
execution_mode: code_change
model: ''
owned_files:
- src/db/checkpoint_worker.zig
- src/vector/overlay.zig
- tests/integration/checkpoint_vector_overlay_acceptance.zig
role: implementer
tags:
- phase6
- checkpoint
- vector-overlay
---

# Work Package Prompt: WP04 - Checkpoint and Vector Overlay Coordination

## Objective

Coordinate checkpoint reads with committed generations and add the vector overlay
contract needed before future background ANN indexing.

## Tasks

1. Add a checkpoint coordination module that snapshots committed generations.
2. Ensure failed checkpoint writes leave durable and in-memory committed state
   intact.
3. Add a vector overlay/delta module for committed vector writes.
4. Ensure exact vector scans include committed overlay deltas.
5. Expose drain-style hooks for a future background vector index worker without
   implementing ANN indexing.

## Integration Touchpoints

Likely integration files include `src/db/database.zig`,
`src/db/persistence.zig`, `src/db/executor.zig`, and vector search paths.

## Definition of Done

- `zig build test` passes.
- Checkpoint-overlap tests pass.
- Exact vector reads see committed overlay deltas.

## Activity Log

- 2026-06-03T03:50:16Z – codex – shell_pid=1166952 – WP04 lane 53cdf0f coordinates checkpoint state and vector overlay deltas; zig build test, zig fmt --check, and diff checks passed.
