---
work_package_id: WP01
title: Roadmap Truth and MTR-Lite Skeleton
dependencies: []
requirement_refs:
- FR-001
- FR-002
- FR-017
- FR-018
- FR-020
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
subtasks: []
shell_pid: 'unknown'
history: []
agent_profile: implementer-ivan
authoritative_surface: docs/project-plan.md
execution_mode: code_change
owned_files:
- docs/project-plan.md
- docs/sql-dialect.md
- docs/test-import-strategy.md
- docs/reference-corpus-snapshot.md
- src/mariadb/mtr_lite.zig
- src/cli/commands.zig
role: implementer
tags: []
agent: "codex"
---

# WP01 - Roadmap Truth and MTR-Lite Skeleton

## Objective

Make the roadmap reflect the completed MVP kernel and create the first runner
surface for executable adapted MariaDB fixtures.

## Tasks

1. Update project and dialect docs so completed phases are marked complete and
   remaining syntax work is concrete.
2. Add a small MTR-lite runner module or CLI path that can parse accepted SQL
   fragments from adapted fixtures.
3. Report unsupported MTR directives with stable reasons instead of ignoring
   them.
4. Add tests or fixture descriptors proving the skeleton can accept a simple
   transaction/vector fixture.

## Definition of Done

- Docs no longer imply completed MVP work is merely planned.
- MTR-lite has a callable Zig surface or CLI surface.
- Unsupported directives have typed diagnostics.
- `zig build test` passes.

## Activity Log

- 2026-06-01T21:25Z - codex - Updated roadmap/dialect/reference docs and added
  `src/mariadb/mtr_lite.zig` plus `run-adapted-test` CLI support. Validation:
  `zig build test`; all existing adapted fixture descriptors executed through
  MTR-lite.
- 2026-06-01T21:18:52Z – codex – Done override: Implemented directly on main before lane allocation; validated with zig build test and adapted fixture CLI smokes.
