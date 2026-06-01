# Implementation Plan: MySQL-Style Syntax Completion

**Branch**: `main`
**Date**: 2026-06-01
**Spec**: `kitty-specs/mysql-style-syntax-completion-01KT2G5Z/spec.md`

## Summary

Finish the outstanding syntax and roadmap items exposed by the MVP kernel. The
work starts with the cheapest high-value gap, executable SQL function calls,
then widens the query model from single-table scans to row-source trees. After
that, grouping, DDL compatibility, procedure control flow, and runnable
MariaDB-derived fixtures become tractable without duplicating one-off logic in
the executor.

## Current Baseline

- Parser supports basic `CREATE TABLE`, `DROP TABLE`, `INSERT`, `SELECT`,
  `UPDATE`, `DELETE`, transactions, views, procedures, and `CALL`.
- Parser already represents function calls, vector literals, binary predicates,
  `ORDER BY`, and `LIMIT`.
- Executor handles single-table scans, simple predicates, projection,
  mutations, transactions, constrained views/procedures, persistence, and
  exact vector helper APIs.
- Executor currently rejects function-call expressions.
- `SelectStatement.from` is a single optional table name, which blocks aliases,
  joins, derived tables, and CTEs.
- Procedure storage currently treats the body as raw SQL and rejects control
  flow.
- Docs describe CTEs, derived tables, ordinary indexes, and richer procedure
  behavior as supported-by-design but not yet implemented.

## Architecture Direction

### 1. Truthful Roadmap and Runnable References

Update documentation first enough that future work is honest. Add an MTR-lite
execution path before expanding too much syntax so accepted reference fixtures
can become regression tests, not just curated notes.

### 2. Expression Functions

Use the existing `ast.Expression.function_call` shape. Add a function registry
inside the executor for deterministic built-ins. Vector functions should call
the existing `src/vector/distance.zig` helpers and return `float` values. This
slice should not require AST churn.

### 3. Query Row Sources

Replace `SelectStatement.from: ?[]const u8` with a row-source AST:

- base table or view with optional alias
- derived table with required alias
- join nodes with join type and `ON` predicate
- CTE declarations attached to `SELECT`

Executor evaluation should produce row environments rather than table-row pairs.
Qualified identifiers and table aliases resolve against that environment.

### 4. Aggregation

Once row environments exist, add grouping as a layer between filtering and
projection. Aggregates should reject invalid non-grouped projections rather than
guessing.

### 5. DDL Compatibility and Index Metadata

Support common MySQL DDL clauses that matter to application schemas. Primary
keys, auto-increment, defaults, and ordinary indexes can begin as catalog
metadata even before optimization uses them.

### 6. Stored Program Subset

Parse procedure bodies into a small statement/control-flow AST:

- parameters
- `DECLARE`
- `SET`
- ordinary SQL statements
- `IF`
- bounded `WHILE`

Execution shares the active session and transaction state. A loop safety limit
prevents accidental unbounded local execution in the embedded engine.

## Work Package Order

1. WP01: Roadmap truth and MTR-lite skeleton.
2. WP02: SQL function execution and vector ranking.
3. WP03: Query AST for aliases, qualified identifiers, CTEs, joins, and derived
   sources.
4. WP04: Row-source executor for aliases, joins, CTEs, derived tables, and
   richer views.
5. WP05: Aggregates, grouping, and HAVING.
6. WP06: MySQL-compatible DDL metadata and ordinary index definitions.
7. WP07: Stored procedure parameters and control flow.
8. WP08: Adapted MariaDB fixture execution and corpus refresh.
9. WP09: Acceptance hardening, benchmarks, and Spec Kitty notes.

## Validation Strategy

- Unit tests for parser/AST deinit behavior.
- Executor tests for every supported SQL form.
- Integration tests that mirror the spec scenarios.
- MTR-lite fixture tests for imported/adapted MariaDB cases.
- CLI smokes for parse/classify/execute/benchmark.
- `zig build test` after each completed work package.

## Branch Contract

Spec Kitty created a coordination branch
`kitty/mission-mysql-style-syntax-completion-01KT2G5Z` while leaving the root
checkout on `main`. Previous mission commands could not auto-commit to
protected `main`, so this mission will keep manual git commits as the reliable
fallback and record tool drift in `docs/spec-kitty-system-notes.md`.
