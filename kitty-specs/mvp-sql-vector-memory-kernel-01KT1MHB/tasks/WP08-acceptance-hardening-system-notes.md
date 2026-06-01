---
work_package_id: WP08
title: Acceptance Hardening and Spec Kitty Notes
dependencies:
- WP01
- WP02
- WP03
- WP04
- WP05
- WP06
- WP07
requirement_refs:
- FR-011
- FR-016
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: kitty/mission-mvp-sql-vector-memory-kernel-01KT1MHB
base_commit: 16d861c3b494946faac7302573d3d78b7d0bc4fd
created_at: '2026-06-01T16:19:57.294840+00:00'
subtasks:
- T030
- T031
- T032
- T033
agent: "codex:gpt-5:reviewer-renata:reviewer"
shell_pid: "1166952"
history:
- timestamp: '2026-06-01T13:10:41Z'
  agent: codex
  action: Prompt generated via Spec Kitty tasks planning
agent_profile: reviewer-renata
authoritative_surface: src/lib.zig
execution_mode: code_change
model: ''
owned_files:
- build.zig
- src/lib.zig
- tests/integration/**
- docs/spec-kitty-system-notes.md
role: reviewer
tags: []
---

# Work Package Prompt: WP08 - Acceptance Hardening and Spec Kitty Notes

## ⚡ Do This First: Load Agent Profile

Use the `/ad-hoc-profile-load` skill to load the agent profile specified in the frontmatter, and behave according to its guidance before parsing the rest of this prompt.

- **Profile**: `reviewer-renata`
- **Role**: `reviewer`
- **Agent/tool**: `codex`

If no profile is specified, run `spec-kitty profiles list` and select the best match for this work package's `task_type` and `authoritative_surface`.

---

## Objective

Integrate the milestone, wire exports/build tests, run acceptance, and keep the
Spec Kitty system issue log actionable for upstream reporting.

Implementation command:

```
spec-kitty agent action implement WP08 --agent codex
```

## Context

This is the final hardening work package and depends on every implementation
package. It may wire module exports and integration tests, but it should not
rewrite earlier package internals unless acceptance fails and the fix is small
and clearly necessary.

### Subtask T030: Wire library exports and build/test integration

**Purpose**: Make all new modules visible to `zig build test`.

**Steps**:

1. Update `src/lib.zig` to export new `sql`, `db`, and `vector` modules.
2. Update `build.zig` only if extra test artifacts or benchmark wiring are
   necessary.
3. Add `refAllDecls` or equivalent coverage for new modules where appropriate.
4. Keep the public API coherent for embedded callers.

**Files**: `src/lib.zig`, `build.zig`

**Validation**: `zig build test`.

### Subtask T031: Add end-to-end acceptance tests

**Purpose**: Prove the pieces work together.

**Steps**:

1. Create `tests/integration/` tests or fixtures if the build structure supports
   separate integration files.
2. Cover create table, insert, select, transaction rollback, transaction commit,
   vector insert/search, persistence reopen, view query, and procedure call.
3. Prefer small deterministic datasets.

**Files**: `tests/integration/**`, `build.zig`

**Validation**: `zig build test`.

### Subtask T032: Run acceptance commands and fix integration gaps

**Purpose**: Bring the mission to a releasable state.

**Steps**:

1. Run `zig build test`.
2. Run the existing `check-sql` smoke command from the spec.
3. Run full reference corpus classification.
4. Run the benchmark command.
5. Fix small integration gaps within owned files, or report blockers with exact
   failing command output if a fix belongs to another WP.

**Files**: `src/lib.zig`, `build.zig`, `tests/integration/**`

**Validation**: all acceptance commands pass or blockers are documented.

### Subtask T033: Keep Spec Kitty system notes report-ready

**Purpose**: Preserve tooling feedback for Rebert.

**Steps**:

1. Update `docs/spec-kitty-system-notes.md` with any additional Spec Kitty
   warnings, failed commands, workarounds, and impact.
2. Separate project implementation failures from Spec Kitty system issues.
3. Include enough command detail for someone else to reproduce.

**Files**: `docs/spec-kitty-system-notes.md`

**Validation**: notes include status, command, observation, impact, workaround,
and report-readiness.

## Definition of Done

- `zig build test` passes.
- CLI acceptance commands pass.
- Integration tests cover the end-to-end kernel path.
- Spec Kitty system notes are current.
- No broad rewrites outside owned files are introduced.

## Risks

- Late integration may expose ownership conflicts. Fix the smallest surface
  needed or send the WP back with precise notes.
- The acceptance package can become a dumping ground. Keep changes focused on
  wiring, tests, and documented issues.

## Reviewer Guidance

Review the final user-visible behavior, acceptance commands, and Spec Kitty
notes. This package decides whether the milestone is ready to merge.

## Activity Log

- 2026-06-01T16:27:55Z – codex – shell_pid=1166952 – WP08 lane 9fdea7a; validation passed: zig build test, check-sql smoke, full reference corpus classification, benchmark, CLI execute smoke, git diff --check.
- 2026-06-01T16:28:19Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Started review via action command
- 2026-06-01T16:30:19Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Review passed. Re-ran zig build test, check-sql smoke, full reference corpus classification, benchmark, CLI execute smoke, and diff whitespace check from lane 9fdea7a/cfa45b5.
- 2026-06-01T16:43:24Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Mission merged to main in squash commit 0488cdb after manual resolution of Spec Kitty add/add artifact conflicts. | Done override: Manual squash merge completed in main commit 0488cdb after spec-kitty merge reached final mission-to-main step and conflicted only on add/add docs/acceptance artifacts.
