---
work_package_id: WP03
title: Query Syntax AST Generalization
dependencies:
- WP02
requirement_refs:
- FR-006
- FR-007
- FR-008
- FR-010
- FR-018
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
subtasks: []
history: []
agent_profile: implementer-ivan
authoritative_surface: src/sql/
execution_mode: code_change
owned_files:
- src/sql/ast.zig
- src/sql/parser.zig
- src/sql/policy.zig
role: implementer
tags: []
---

# WP03 - Query Syntax AST Generalization

## Objective

Widen the parser and AST so SELECT can represent MySQL-style aliases,
qualified identifiers, derived tables, CTEs, and joins without executor string
guessing.

## Tasks

1. Add projection nodes with optional aliases.
2. Add qualified identifiers for `table.column` and `alias.column`.
3. Replace the single `SelectStatement.from` table string with a row-source
   AST covering base sources, derived sources, and joins.
4. Add non-recursive CTE declarations to `SelectStatement`.
5. Parse `AS` aliases and MySQL implicit aliases where unambiguous.
6. Add parser tests for the spec examples.

## Definition of Done

- AST owns all new strings/child nodes safely.
- Parser tests cover aliases, qualified identifiers, joins, derived tables, and
  CTEs.
- Policy rejections for foreign keys/temp tables/server features still fire
  before parser work.
- `zig build test` passes.
