---
work_package_id: WP07
title: Reference Fixtures, CLI, and Benchmarks
dependencies:
- WP01
- WP02
- WP03
- WP04
- WP05
- WP06
requirement_refs:
- FR-012
- FR-013
- FR-014
- FR-015
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: kitty/mission-mvp-sql-vector-memory-kernel-01KT1MHB
base_commit: bbadee5f6d8eb0524dccb1601f569ea90aed7532
created_at: '2026-06-01T15:53:53.195203+00:00'
subtasks:
- T026
- T027
- T028
- T029
agent: "codex:gpt-5:reviewer-renata:reviewer"
shell_pid: "1166952"
history:
- timestamp: '2026-06-01T13:10:41Z'
  agent: codex
  action: Prompt generated via Spec Kitty tasks planning
agent_profile: curator-carla
authoritative_surface: src/cli/
execution_mode: code_change
model: ''
owned_files:
- src/main.zig
- src/cli/commands.zig
- src/cli/benchmark.zig
- tests/fixtures/mariadb-adapted/**
- docs/test-import-strategy.md
- docs/reference-corpus-snapshot.md
role: curator
tags: []
---

# Work Package Prompt: WP07 - Reference Fixtures, CLI, and Benchmarks

## ⚡ Do This First: Load Agent Profile

Use the `/ad-hoc-profile-load` skill to load the agent profile specified in the frontmatter, and behave according to its guidance before parsing the rest of this prompt.

- **Profile**: `curator-carla`
- **Role**: `curator`
- **Agent/tool**: `codex`

If no profile is specified, run `spec-kitty profiles list` and select the best match for this work package's `task_type` and `authoritative_surface`.

---

## Objective

Turn the engine into a usable development harness: CLI parse/execute/benchmark
commands, native MariaDB-derived fixtures, and updated reference-test docs.

Implementation command:

```
spec-kitty agent action implement WP07 --agent codex
```

## Context

This package is late because it depends on the parser, database, executor,
vectors, and persistence surfaces. It must not mutate `references/mariadb/`.

### Subtask T026: Add CLI parse/execute/benchmark command surfaces

**Purpose**: Keep ShovelerDB easy to smoke-test from the command line.

**Steps**:

1. Create `src/cli/commands.zig` for reusable command dispatch if useful.
2. Update `src/main.zig` to include parse and execute command surfaces.
3. Keep existing `check-sql`, `analyze-test`, and `classify-test` behavior.
4. Add clear usage text for new commands.

**Files**: `src/main.zig`, `src/cli/commands.zig`

**Validation**: CLI smoke commands for policy, parse, execute, and classify.

### Subtask T027: Promote MariaDB-derived native fixtures

**Purpose**: Convert reference evidence into native ShovelerDB tests.

**Steps**:

1. Create `tests/fixtures/mariadb-adapted/`.
2. Add at least four adapted fixture files or fixture descriptors.
3. Include source path, source intent, ShovelerDB adaptation, and removed
   unsupported MariaDB behavior.
4. Prefer vector, procedure, view, and autoincrement/deferred evidence from the
   spec.

**Files**: `tests/fixtures/mariadb-adapted/**`

**Validation**: fixture files are referenced by tests or docs and do not copy
unrelated reference corpus bulk.

### Subtask T028: Update reference-test docs and classification workflow

**Purpose**: Keep MariaDB evidence understandable.

**Steps**:

1. Update `docs/test-import-strategy.md` with the native-fixture promotion
   process.
2. Update `docs/reference-corpus-snapshot.md` if classifier output changes.
3. Document why policy-rejected tests are still useful evidence.
4. Keep the full corpus classifier command runnable.

**Files**: `docs/test-import-strategy.md`, `docs/reference-corpus-snapshot.md`

**Validation**: full corpus classification command still prints the summary.

### Subtask T029: Add scalar/vector benchmark reporting

**Purpose**: Start measuring the "screaming fast" goal in concrete terms.

**Steps**:

1. Create `src/cli/benchmark.zig`.
2. Add benchmark options for rows, vectors, dimensions, and operation count.
3. Report dataset size, elapsed time, and throughput.
4. Include insert, select/scan, commit/rollback, and exact vector scan timings
   as surfaces become available.

**Files**: `src/cli/benchmark.zig`, `src/main.zig`

**Validation**: `zig build run -- benchmark --rows 10000 --vectors 1000 --dimensions 128`
prints structured timing output or a clear usage/error if the command shape is
adjusted.

## Definition of Done

- CLI has parse/execute/benchmark surfaces.
- Existing reference analyzer/classifier commands still work.
- At least four native MariaDB-derived fixtures exist.
- Benchmark output includes dataset and throughput details.
- `references/mariadb/` is not mutated.

## Risks

- CLI can become a second API. Keep it a thin harness over library functions.
- Fixtures can accidentally imply full MariaDB compatibility. Document deltas.

## Reviewer Guidance

Review fixture provenance and CLI compatibility. Verify the classifier baseline
is still meaningful.

## Activity Log

- 2026-06-01T16:01:36Z – codex – shell_pid=2539739 – Ready for review: lane-g ef8075c; validation passed: zig build test; check-sql smoke; parse smoke; execute smoke; full corpus classify-test summary; benchmark --rows 10000 --vectors 1000 --dimensions 128; git diff --check.
- 2026-06-01T16:02:00Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Started review via action command
- 2026-06-01T16:03:07Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Review passed: WP07 commit ef8075c touches only owned CLI/docs/fixture files and leaves references/mariadb unchanged. Validation passed: zig build test; git diff --check; check-sql, parse, execute smokes; full corpus classify-test summary; benchmark --rows 10000 --vectors 1000 --dimensions 128.
