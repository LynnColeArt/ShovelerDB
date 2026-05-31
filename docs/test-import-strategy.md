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

## Import Rules

1. Preserve original references under `references/mariadb/`.
2. Do not edit copied reference files in place.
3. Port behavior into native Zig tests under `tests/`.
4. Record intentional incompatibilities in docs or a future manifest.
5. Prefer behavior-level compatibility over source-level compatibility.

