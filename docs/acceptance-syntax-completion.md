# MySQL-Style Syntax Completion Acceptance

Generated during WP09 of `mysql-style-syntax-completion-01KT2G5Z`.

## Validation Summary

```text
zig build test
status: pass
```

The full copied MariaDB reference classifier still matches the WP08 snapshot:

```text
files: 97
sacred-candidate: 2
adaptation-candidate: 35
rejected-by-policy: 60
deferred-candidate: 0
statements: 16027 accepted, 371 rejected, 16398 total
```

All promoted adapted fixture descriptors execute through MTR-lite:

```text
autoincrement-deferred: 6 statements, 6 executed, 0 expected errors
grouping-aggregates: 11 statements, 11 executed, 1 expected error
procedure-control-flow: 8 statements, 8 executed, 2 expected errors
procedure-single-statement: 7 statements, 7 executed, 0 expected errors
query-syntax: 16 statements, 16 executed, 0 expected errors
vector-distance-functions: 9 statements, 9 executed, 0 expected errors
vector-values: 5 statements, 5 executed, 0 expected errors
view-basic: 7 statements, 7 executed, 0 expected errors
```

## CLI Smokes

Parse smoke:

```bash
zig build run -- parse "WITH ranked AS (SELECT m.id, l2_distance(m.embedding, [1, 0]) AS distance FROM memories AS m JOIN memory_tags AS t ON t.memory_id = m.id) SELECT id FROM ranked ORDER BY distance ASC LIMIT 5"
```

Result:

```text
statement: select
```

Execute smoke:

```bash
zig build run -- execute \
  "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2))" \
  "CREATE TABLE memory_tags (id INTEGER, memory_id INTEGER, name TEXT)" \
  "BEGIN" \
  "INSERT INTO memories VALUES (1, 'project plan', [1, 0])" \
  "INSERT INTO memories VALUES (2, 'project note', [0.8, 0.2])" \
  "INSERT INTO memory_tags VALUES (1, 1, 'project')" \
  "INSERT INTO memory_tags VALUES (2, 2, 'project')" \
  "COMMIT" \
  "WITH ranked AS (SELECT m.id, m.body, l2_distance(m.embedding, [1, 0]) AS distance FROM memories AS m JOIN memory_tags AS t ON t.memory_id = m.id WHERE t.name = 'project') SELECT id, body FROM ranked WHERE distance < 0.3 ORDER BY distance ASC LIMIT 10"
```

Result:

```text
columns: id body
row: 1 'project plan'
row: 2 'project note'
rows: 2
```

Benchmark smoke:

```bash
zig build run -- benchmark --rows 20 --vectors 8 --dimensions 3 --operations 5
```

The benchmark now reports the mission hot paths:

```text
insert_commit
select_scan
grouped_scan
joined_filter
rollback_updates
exact_vector_scan
sql_vector_rank
```

## Deferred Non-Goals

The mission keeps these surfaces explicitly rejected or deferred instead of
silently accepting MariaDB compatibility syntax:

- Foreign keys.
- User-visible temporary tables.
- Storage engine clauses such as `ENGINE=InnoDB`.
- Replication, binlog, server lifecycle, auth, grants, roles, and privilege SQL.
- Plugin and UDF loading.
- Full stored-program parity, including cursors, handlers, recursion, dynamic
  SQL, `OUT`/`INOUT` parameters, and function-returning routines.
- ANN/vector index implementation.

## Acceptance Notes

No external blockers remain for the syntax-completion mission. Spec Kitty
workflow anomalies observed during WP09 were added to
`docs/spec-kitty-system-notes.md`.
