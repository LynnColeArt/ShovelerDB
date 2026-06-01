---
work_package_id: WP05
title: Aggregates and Grouping
dependencies:
- WP04
requirement_refs:
- FR-011
- FR-016
- FR-019
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
base_commit: 49b7714c8acfe038b6a59f7c783fb6142bd3ce1a
created_at: '2026-06-01T22:26:41.941886+00:00'
subtasks: []
shell_pid: '1166952'
history: []
agent_profile: implementer-ivan
authoritative_surface: src/db/aggregate.zig
execution_mode: code_change
owned_files:
- src/db/aggregate.zig
- tests/integration/aggregate_acceptance.zig
role: implementer
tags: []
agent: "codex"
---

# WP05 - Aggregates and Grouping

## Objective

Add aggregate execution for practical reporting queries.

## Tasks

1. Parse `GROUP BY` and `HAVING`.
2. Execute `COUNT`, `SUM`, `AVG`, `MIN`, and `MAX`.
3. Reject non-grouped projections that are neither aggregate nor grouped keys.
4. Add grouped query tests and benchmark coverage for grouped scans.
5. Coordinate parser/executor integration edits through review after the
   aggregate module owns the grouped-row behavior.

## Definition of Done

- The grouped-query example from the spec passes.
- Invalid aggregate/grouping mixes produce explicit diagnostics.
- `zig build test` passes.

## Activity Log

- 2026-06-01T22:40:10Z – codex – shell_pid=1166952 – Done override: Implemented aggregate grouping on lane commit dc1ba0c, landed on main as 87d1c0e, and validated with zig build test, diff check, CLI GROUP BY/HAVING smoke, and benchmark grouped_scan smoke.
