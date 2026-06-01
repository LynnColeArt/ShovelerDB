# MariaDB Reference Corpus Snapshot

Generated on 2026-06-01 with:

```bash
zig build run -- classify-test $(find references/mariadb -name '*.test' | sort)
```

## Summary

```text
files: 97
sacred-candidate: 2
adaptation-candidate: 35
rejected-by-policy: 60
deferred-candidate: 0
statements: 16027 accepted, 371 rejected, 16398 total
```

## Sacred Candidates

These files are plain policy-clean SQL under the current analyzer:

```text
references/mariadb/mysql-test/main/insert_update_autoinc-7150.test
references/mariadb/mysql-test/main/vector_utf16.test
```

## Adaptation Candidates

These files are policy-clean, but wrapped in MariaDB test harness behavior such
as directives, delimiter changes, or expected-error declarations:

```text
references/mariadb/mysql-test/main/delete_returning.test
references/mariadb/mysql-test/main/delete_single_to_multi.test
references/mariadb/mysql-test/main/sp-big.test
references/mariadb/mysql-test/main/sp-condition-handler.test
references/mariadb/mysql-test/main/sp-cursor-dynamic-debug.test
references/mariadb/mysql-test/main/sp-cursor-dynamic.test
references/mariadb/mysql-test/main/sp-cursor-slow-log.test
references/mariadb/mysql-test/main/sp-default-param.test
references/mariadb/mysql-test/main/sp-destruct.test
references/mariadb/mysql-test/main/sp-dynamic.test
references/mariadb/mysql-test/main/sp-expr.test
references/mariadb/mysql-test/main/sp-fib.test
references/mariadb/mysql-test/main/sp-for-loop.test
references/mariadb/mysql-test/main/sp-i_s_columns.test
references/mariadb/mysql-test/main/sp-inout.test
references/mariadb/mysql-test/main/sp-no-code.test
references/mariadb/mysql-test/main/sp-package-code.test
references/mariadb/mysql-test/main/sp-package.test
references/mariadb/mysql-test/main/sp-row.test
references/mariadb/mysql-test/main/sp-sys_refcursor.test
references/mariadb/mysql-test/main/sp-threads.test
references/mariadb/mysql-test/main/sp-typedef.test
references/mariadb/mysql-test/main/sp-ucs2.test
references/mariadb/mysql-test/main/sp-vars.test
references/mariadb/mysql-test/main/sp2.test
references/mariadb/mysql-test/main/sp_gis.test
references/mariadb/mysql-test/main/sp_missing_4665.test
references/mariadb/mysql-test/main/sp_stress_case.test
references/mariadb/mysql-test/main/sp_sync.test
references/mariadb/mysql-test/main/trans_read_only.test
references/mariadb/mysql-test/main/vector_debug.test
references/mariadb/mysql-test/main/vector_funcs.test
references/mariadb/mysql-test/main/vector_subdist.test
references/mariadb/mysql-test/main/view_alias.test
references/mariadb/mysql-test/main/view_debug.test
```

## Interpretation

The current classifier is intentionally strict. `rejected-by-policy` means a file
contains at least one statement outside ShovelerDB's intended surface, not that
the whole file is useless.

The most common early rejection classes are expected:

- user-visible temporary tables
- storage engine selection such as `ENGINE=InnoDB`

Many rejected files are likely still valuable after adaptation. For example,
InnoDB and transaction references often include `ENGINE=InnoDB` clauses because
MariaDB is multi-engine; ShovelerDB can port the behavior while omitting the
engine-selection syntax.

## Promoted Native Fixtures

WP07 adds a small native fixture set under
`tests/fixtures/mariadb-adapted/`. These descriptors keep provenance while
rewriting behavior into ShovelerDB's supported surface:

```text
tests/fixtures/mariadb-adapted/autoincrement-deferred.md
tests/fixtures/mariadb-adapted/procedure-single-statement.md
tests/fixtures/mariadb-adapted/vector-values.md
tests/fixtures/mariadb-adapted/view-basic.md
```

The classifier output above is unchanged by these descriptors because they do
not modify `references/mariadb/`; they are the bridge between reference evidence
and native acceptance tests.
