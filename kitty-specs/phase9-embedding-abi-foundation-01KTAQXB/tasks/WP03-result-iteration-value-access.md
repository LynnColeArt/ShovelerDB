---
work_package_id: WP03
title: Result Iteration and Value Access
dependencies:
- WP01
- WP02
requirement_refs:
- FR-005
- FR-006
- FR-010
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
created_at: '2026-06-05T01:59:00+00:00'
subtasks:
- T007
- T008
- T009
agent_profile: implementer-ivan
authoritative_surface: src/abi/result.zig
execution_mode: code_change
owned_files:
- src/abi/c_api.zig
- src/abi/handles.zig
- src/abi/result.zig
- src/abi/value_access.zig
- src/lib.zig
role: implementer
tags:
- phase9
- abi
- results
---

# Work Package Prompt: WP03 - Result Iteration and Value Access

## Objective

Expose connector-safe result metadata, row iteration, and typed value accessors
for ABI-owned result handles.

## Tasks

1. Add result metadata helpers for result kind, mutation count, row count,
   column count, and column names.
2. Add value accessors for null, integer, float, boolean, text, blob, and
   float32 vector values.
3. Ensure text/blob/vector pointers remain valid only for the documented result
   lifetime and are never borrowed from internal row-store slices.
4. Add lifecycle tests for repeated release and invalid result/value access.

## Definition of Done

- ABI result handles expose all accepted value kinds.
- Vector access includes float32 element type and dimension.
- Caller ownership rules match `docs/embedding-abi.md`.
- Existing `zig build test` remains green.
