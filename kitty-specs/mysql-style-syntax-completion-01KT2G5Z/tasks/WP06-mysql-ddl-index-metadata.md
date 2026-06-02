---
work_package_id: WP06
title: MySQL DDL Compatibility and Index Metadata
dependencies:
- WP03
requirement_refs:
- FR-013
- FR-018
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
base_commit: 63e35c3125da5e0395e826be1fafe40bf93fc013
created_at: '2026-06-02T00:23:02.087912+00:00'
subtasks: []
shell_pid: '1166952'
history: []
agent_profile: implementer-ivan
authoritative_surface: src/db/catalog.zig
execution_mode: code_change
owned_files:
- src/db/catalog.zig
- src/db/ddl.zig
- tests/integration/ddl_acceptance.zig
role: implementer
tags: []
---

# WP06 - MySQL DDL Compatibility and Index Metadata

## Objective

Accept common application-schema DDL while preserving explicit rejection of
server or storage-engine surfaces.

## Tasks

1. Parse `CREATE TABLE IF NOT EXISTS` and `DROP TABLE IF EXISTS` semantics.
2. Store column nullability, default values, primary-key metadata, and
   auto-increment metadata.
3. Parse ordinary `INDEX`/`KEY` definitions into catalog metadata.
4. Reject unsupported table options such as `ENGINE=` through policy/diagnostic
   paths.
5. Add tests for compatible DDL and rejected legacy/server DDL.
6. Coordinate parser integration edits through review once catalog metadata is
   ready.

## Definition of Done

- Practical MySQL DDL from adapted fixtures parses and executes.
- Ordinary indexes are catalog-visible metadata, even if not optimizer-active.
- Explicit non-goals remain loudly rejected.
- `zig build test` passes.

## Activity Log

- 2026-06-02T00:36:01Z – unknown – shell_pid=1166952 – Ready for review: mysql-style DDL metadata is wired through parser/catalog/executor/persistence. Validation: zig build test exit 0; zig fmt --check diff-scoped exit 0; CLI execute smoke exit 0.
- 2026-06-02T00:38:50Z – unknown – shell_pid=1166952 – Review passed manually: lane-f after rebase satisfies WP06 DDL acceptance criteria. Verified parser/catalog/executor/persistence integration, DDL policy rejection, zig build test exit 0 before and after rebase, diff-scoped zig fmt --check exit 0, and CLI execute smoke exit 0.
- 2026-06-02T00:39:49Z – unknown – shell_pid=1166952 – Forced done because lane-f patch was already cherry-picked to main as ed79ba4 and the rebased lane has no commits beyond main. Final validation: zig build test exit 0; CLI DDL/autoincrement/default smoke exit 0.
