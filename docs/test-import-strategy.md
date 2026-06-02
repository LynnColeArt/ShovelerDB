# MariaDB Test Import Strategy

## Source

The initial reference corpus was copied from a local MariaDB fork at commit:

```text
a06be0288f63f520aec95982cc6f872d26c4f23c
```

The imported references are stored under `references/mariadb/`.

## License

MariaDB Server is GPLv2. The copied reference files are kept with a copy of the
MariaDB GPLv2 license in `references/mariadb/COPYING`.

ShovelerDB currently uses GPLv2 for the repository license because it includes
MariaDB-derived reference tests.

## Initial Corpus

- `mysql-test/main/vector*`
- selected `mysql-test/main/sp*` stored procedure tests
- selected `mysql-test/main/view*` view tests
- selected transaction and DML tests
- selected InnoDB MVCC, locking, deadlock, snapshot, and autoincrement tests
- `unittest/my_decimal`
- `unittest/strings`
- `unittest/json_lib`
- `unittest/sql`
- `storage/innobase/unittest`

Foreign key references are intentionally excluded from the initial copied set.

## Classification States

- `sacred`: behavior ShovelerDB should preserve.
- `adapted`: useful behavior, but the test must be rewritten or reframed.
- `deferred`: desirable, but outside the current milestone.
- `rejected`: intentionally unsupported by ShovelerDB.

The current CLI uses conservative working buckets while the corpus is being
surveyed:

- `sacred-candidate`: plain policy-clean SQL with no MariaDB harness features.
- `adaptation-candidate`: policy-clean SQL wrapped in directives, delimiter
  changes, expected errors, or other MariaDB test-runner behavior.
- `rejected-by-policy`: contains SQL that ShovelerDB intentionally rejects.
- `deferred-candidate`: no candidate SQL statements detected yet.

These buckets are triage labels, not final doctrine. A human review can promote
an adaptation candidate into a sacred test once it has a native ShovelerDB
version.

## Import Rules

1. Preserve original references under `references/mariadb/`.
2. Do not edit copied reference files in place.
3. Port behavior into native Zig tests under `tests/`.
4. Record intentional incompatibilities in docs or a future manifest.
5. Prefer behavior-level compatibility over source-level compatibility.

## Native Fixture Promotion

Promoted fixtures live under `tests/fixtures/mariadb-adapted/`. Each fixture is
a descriptor, not a verbatim corpus copy. It must name the MariaDB source path,
summarize the behavior being preserved, show the ShovelerDB-native smoke SQL,
and list removed or deferred MariaDB behavior.

The first promoted fixtures cover four evidence categories:

- `vector-values.md`: vector column and vector literal behavior from
  `mysql-test/main/vector.test`.
- `view-basic.md`: single-table view behavior from `mysql-test/main/view.test`.
- `procedure-single-statement.md`: procedure create/call/drop behavior from
  `mysql-test/main/sp.test`.
- `autoincrement-deferred.md`: stable identity evidence from
  `mysql-test/main/insert_update_autoinc-7150.test`, adapted to explicit IDs
  because SQL autoincrement syntax is not part of the MVP surface yet.
- `vector-distance-functions.md`: SQL-callable vector distance behavior from
  `mysql-test/main/vector_funcs.test`.
- `query-syntax.md`: aliases, joins, CTEs, derived tables, view expansion, and
  vector-aware filtering from `mysql-test/main/view_alias.test`.
- `procedure-control-flow.md`: stored procedure parameters, variables, control
  flow, and explicit cursor/dynamic-SQL rejections from `mysql-test/main/sp*`.
- `grouping-aggregates.md`: aggregate and grouping behavior from
  `mysql-test/main/sp-group.test`.

Policy-rejected MariaDB files are still useful evidence. A rejection usually
means the original file includes unsupported harness or server syntax such as
`ENGINE=InnoDB`, temporary tables, grants, or replication controls. The behavior
inside the file can still be promoted when the adapted fixture removes that
syntax and records the delta.

The full-corpus classifier remains the coarse survey command:

```bash
zig build run -- classify-test $(find references/mariadb -name '*.test' | sort)
```

## MTR-Lite Runner

The syntax-completion mission added an MTR-lite runner skeleton for adapted
fixtures. The runner executes ShovelerDB-native SQL fragments from fenced SQL
blocks through the embedded engine and rejects unsupported MariaDB harness
directives with clear reasons. Result comparison is still a follow-up once
fixtures carry expected rows in a structured format.

Current accepted runner features:

- plain SQL statement execution
- statement-level expected errors when the adapted fixture intentionally proves
  a rejection
- explicit diagnostics for unsupported directives such as server restarts,
  connection choreography, replication controls, delimiter tricks that have not
  been adapted, or filesystem/server harness commands

The runner should operate on adapted fixture descriptors first. Original
MariaDB files under `references/mariadb/` remain preserved evidence and should
not be mutated.

Example:

```bash
zig build run -- run-adapted-test tests/fixtures/mariadb-adapted/vector-distance-functions.md
```

`zig build test` executes the promoted WP08 syntax descriptors through
MTR-lite, so fixture drift is now part of normal regression coverage.
