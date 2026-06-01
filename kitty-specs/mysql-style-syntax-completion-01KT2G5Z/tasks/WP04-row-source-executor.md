---
work_package_id: WP04
title: Row-Source Executor
dependencies:
- WP03
requirement_refs:
- FR-007
- FR-009
- FR-010
- FR-012
- FR-016
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
subtasks: []
history: []
agent_profile: implementer-ivan
authoritative_surface: src/db/query_source.zig
execution_mode: code_change
owned_files:
- src/db/query_source.zig
- tests/integration/query_source_acceptance.zig
role: implementer
tags: []
---

# WP04 - Row-Source Executor

## Objective

Execute the generalized query-source AST with row environments, alias
resolution, joins, CTEs, derived tables, and richer views.

## Tasks

1. Introduce an executor row environment that can hold columns from one or more
   sources.
2. Resolve unqualified identifiers only when unambiguous; resolve qualified
   identifiers through source aliases.
3. Execute base table/view sources, derived sources, and CTE refs.
4. Execute plain/inner joins, cross joins, and left joins with `ON` predicates.
5. Expand view execution over the richer supported SELECT forms.
6. Add integration tests for the CTE/join example in the spec.
7. Coordinate minimal integration edits to `src/db/executor.zig` through review
   when wiring this new row-source module into live SELECT execution.

## Definition of Done

- Existing single-table SELECT behavior still passes.
- Joined and derived queries produce deterministic column names and values.
- Ambiguous or missing columns fail with typed diagnostics.
- `zig build test` passes.
