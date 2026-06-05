---
work_package_id: WP04
title: Diagnostics and ABI Acceptance Smoke
dependencies:
- WP01
- WP02
- WP03
requirement_refs:
- FR-007
- FR-008
- FR-010
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
created_at: '2026-06-05T01:59:00+00:00'
subtasks:
- T010
- T011
- T012
agent_profile: implementer-ivan
authoritative_surface: tests/integration/abi_acceptance.zig
execution_mode: code_change
owned_files:
- src/abi/c_api.zig
- src/abi/diagnostics.zig
- src/lib.zig
- tests/integration/abi_acceptance.zig
- build.zig
role: implementer
tags:
- phase9
- abi
- diagnostics
- tests
assignee: "codex:gpt-5:implementer-ivan:implementer"
agent: "codex:gpt-5:implementer-ivan:implementer"
---

# Work Package Prompt: WP04 - Diagnostics and ABI Acceptance Smoke

## Objective

Make the ABI verifiably connector-safe by centralizing diagnostic mapping and
adding an acceptance smoke for the full embedded lifecycle.

## Tasks

1. Add `src/abi/diagnostics.zig` mapping internal errors to stable ABI status
   codes and messages.
2. Add `tests/integration/abi_acceptance.zig` covering open/create, SQL DDL,
   transaction DML, SELECT iteration, vector ranking, typed errors,
   checkpoint/close/reopen, and release cleanup.
3. Wire the ABI integration test into `zig build test` via `build.zig`.
4. Add negative checks for invalid handles and at least one typed SQL/vector
   diagnostic.

## Definition of Done

- ABI diagnostics are stable enum values, not message parsing.
- Acceptance smoke covers the connector lifecycle future language packages need.
- No server/network/auth/plugin lifecycle appears.
- `zig build test` passes.

## Activity Log

- 2026-06-05T02:52:43Z – codex:gpt-5:implementer-ivan:implementer – Moved to in_progress
