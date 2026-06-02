---
work_package_id: WP08
title: Adapted MariaDB Fixture Execution
dependencies:
- WP01
- WP02
- WP04
- WP05
- WP06
- WP07
requirement_refs:
- FR-002
- FR-017
- FR-018
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
subtasks: []
shell_pid: '1166952'
history: []
agent_profile: implementer-ivan
authoritative_surface: tests/fixtures/mariadb-adapted/query-syntax.md
execution_mode: code_change
owned_files:
- tests/fixtures/mariadb-adapted/query-syntax.md
- tests/fixtures/mariadb-adapted/procedure-control-flow.md
- tests/fixtures/mariadb-adapted/grouping-aggregates.md
- docs/reference-corpus-syntax-refresh.md
role: implementer
tags: []
agent: "codex:gpt-5:implementer-ivan:implementer"
---

# WP08 - Adapted MariaDB Fixture Execution

## Objective

Promote accepted reference fixtures into executable regression coverage.

## Tasks

1. Convert newly supported syntax examples into adapted fixture descriptors.
2. Execute accepted fixture SQL through MTR-lite.
3. Record rejected/deferred reference cases with reasons.
4. Refresh `docs/reference-corpus-snapshot.md`.

## Definition of Done

- At least one accepted adapted fixture is executed by the test suite.
- Unsupported harness directives are reported, not skipped invisibly.
- Corpus docs match the current classified and executable counts.
- `zig build test` passes.

## Activity Log

- 2026-06-02T12:05:42Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=1166952 – Ready for review: promoted query syntax, procedure control-flow, and grouping/aggregate adapted MariaDB descriptors; wired them into zig build test through MTR-lite; refreshed reference corpus docs and explicit deferrals. Validation: zig build test exit 0; zig fmt --check diff-scoped exit 0; git diff --check exit 0; run-adapted-test query/procedure/grouping fixtures exit 0. Lane commit 87e42ca.
- 2026-06-02T12:10:42Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=1166952 – Manual review approved because canonical review failed with LANE_AUTO_REBASE_FAILED on status.events.jsonl. Reviewed lane-h diff at rebased head 70a0081: no findings. Validation in lane: zig build test exit 0; zig fmt --check build.zig tests/adapted_fixture_acceptance.zig exit 0; git diff --check main..HEAD exit 0; run-adapted-test query/procedure/grouping fixtures exit 0 with expected statement/error counts.
