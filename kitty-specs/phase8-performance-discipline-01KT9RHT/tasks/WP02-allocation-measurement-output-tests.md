---
work_package_id: WP02
title: Allocation Measurement and Output Tests
dependencies:
- WP01
requirement_refs:
- FR-004
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
- T004
- T005
- T006
agent_profile: implementer-ivan
authoritative_surface: src/cli/benchmark_metrics.zig
execution_mode: code_change
owned_files:
- src/cli/benchmark_metrics.zig
- tests/integration/benchmark_output_acceptance.zig
role: implementer
tags:
- phase8
- benchmark
- allocation
agent: "codex:gpt-5:implementer-ivan:implementer"
shell_pid: "4043082"
---

# Work Package Prompt: WP02 - Allocation Measurement and Output Tests

## Objective

Make allocation cost visible in benchmark metrics and add stable output-shape
tests that avoid machine-specific timing assertions.

## Tasks

1. Add explicit allocation counting helpers for benchmark workloads.
2. Include allocation count and byte fields in the structured metric output.
3. Add tests that validate metric names, counts, dimensions, JSON shape, and
   allocation fields without asserting absolute elapsed time.
4. Wire any helper modules into `src/lib.zig` or `build.zig` only if needed for
   tests; keep benchmark instrumentation explicit.

## Definition of Done

- Benchmark output includes allocation fields.
- Output-shape tests pass without timing fragility.
- `zig build test` passes.

## Activity Log

- 2026-06-05T00:37:30Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=4043082 – Implemented allocation-aware benchmark metrics in lane commit 91e8e42; verified zig build test, text allocation smoke, JSON allocation jq check, acceptance-smoke JSON allocation check, and git diff --check.
- 2026-06-05T00:39:36Z – codex:gpt-5:reviewer-renata:reviewer – Approved after reviewing WP02 allocation metrics diff. Validation: zig build test; text allocation-field smoke; JSON allocation-field jq check; git diff --check.
- 2026-06-05T01:16:59Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=4043082 – Done override: Accepted mission branch was fast-forwarded to main after Spec Kitty merge blocked on stale lane already integrated into the accepted branch.
