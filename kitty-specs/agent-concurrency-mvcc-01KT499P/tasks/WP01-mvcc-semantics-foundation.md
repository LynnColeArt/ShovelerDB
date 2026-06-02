---
work_package_id: WP01
title: MVCC Semantics Foundation
dependencies: []
requirement_refs:
- FR-001
- FR-002
- FR-003
- FR-004
- FR-005
- FR-006
- FR-007
- FR-008
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were repaired on main after the implementation slice had already landed; completed changes are already on main as 865eb05.
base_branch: main
base_commit: 865eb05f6c31d42a90a5f680dc44ba00e623f535
created_at: '2026-06-02T15:48:00Z'
subtasks:
- T001
- T002
- T003
- T004
- T005
- T006
- T007
- T008
agent: "codex:gpt-5:implementer-ivan:implementer"
shell_pid: "4072697"
assignee: "codex:gpt-5:implementer-ivan"
history:
- timestamp: '2026-06-02T15:48:00Z'
  agent: codex:gpt-5:implementer-ivan:implementer
  action: Prompt backfilled after direct implementation landing so Spec Kitty runtime could track the completed MVCC slice.
agent_profile: implementer-ivan
authoritative_surface: src/db/executor.zig
execution_mode: code_change
model: ''
owned_files:
- src/db/executor.zig
- src/db/transaction.zig
- src/cli/benchmark.zig
- docs/project-plan.md
- docs/acceptance-agent-concurrency-mvcc.md
- kitty-specs/agent-concurrency-mvcc-01KT499P/**
role: implementer
tags:
- mvcc
- concurrency
- benchmark
---

# Work Package Prompt: WP01 - MVCC Semantics Foundation

## Objective

Establish the first agent-shaped concurrency layer for ShovelerDB: stable
reader snapshots at `BEGIN`, serialized writer commit sequencing, and benchmark
evidence for interleaved reader/writer workloads.

## Scope

1. Capture session snapshots for committed table rows.
2. Route reads through transaction overlays, then session snapshots, then the
   current committed store.
3. Track commit sequence numbers for deterministic writer order.
4. Keep snapshot row stores attached to owned table metadata.
5. Preserve read-your-writes behavior for writer sessions.
6. Add tests proving stable readers and ordered writer commits.
7. Extend the benchmark CLI with `snapshot_read_write`.
8. Update roadmap and acceptance documentation.

## Definition of Done

- `zig build test` passes.
- `zig build run -- benchmark --rows 20 --vectors 8 --dimensions 3 --operations 5`
  passes and reports `snapshot_read_write`.
- A reader transaction started before a writer commit continues to see its
  original snapshot until it commits or rolls back.
- Two writer transactions begun before either commit can commit in sequence and
  leave both rows visible.
- Acceptance evidence is recorded in
  `docs/acceptance-agent-concurrency-mvcc.md`.

## Landing Evidence

This WP was implemented directly on `main` as commit
`865eb05 feat: Add first MVCC concurrency slice`, then this prompt was
backfilled so Spec Kitty runtime can represent the completed work.

## Activity Log

- 2026-06-02T15:48:20Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=4072697 – Backfilled workflow state for MVCC slice already landed on main as 865eb05.
