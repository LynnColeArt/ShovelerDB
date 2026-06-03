---
work_package_id: WP01
title: Concurrency Contract and Harness
dependencies: []
requirement_refs:
- FR-001
- FR-011
- FR-013
- FR-014
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
base_commit: 2b1ad296f9ffa7b36f303b7fbb0584ba26c5c02e
created_at: '2026-06-03T03:12:54.764002+00:00'
subtasks:
- T001
- T002
- T003
agent: ''
shell_pid: '1166952'
history:
- timestamp: '2026-06-02T21:29:15Z'
  agent: codex
  action: Prompt generated for Phase 6 scalable concurrency planning.
agent_profile: implementer-ivan
authoritative_surface: docs/concurrency.md
execution_mode: code_change
model: ''
owned_files:
- docs/concurrency.md
- docs/project-plan.md
- src/db/concurrency.zig
- tests/integration/concurrency_contract_acceptance.zig
- build.zig
- src/lib.zig
role: implementer
tags:
- phase6
- concurrency
---

# Work Package Prompt: WP01 - Concurrency Contract and Harness

## Objective

Define the Phase 6 concurrency contract and create the first dedicated
concurrency acceptance harness.

## Tasks

1. Update `docs/concurrency.md` with concrete session, snapshot, commit queue,
   backpressure, checkpoint, and vector overlay semantics.
2. Update `docs/project-plan.md` to point Phase 6 at this mission and preserve
   Phase 9 connector scope.
3. Add a small `src/db/concurrency.zig` module for typed diagnostics and shared
   concurrency configuration.
4. Add `tests/integration/concurrency_contract_acceptance.zig` with skeleton
   tests for the public contract.
5. Wire the new module/test into `src/lib.zig` and `build.zig`.

## Definition of Done

- `zig build test` passes.
- Concurrency contract docs describe what later WPs must preserve.
- The new test harness compiles and can be extended by later WPs.
