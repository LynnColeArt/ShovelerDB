---
work_package_id: WP04
title: Methodology and Warn-Only Baselines
dependencies:
- WP01
- WP02
- WP03
requirement_refs:
- FR-001
- FR-010
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
- T011
- T012
- T013
agent_profile: implementer-ivan
authoritative_surface: docs/performance.md
execution_mode: code_change
owned_files:
- docs/performance.md
- docs/project-plan.md
- docs/performance-baselines.json
role: implementer
tags:
- phase8
- docs
- benchmark
agent: "codex:gpt-5:implementer-ivan:implementer"
shell_pid: "4095245"
---

# Work Package Prompt: WP04 - Methodology and Warn-Only Baselines

## Objective

Document how ShovelerDB benchmarks should be run and add warn-only baseline
guidance without creating brittle hard timing gates.

## Tasks

1. Add `docs/performance.md` with methodology, presets, output fields,
   limitations, and interpretation guidance.
2. Add a small baseline or threshold artifact in warn-only mode.
3. Refresh `docs/project-plan.md` so Phase 8 status is truthful.
4. Document why hard CI timing gates remain deferred.

## Definition of Done

- Performance docs explain local and acceptance benchmark commands.
- Warn-only baseline artifact exists and is documented.
- Roadmap reflects the new benchmark discipline.
- `zig build test` passes.

## Activity Log

- 2026-06-05T01:00:33Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=4095245 – Implemented performance methodology docs and warn-only baseline artifact in lane commit f61a6bd; verified jq baseline schema/counts, zig build test, local-smoke JSON counts against docs/performance-baselines.json, and git diff --check.
