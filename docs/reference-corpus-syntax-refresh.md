# Reference Corpus Syntax Refresh

Generated during WP08 of `mysql-style-syntax-completion-01KT2G5Z`.

## Newly Executable Adapted Fixtures

```text
tests/fixtures/mariadb-adapted/query-syntax.md
tests/fixtures/mariadb-adapted/procedure-control-flow.md
tests/fixtures/mariadb-adapted/grouping-aggregates.md
```

These descriptors promote behavior from MariaDB reference tests into native
ShovelerDB SQL and are executed by `zig build test` through the MTR-lite runner.

## Coverage Added

- Query-source syntax: aliases, qualified identifiers, non-recursive CTEs,
  derived tables, inner/left/cross joins, view expansion, vector filtering, and
  deterministic ordering.
- Stored procedure subset: `IN` parameters, local variables, `IF`, bounded
  `WHILE`, SQL body statements, caller transaction state, and explicit
  unsupported cursor/dynamic SQL diagnostics.
- Grouping and aggregates: `COUNT`, `SUM`, `AVG`, `MIN`, `MAX`, `GROUP BY`,
  `HAVING`, aggregate aliases, and invalid grouped-projection diagnostics.

## Explicitly Deferred or Rejected

- MariaDB harness directives such as `delimiter`, `source`, `let`, `eval`,
  connection choreography, filesystem operations, and server restarts.
- Server metadata checks through `INFORMATION_SCHEMA`, privilege metadata,
  view definer/security clauses, storage-engine clauses, and SQL mode toggles.
- Stored-program cursors, handlers, dynamic SQL, recursion, `OUT`/`INOUT`
  parameters, and function-returning routines.

MTR-lite reports unsupported directives as `UnsupportedDirective` rather than
silently skipping them. Fixture-level expected errors use `--error <Name>` and
must match ShovelerDB's stable error names.
