---
work_package_id: WP03
title: Procedure Call and Transaction Semantics
dependencies: []
requirement_refs:
- FR-005
- FR-006
- FR-007
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
- T007
- T008
- T009
agent_profile: implementer-ivan
authoritative_surface: src/db/procedure.zig
execution_mode: code_change
owned_files:
- src/db/procedure.zig
- tests/integration/procedure_transaction_acceptance.zig
role: implementer
tags:
- phase7
- procedures
---

# Work Package Prompt: WP03 - Procedure Call and Transaction Semantics

## Objective

Make procedure calls boringly correct: argument binding, caller transaction
visibility, rollback behavior, and stable call diagnostics.

## Tasks

1. Harden `CALL` validation for missing procedures, argument count, and known
   type mismatches.
2. Prove procedure body SQL executes in the caller session and transaction
   context.
3. Add coverage for procedure writes visible before commit, durable after
   commit, and discarded after rollback.
4. Keep procedure body execution routed through existing SQL executor entry
   points instead of a parallel runtime.
5. Coordinate parser/executor/build integration through review if needed.

## Definition of Done

- Procedure transaction tests cover commit and rollback behavior.
- Bad `CALL` shapes return stable diagnostics.
- Existing procedure acceptance tests still pass.
- `zig build test` passes.
