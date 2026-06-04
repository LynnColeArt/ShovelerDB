---
work_package_id: WP02
title: View Persistence and Fixture Coverage
dependencies:
- WP01
requirement_refs:
- FR-001
- FR-004
- FR-009
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
- T004
- T005
- T006
agent_profile: implementer-ivan
authoritative_surface: tests/fixtures/mariadb-adapted
execution_mode: code_change
owned_files:
- src/db/persistence.zig
- tests/integration/view_persistence_acceptance.zig
- tests/fixtures/mariadb-adapted/view-rich.md
- docs/reference-corpus-snapshot.md
role: implementer
tags:
- phase7
- views
- fixtures
agent: "codex:gpt-5:implementer-ivan:implementer"
---

# Work Package Prompt: WP02 - View Persistence and Fixture Coverage

## Objective

Prove rich views survive the embedded snapshot/reopen path and promote useful
view reference behavior into adapted fixture coverage.

## Tasks

1. Add integration coverage for creating a view, saving/checkpointing the
   database, reopening it, and executing the view.
2. Ensure view definitions persist with enough query metadata to remain
   executable after reopen.
3. Add a richer adapted view fixture descriptor when it provides behavior not
   already covered by `view-basic.md` or `query-syntax.md`.
4. Refresh view-related reference notes without claiming full MariaDB view
   metadata compatibility.
5. Coordinate any executor/catalog wiring through review.

## Definition of Done

- Reopen tests prove executable persisted views.
- Adapted fixture coverage documents useful MariaDB view behavior and rejected
  server metadata.
- `zig build test` passes.

## Activity Log

- 2026-06-04T18:18:50Z – codex:gpt-5:implementer-ivan:implementer – Moved to for_review
