---
work_package_id: WP01
title: View Expansion and Lifecycle Diagnostics
dependencies: []
requirement_refs:
- FR-001
- FR-002
- FR-003
- FR-011
- FR-012
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
base_commit: d0073eb7ceb53839c6ac90b70f182ce9604d8238
created_at: '2026-06-04T16:55:00+00:00'
subtasks:
- T001
- T002
- T003
agent_profile: implementer-ivan
authoritative_surface: src/db/view.zig
execution_mode: code_change
owned_files:
- src/db/view.zig
- tests/integration/view_acceptance.zig
role: implementer
tags:
- phase7
- views
---

# Work Package Prompt: WP01 - View Expansion and Lifecycle Diagnostics

## Objective

Harden executable views over the supported row-source `SELECT` surface and make
view lifecycle failures deterministic.

## Tasks

1. Ensure views execute through the same row-source path as direct `SELECT`
   statements for aliases, qualified identifiers, joins, CTEs, derived tables,
   grouping, ordering, limits, and vector expressions already supported by the
   engine.
2. Stabilize view result column names and aliases where they are exposed to
   callers or outer queries.
3. Add typed diagnostics for duplicate view creation, missing view drops, and
   querying dropped or unknown views.
4. Add or extend integration coverage for rich view expansion and lifecycle
   diagnostics.
5. Coordinate any required parser/executor/build wiring through review; keep
   the primary behavior owned by `src/db/view.zig` and the new acceptance test.

## Definition of Done

- View expansion tests cover at least one rich query-source view.
- Lifecycle diagnostics are stable and tested.
- Existing query-source, aggregate, vector, procedure, persistence, and
  concurrency tests still pass.
- `zig build test` passes.
