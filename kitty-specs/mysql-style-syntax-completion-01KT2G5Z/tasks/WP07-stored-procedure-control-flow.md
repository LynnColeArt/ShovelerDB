---
work_package_id: WP07
title: Stored Procedure Control Flow
dependencies:
- WP02
- WP04
- WP06
requirement_refs:
- FR-014
- FR-015
- FR-016
- FR-018
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
subtasks: []
shell_pid: '1166952'
history: []
agent_profile: implementer-ivan
authoritative_surface: src/db/procedure.zig
execution_mode: code_change
owned_files:
- src/sql/procedure_body.zig
- src/db/procedure.zig
- tests/integration/procedure_acceptance.zig
role: implementer
tags: []
---

# WP07 - Stored Procedure Control Flow

## Objective

Turn procedures from single-statement storage into a useful embedded stored
program subset.

## Tasks

1. Parse `IN` parameters and bind `CALL` arguments.
2. Parse procedure bodies into body statements instead of opaque raw SQL.
3. Execute `DECLARE`, `SET`, ordinary SQL statements, `IF`, and bounded
   `WHILE`.
4. Share the caller session and transaction state.
5. Reject cursors, handlers, dynamic SQL, and unsupported stored-program
   features with stable diagnostics.
6. Coordinate parser/executor integration edits through review after the body
   model and procedure runtime are in place.

## Definition of Done

- The procedure example from the spec passes.
- Procedure writes participate in caller transaction visibility.
- Unsupported stored-program features have tests and diagnostics.
- `zig build test` passes.
