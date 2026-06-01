---
work_package_id: WP05
title: Vector Functions and Exact Search
dependencies:
- WP02
requirement_refs:
- FR-005
- FR-006
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: kitty/mission-mvp-sql-vector-memory-kernel-01KT1MHB
base_commit: 600a750f8d6ee892c959ae608affe708d3ea5a58
created_at: '2026-06-01T14:45:26.670657+00:00'
subtasks:
- T019
- T020
- T021
agent: "codex:gpt-5:reviewer-renata:reviewer"
shell_pid: "1166952"
history:
- timestamp: '2026-06-01T13:10:41Z'
  agent: codex
  action: Prompt generated via Spec Kitty tasks planning
agent_profile: implementer-ivan
authoritative_surface: src/vector/
execution_mode: code_change
model: ''
owned_files:
- src/vector/distance.zig
- src/vector/search.zig
role: implementer
tags: []
---

# Work Package Prompt: WP05 - Vector Functions and Exact Search

## ⚡ Do This First: Load Agent Profile

Use the `/ad-hoc-profile-load` skill to load the agent profile specified in the frontmatter, and behave according to its guidance before parsing the rest of this prompt.

- **Profile**: `implementer-ivan`
- **Role**: `implementer`
- **Agent/tool**: `codex`

If no profile is specified, run `spec-kitty profiles list` and select the best match for this work package's `task_type` and `authoritative_surface`.

---

## Objective

Implement native vector distance helpers and exact search utilities. This is the
fast, honest baseline before any approximate nearest-neighbor index exists.

Implementation command:

```
spec-kitty agent action implement WP05 --agent codex
```

## Context

Vectors are a first-class ShovelerDB type. WP02 owns the runtime value type;
this package owns vector math and exact search helpers under `src/vector/`.

### Subtask T019: Implement vector distance functions

**Purpose**: Provide exact L2 and cosine distance calculations.

**Steps**:

1. Create `src/vector/distance.zig`.
2. Implement squared L2 and L2 distance for equal-length float vectors.
3. Implement cosine distance with clear behavior for zero vectors.
4. Return typed dimension mismatch errors instead of panicking.

**Files**: `src/vector/distance.zig`

**Validation**: tests cover known distances, dimension mismatch, and zero-vector
cosine behavior.

### Subtask T020: Implement exact vector search helpers

**Purpose**: Support query-time nearest-neighbor ordering without ANN indexes.

**Steps**:

1. Create `src/vector/search.zig`.
2. Define a small candidate/result structure with row ID or caller-provided key.
3. Implement top-k exact scan using distance functions.
4. Keep allocation and sorting behavior explicit.

**Files**: `src/vector/search.zig`

**Validation**: tests cover top-k ordering, ties, empty input, and limit larger
than candidate count.

### Subtask T021: Add vector validation and ordering tests

**Purpose**: Lock exact vector behavior before executor integration.

**Steps**:

1. Add tests that match expected ordering for small hand-built vectors.
2. Include non-normalized vectors for cosine distance.
3. Include dimension mismatch failures.

**Files**: `src/vector/distance.zig`, `src/vector/search.zig`

**Validation**: `zig test src/vector/distance.zig` and `zig test src/vector/search.zig`.

## Definition of Done

- L2 and cosine distance helpers exist.
- Exact top-k search helper exists.
- Tests cover ordering and dimension errors.
- No ANN/index work is introduced.
- No files outside `src/vector/` are modified.

## Risks

- Floating-point assertions can be brittle. Use tolerances.
- Search helpers can accidentally own too much DB state. Keep them generic.

## Reviewer Guidance

Review math correctness, edge cases, and allocator behavior. Confirm this stays
an exact-scan baseline.

## Activity Log

- 2026-06-01T14:47:24Z – codex – shell_pid=1166952 – WP05 implementation committed in lane-e at 9def588; validation passed: zig test src/vector/distance.zig, zig test src/vector/search.zig, git diff --check.
- 2026-06-01T14:47:37Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Started review via action command
- 2026-06-01T14:48:02Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Review passed. Exact L2/cosine helpers and generic top-k scan are scoped to src/vector with deterministic ordering and typed dimension/zero-vector diagnostics.
