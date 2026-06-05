---
work_package_id: WP01
title: ABI Contract and Roadmap Docs
dependencies: []
requirement_refs:
- FR-001
- FR-002
- FR-009
- FR-011
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
created_at: '2026-06-05T01:59:00+00:00'
subtasks:
- T001
- T002
- T003
agent_profile: implementer-ivan
authoritative_surface: docs/embedding-abi.md
execution_mode: code_change
owned_files:
- docs/embedding-abi.md
- include/shovelerdb.h
- docs/project-plan.md
- README.md
role: implementer
tags:
- phase9
- abi
- docs
assignee: "codex:gpt-5:implementer-ivan:implementer"
agent: "codex:gpt-5:implementer-ivan:implementer"
---

# Work Package Prompt: WP01 - ABI Contract and Roadmap Docs

## Objective

Define the connector-facing ABI contract before implementation begins, and make
the public roadmap truthful about Phase 9 being active for ABI foundation work.

## Tasks

1. Add `docs/embedding-abi.md` documenting ABI lifecycle, ownership, result
   access, vector representation, diagnostic mapping, thread/concurrency
   expectations, and connector fixture expectations.
2. Add `include/shovelerdb.h` with the first C ABI surface: version constants,
   opaque handles, status/result/value enums, open/close/checkpoint,
   execute/release, result metadata, value accessors, and diagnostic helpers.
3. Refresh `README.md` and `docs/project-plan.md` so Phase 9 is active only for
   ABI foundation work, not for full language connector packages.

## Definition of Done

- Header and docs describe the same ABI surface.
- Docs preserve the no-server, no-replication, no-plugin product boundary.
- Roadmap clearly says full language connectors are follow-up work.
- `zig build test` passes.

## Activity Log

- 2026-06-05T02:10:17Z – codex:gpt-5:implementer-ivan:implementer – WP01 implementation started on lane-a after protected-main workspace recovery.
- 2026-06-05T02:10:49Z – codex:gpt-5:implementer-ivan:implementer – Implementation commit 92afadb defines docs/embedding-abi.md, include/shovelerdb.h, and roadmap status updates; zig build test and C99 header syntax check pass.
