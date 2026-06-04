---
work_package_id: WP04
title: Procedure Diagnostics and Body Hardening
dependencies:
- WP03
requirement_refs:
- FR-007
- FR-008
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
- T010
- T011
- T012
agent_profile: implementer-ivan
authoritative_surface: src/sql/procedure_body.zig
execution_mode: code_change
owned_files:
- src/sql/procedure_body.zig
- tests/integration/procedure_diagnostics_acceptance.zig
role: implementer
tags:
- phase7
- procedures
- diagnostics
agent: "codex:gpt-5:implementer-ivan:implementer"
---

# Work Package Prompt: WP04 - Procedure Diagnostics and Body Hardening

## Objective

Tighten the constrained procedure body language and preserve explicit rejection
for unsupported stored-program features.

## Tasks

1. Add tests for local variable assignment, `IF`, bounded `WHILE`, and loop cap
   behavior not already covered by Phase 6/previous syntax acceptance.
2. Preserve rejection tests for cursors, handlers, recursion, dynamic SQL,
   routine functions, `OUT`/`INOUT`, packages, and server diagnostics surfaces.
3. Prove rejected procedure bodies do not leave partial catalog entries.
4. Improve diagnostics only where needed for stable acceptance.
5. Coordinate executor/catalog integration through review if needed.

## Definition of Done

- Procedure body diagnostics are stable and covered.
- Unsupported stored-program syntax remains rejected before partial execution.
- `zig build test` passes.

## Activity Log

- 2026-06-04T18:28:38Z – codex:gpt-5:implementer-ivan:implementer – WP04 implementation: added procedure diagnostics acceptance coverage, expanded procedure-body rejection cases, fixed unsupported SQL statement rejection ownership, and proved rejected creates leave procedure names reusable. Validation: zig build test; procedure-control-flow fixture smoke; zig fmt --check; git diff --check.
- 2026-06-04T18:28:58Z – codex:gpt-5:implementer-ivan:implementer – WP04 review passed: unsupported procedure surfaces reject cleanly, rejected creates leave no partial catalog entries, loop cap diagnostics are stable, and the ownership fix is covered.
