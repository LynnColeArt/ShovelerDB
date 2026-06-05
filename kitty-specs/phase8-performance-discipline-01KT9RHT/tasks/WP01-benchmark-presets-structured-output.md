---
work_package_id: WP01
title: Benchmark Presets and Structured Output
dependencies: []
requirement_refs:
- FR-002
- FR-003
- FR-008
- FR-012
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
base_commit: d0073eb7ceb53839c6ac90b70f182ce9604d8238
created_at: '2026-06-04T16:55:00+00:00'
subtasks:
- T001
- T002
- T003
agent_profile: implementer-ivan
authoritative_surface: src/cli/benchmark.zig
execution_mode: code_change
owned_files:
- src/cli/benchmark.zig
- src/cli/commands.zig
role: implementer
tags:
- phase8
- benchmark
agent: "codex:gpt-5:reviewer-renata:reviewer"
shell_pid: "3361848"
---

# Work Package Prompt: WP01 - Benchmark Presets and Structured Output

## Objective

Add stable benchmark presets and structured output while preserving the existing
developer-friendly text report.

## Tasks

1. Add benchmark preset parsing for at least `local-smoke` and
   `acceptance-smoke`.
2. Add a small metric schema that can render text and JSON.
3. Add `--format json` or equivalent option handling.
4. Preserve existing metric names, including Phase 6 concurrency metrics.
5. Keep behavior changes scoped to the CLI benchmark surface.

## Definition of Done

- Existing benchmark command still works.
- Preset commands work.
- JSON output is valid enough for later tests to parse.
- `zig build test` passes.

## Activity Log

- 2026-06-05T00:24:54Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=3361848 – Started review via action command
