# SQL Dialect Notes

ShovelerDB targets a practical MariaDB-like dialect for embedded transactional
and vector workloads.

## Currently Executable

- `CREATE TABLE`, `DROP TABLE`
- `INSERT`, `SELECT`, `UPDATE`, `DELETE`
- `BEGIN`, `COMMIT`, `ROLLBACK`
- scalar columns: integer, float, boolean, text, blob
- `VECTOR(N)` columns and vector literals
- vector SQL functions: `l2_distance`, `squared_l2_distance`, and
  `cosine_distance`
- primary-key-like declarations tolerated as column attributes in the current
  parser surface
- scans and row sources with `WHERE`, `ORDER BY`, `LIMIT`, CTEs, derived
  tables, aliases, qualified identifiers, inner/cross/left joins,
  grouping/aggregates, `GROUP BY`, and `HAVING`
- views over supported `SELECT` statements, including richer row-source queries
  and persisted view definitions that remain executable after snapshot reopen
- constrained stored procedures with `IN` parameters, `DECLARE`, `SET`, `IF`,
  bounded `WHILE`, and supported SQL statements inside `BEGIN ... END`
- `CALL` execution through the caller session and transaction context, including
  caller-visible writes, commit durability, rollback discard behavior, and
  stable diagnostics for missing procedures, argument count, and known type
  mismatches
- CLI parse, execute, analyze, classify, and benchmark commands

## Deferred Or Future Work

- secondary-index planner behavior
- ANN/vector index implementation
- full MySQL DDL metadata parity
- `SHOW CREATE VIEW`, `INFORMATION_SCHEMA.VIEWS`, view algorithm clauses,
  definer/security clauses, and privilege metadata
- full stored-program parity, including cursors, handlers, recursion, dynamic
  SQL, routine functions, `OUT`/`INOUT`, packages, and server diagnostics areas

## Rejected by Design

- foreign keys
- user-visible temporary tables
- storage engine selection
- replication and binlog SQL
- users, grants, and server auth SQL
- plugin and UDF management
- daemon lifecycle commands
- historical SQL modes unless they directly help compatibility

## Compatibility Rule

If MariaDB behavior supports ShovelerDB's target workload, prefer matching it.
If MariaDB behavior exists to support legacy server administration,
multi-engine compatibility, or historical MySQL quirks, reject it explicitly.

## Foreign Keys

Foreign keys should fail loudly. Silent non-enforcement is not acceptable.

## Temporary Tables

User-visible temporary tables should fail loudly. Use CTEs, derived tables,
views, or explicit persistent staging tables instead.

Internal scratch space for sorting, grouping, query execution, and indexing is
allowed as an implementation detail.

## Compatibility Rule

Every accepted syntax form must be backed by execution tests. Syntax that is
not implemented yet should fail loudly or be documented as deferred; silent
acceptance is not compatible with the project direction.
