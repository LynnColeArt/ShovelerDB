---
work_package_id: WP02
title: Handle Lifecycle and SQL Execution
dependencies:
- WP01
requirement_refs:
- FR-003
- FR-004
- FR-006
- FR-010
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
created_at: '2026-06-05T01:59:00+00:00'
subtasks:
- T004
- T005
- T006
agent_profile: implementer-ivan
authoritative_surface: src/abi/c_api.zig
execution_mode: code_change
owned_files:
- src/abi/c_api.zig
- src/abi/handles.zig
- src/lib.zig
role: implementer
tags:
- phase9
- abi
- execution
agent: "codex:gpt-5:implementer-ivan:implementer"
---

# Work Package Prompt: WP02 - Handle Lifecycle and SQL Execution

## Objective

Implement the first opaque ABI handles and SQL execution bridge without exposing
internal Zig allocator-owned structures to foreign callers.

## Tasks

1. Add `src/abi/c_api.zig` and `src/abi/handles.zig` with database/result
   handle types, allocator ownership, and idempotent cleanup.
2. Implement open-or-create, close, checkpoint, execute SQL, result release,
   and last-status/diagnostic plumbing according to `include/shovelerdb.h`.
3. Bridge SQL execution through existing `src/db/executor.zig` behavior and
   persistence through the existing snapshot/checkpoint path.
4. Wire the ABI module into `src/lib.zig`.

## Definition of Done

- ABI handles are opaque to foreign callers.
- SQL execution can return ok, mutation count, or result-set handles.
- Cleanup is explicit and idempotent where documented.
- Existing `zig build test` remains green.

## Activity Log

- 2026-06-05T02:34:32Z – codex:gpt-5:implementer-ivan:implementer – Moved to for_review
- 2026-06-05T02:37:56Z – codex:gpt-5:reviewer-renata:reviewer – Review passed: ABI handles and SQL execution match WP02 scope; review fix covered failed initial checkpoint cleanup. Validation: zig build test, zig fmt --check, git diff --check, C header syntax compile.
- 2026-06-05T02:39:25Z – codex:gpt-5:implementer-ivan:implementer – Done: WP02 merged to main with ABI handle lifecycle, SQL execution bridge, and checkpoint-failure ownership fix. Validation on main: zig build test, zig fmt --check, git diff --check, C header syntax compile.
