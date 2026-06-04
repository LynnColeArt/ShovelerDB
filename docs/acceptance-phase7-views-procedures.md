# Phase 7 Views and Procedures Acceptance

Generated during WP05 of `phase7-views-procedures-hardening-01KT9RHH`.

## Validation Summary

```text
zig build test
status: pass
```

Promoted view and procedure fixture descriptors execute through MTR-lite:

```text
query-syntax: 16 statements, 16 executed, 0 expected errors
view-basic: 7 statements, 7 executed, 0 expected errors
view-rich: 13 statements, 13 executed, 0 expected errors
procedure-single-statement: 7 statements, 7 executed, 0 expected errors
procedure-control-flow: 8 statements, 8 executed, 2 expected errors
```

Representative CLI smokes:

```text
zig build run -- parse "CREATE VIEW project_memory AS SELECT m.id AS memory_id, m.body FROM memories AS m ORDER BY memory_id ASC LIMIT 10"
status: pass
result: statement: create_view
```

```text
zig build run -- execute "CREATE TABLE memories (id INTEGER, body TEXT)" ...
status: pass
result: SELECT id, body FROM recent returned one row: 1 'from cli proc'
```

```text
zig build run -- benchmark --rows 20 --vectors 8 --dimensions 3 --operations 5
status: pass
result: benchmark reported all current hot paths, including sql_vector_rank,
queued_commit, checkpoint_overlap, and vector_overlay_visibility
```

## Requirement Evidence

| Requirement | Status | Evidence |
| --- | --- | --- |
| FR-001 | pass | `tests/integration/view_acceptance.zig`, `tests/integration/query_source_acceptance.zig`, `tests/fixtures/mariadb-adapted/query-syntax.md`, and `tests/fixtures/mariadb-adapted/view-rich.md` cover view expansion over aliases, qualified identifiers, joins, ordering, limits, and vector distance expressions. |
| FR-002 | pass | `tests/integration/view_acceptance.zig` verifies stable view result metadata and outer queries over view aliases. |
| FR-003 | pass | `tests/integration/view_acceptance.zig` verifies duplicate view creation, dropped views, and unknown view diagnostics. |
| FR-004 | pass | `tests/integration/view_persistence_acceptance.zig` verifies rich views persist through snapshot write/read and remain executable after executor reopen. |
| FR-005 | pass | `tests/integration/procedure_transaction_acceptance.zig` verifies missing procedure, argument count, and argument type diagnostics for `CALL`. |
| FR-006 | pass | `tests/integration/procedure_transaction_acceptance.zig` and `tests/integration/procedure_acceptance.zig` verify procedure body SQL executes through the caller session with commit visibility and rollback discard behavior. |
| FR-007 | pass | `tests/integration/procedure_diagnostics_acceptance.zig`, `tests/integration/procedure_acceptance.zig`, and `src/sql/procedure_body.zig` tests cover local variables, parameter references, assignment, `IF`, bounded `WHILE`, and the loop safety cap. |
| FR-008 | pass | `tests/integration/procedure_diagnostics_acceptance.zig`, `src/sql/procedure_body.zig`, and `tests/fixtures/mariadb-adapted/procedure-control-flow.md` preserve explicit rejection for cursors, handlers, recursion through `CALL`, dynamic SQL, routine functions, `OUT`/`INOUT`, packages, and server diagnostics surfaces without partial procedure catalog entries. |
| FR-009 | pass | `query-syntax.md`, `view-basic.md`, `view-rich.md`, `procedure-single-statement.md`, and `procedure-control-flow.md` execute through MTR-lite with expected diagnostics. |
| FR-010 | pass | `docs/sql-dialect.md`, `docs/project-plan.md`, `docs/reference-corpus-snapshot.md`, and this acceptance document describe supported, deferred, and rejected view/procedure behavior. |
| FR-011 | pass | Full validation includes `zig build test`, MTR-lite view/procedure fixtures, parse/execute CLI smokes, and a representative benchmark smoke. |
| FR-012 | pass | `docs/sql-dialect.md`, `src/lib.zig` feature policy tests, and procedure diagnostics coverage keep server lifecycle, replication, temporary-table, plugin, user/auth, full stored-program, and legacy metadata surfaces out of the supported subset. |

## Accepted Subset

Views are accepted for supported `SELECT` statements over the current row-source
surface, including aliases, qualified identifiers, joins, derived/CTE-backed
queries where already supported, grouping/aggregates, ordering, limits, and
vector distance expressions. View definitions persist as executable `SELECT`
body SQL in snapshots.

Procedures are accepted for constrained `CREATE PROCEDURE`, `DROP PROCEDURE`,
and `CALL` with `IN` parameters, local `DECLARE`, `SET`, `IF`, bounded `WHILE`,
and supported SQL statements routed through the normal executor. Procedure
writes share the caller session and transaction state.

## Deferred And Rejected

ShovelerDB still rejects MariaDB server metadata and full stored-program
parity: `SHOW CREATE VIEW`, `INFORMATION_SCHEMA.VIEWS`, definer/security
clauses, cursors, handlers, recursion, dynamic SQL, routine functions,
`OUT`/`INOUT`, packages, server diagnostics areas, user-visible temporary
tables, replication/binlog syntax, plugin/UDF loading, users/grants/auth, and
daemon lifecycle commands.

## Acceptance Notes

No code or validation blockers remain for Phase 7. Formal `spec-kitty accept
--mode local --lenient --no-commit --json` passed on the repaired mission
branch at 2026-06-04T23:52:06Z with WP01-WP05 in `done`, no failed checks,
and only optional artifact warnings.
