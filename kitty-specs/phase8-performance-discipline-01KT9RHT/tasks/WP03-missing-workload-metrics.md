---
work_package_id: WP03
title: Missing Workload Metrics
dependencies:
- WP01
- WP02
requirement_refs:
- FR-005
- FR-006
- FR-007
- FR-008
- FR-009
- FR-012
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: main
base_commit: d0073eb7ceb53839c6ac90b70f182ce9604d8238
created_at: '2026-06-04T16:55:00+00:00'
subtasks:
- T007
- T008
- T009
- T010
agent_profile: implementer-ivan
authoritative_surface: src/cli/benchmark_workloads.zig
execution_mode: code_change
owned_files:
- src/cli/benchmark_workloads.zig
- tests/integration/benchmark_workload_acceptance.zig
role: implementer
tags:
- phase8
- benchmark
- workloads
agent: "codex:gpt-5:implementer-ivan:implementer"
shell_pid: "4074153"
---

# Work Package Prompt: WP03 - Missing Workload Metrics

## Objective

Round out benchmark coverage for the product hot paths that are not currently
separate metrics.

## Tasks

1. Add a point-lookup metric distinct from full scans.
2. Add a hybrid filter/vector ranking metric that combines metadata filtering
   with vector ordering.
3. Add a persistence checkpoint/reopen benchmark smoke that preserves durable
   state safety.
4. Preserve and validate existing Phase 6 metrics in the new structured output.
5. Keep benchmark data setup deterministic and small enough for local smokes.

## Definition of Done

- New workload metrics appear in text and JSON output.
- Existing Phase 6 metrics still appear.
- Workload tests or smokes validate metric names/counts.
- `zig build test` passes.

## Activity Log

- 2026-06-05T00:50:45Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=4074153 – Implemented missing benchmark workload metrics in lane commit d1140cf; verified zig build test, text smoke with new and Phase 6 metric names, JSON jq metric/allocation check, acceptance-smoke JSON count check, git diff --check, and persistence smoke cleanup.
- 2026-06-05T00:55:18Z – codex:gpt-5:reviewer-renata:reviewer – Approved after reviewing WP03 lane commit d1140cf. Validation: zig build test; text and JSON workload metric smokes; acceptance-smoke JSON count check; git diff --check; persistence smoke cleanup.
