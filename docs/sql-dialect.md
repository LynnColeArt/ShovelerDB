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
- single-table scans with `WHERE`, `ORDER BY`, and `LIMIT`
- views over supported `SELECT` statements, with current executor support
  strongest for simple delegation
- constrained stored procedures with `IN` parameters, `DECLARE`, `SET`, `IF`,
  bounded `WHILE`, and supported SQL statements inside `BEGIN ... END`
- CLI parse, execute, analyze, classify, and benchmark commands

## Active Syntax-Completion Mission

The mission `mysql-style-syntax-completion-01KT2G5Z` is responsible for turning
these design promises into tested executable behavior or explicit deferrals:

- ordinary indexes
- scalar expressions
- CTEs
- derived tables
- table aliases and qualified identifiers
- inner/cross/left joins
- aggregate functions, `GROUP BY`, and `HAVING`
- richer view expansion
- vector indexes
- MySQL-compatible DDL metadata such as `IF EXISTS`, `IF NOT EXISTS`, defaults,
  nullability, primary keys, and auto-increment metadata

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
