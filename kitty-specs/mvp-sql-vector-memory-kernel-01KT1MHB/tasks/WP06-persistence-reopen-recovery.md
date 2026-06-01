---
work_package_id: WP06
title: Persistence, Reopen, and Recovery
dependencies:
- WP02
- WP03
requirement_refs:
- FR-010
- FR-011
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: kitty/mission-mvp-sql-vector-memory-kernel-01KT1MHB
base_commit: d169c3a431020c83716a60865afdd464e2a514ff
created_at: '2026-06-01T15:36:06.078596+00:00'
subtasks:
- T022
- T023
- T024
- T025
agent: "codex:gpt-5:reviewer-renata:reviewer"
shell_pid: "1166952"
history:
- timestamp: '2026-06-01T13:10:41Z'
  agent: codex
  action: Prompt generated via Spec Kitty tasks planning
agent_profile: implementer-ivan
authoritative_surface: src/db/
execution_mode: code_change
model: ''
owned_files:
- src/db/persistence.zig
- src/db/database.zig
role: implementer
tags: []
---

# Work Package Prompt: WP06 - Persistence, Reopen, and Recovery

## ⚡ Do This First: Load Agent Profile

Use the `/ad-hoc-profile-load` skill to load the agent profile specified in the frontmatter, and behave according to its guidance before parsing the rest of this prompt.

- **Profile**: `implementer-ivan`
- **Role**: `implementer`
- **Agent/tool**: `codex`

If no profile is specified, run `spec-kitty profiles list` and select the best match for this work package's `task_type` and `authoritative_surface`.

---

## Objective

Define the embedded database open/close surface and the MVP durable format for
committed state. A simple atomic snapshot is acceptable if it is versioned,
validated, and tested.

Implementation command:

```
spec-kitty agent action implement WP06 --agent codex
```

## Context

The user wants filesystem-first embedded operation, not a daemon. This package
owns persistence and the public database object surface under `src/db/`.

### Subtask T022: Define durable file format and version checks

**Purpose**: Make on-disk data explicit and reject invalid formats loudly.

**Steps**:

1. Create `src/db/persistence.zig`.
2. Define a small file header with magic, version, and payload length/check
   metadata if practical.
3. Define serialization for catalog and row-store committed state.
4. Reject unknown versions and invalid headers.

**Files**: `src/db/persistence.zig`

**Validation**: unit tests for header encode/decode and invalid version.

### Subtask T023: Implement atomic snapshot write and reopen

**Purpose**: Persist committed state safely enough for MVP.

**Steps**:

1. Write snapshots through a temporary file plus rename or equivalent staged
   filesystem pattern.
2. Flush/sync where practical with Zig stdlib APIs.
3. Implement reopen from the latest valid snapshot.
4. Keep partial writes from being silently accepted.

**Files**: `src/db/persistence.zig`

**Validation**: tests write a database, reopen it, and compare catalog/rows.

### Subtask T024: Add invalid/truncated file recovery tests

**Purpose**: Prove persistence refuses bad data.

**Steps**:

1. Add tests for empty file, bad magic, unsupported version, and truncated
   payload.
2. Assert typed persistence errors.
3. Ensure corrupt files do not mutate in-memory state during failed open.

**Files**: `src/db/persistence.zig`

**Validation**: direct Zig tests with temp directories/files.

### Subtask T025: Add embedded database open/close API surface

**Purpose**: Give the CLI and callers a small database object.

**Steps**:

1. Create `src/db/database.zig`.
2. Expose open/create/close or init/deinit style APIs.
3. Tie database object to catalog, committed row store, and persistence path.
4. Leave execute/query convenience methods as thin wrappers if executor is
   available; otherwise document integration points for WP08.

**Files**: `src/db/database.zig`

**Validation**: tests open a new database path, write committed state through
persistence, close, reopen, and read it back.

## Definition of Done

- Durable format has magic/version validation.
- Committed state can be written and reopened.
- Invalid/truncated files fail loudly.
- Embedded database API exists.
- No files outside `src/db/persistence.zig` and `src/db/database.zig` are modified.

## Risks

- Atomicity is platform-sensitive. Use Zig stdlib capabilities and document
  any remaining limitation.
- Serialization can overfit current structs. Include versioning from the start.

## Reviewer Guidance

Review crash-conscious write ordering, validation behavior, and whether failed
opens leave state untouched.

## Activity Log

- 2026-06-01T15:46:46Z – codex – shell_pid=2518125 – Ready for review: lane-f 008903f; zig test src/db/persistence.zig; zig test src/db/database.zig; zig build test; git diff --check.
- 2026-06-01T15:47:07Z – codex:gpt-5:reviewer-renata:reviewer – shell_pid=1166952 – Started review via action command
