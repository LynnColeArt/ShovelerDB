---
work_package_id: WP02
title: SQL Function Execution and Vector Ranking
dependencies: []
requirement_refs:
- FR-003
- FR-004
- FR-005
- FR-016
- FR-019
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
subtasks: []
shell_pid: 'unknown'
history: []
agent_profile: implementer-ivan
authoritative_surface: src/db/executor.zig
execution_mode: code_change
owned_files:
- src/db/executor.zig
- tests/integration/kernel_acceptance.zig
- tests/fixtures/mariadb-adapted/vector-distance-functions.md
role: implementer
tags: []
agent: "codex"
---

# WP02 - SQL Function Execution and Vector Ranking

## Objective

Make existing parsed function-call expressions executable, with vector distance
functions available in projection, filtering, and ordering contexts.

## Tasks

1. Add executor evaluation for built-in function calls.
2. Implement `l2_distance`, `squared_l2_distance`, and `cosine_distance` over
   vector values and vector literals.
3. Return typed errors for wrong argument count, wrong argument type, zero-vector
   cosine, and vector dimension mismatch.
4. Add executor and integration tests for:
   - projected distance columns
   - `WHERE` predicates using distance functions
   - `ORDER BY l2_distance(...) LIMIT n`
   - dimension mismatch diagnostics
5. Keep unsupported functions rejected with `UnsupportedExpression`.

## Definition of Done

- SQL vector ranking works without application-side calls to
  `vector.search.topK`.
- Existing parser function-call tests now correspond to executable behavior.
- `zig build test` passes.

## Activity Log

- 2026-06-01T21:25Z - codex - Implemented executor evaluation for
  `l2_distance`, `squared_l2_distance`, and `cosine_distance`; added executor
  and integration coverage; added `vector-distance-functions.md` adapted
  fixture. Validation: `zig build test`, `run-adapted-test` smokes, and CLI SQL
  vector-ranking smoke.
- 2026-06-01T21:18:52Z – codex – Done override: Implemented directly on main before lane allocation; validated with zig build test and SQL vector-ranking CLI smoke.
