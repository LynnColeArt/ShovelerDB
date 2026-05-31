# SQL Dialect Notes

ShovelerDB targets a practical MariaDB-like dialect for embedded transactional
and vector workloads.

## Supported by Design

- tables
- primary keys
- ordinary indexes
- transactions
- views
- stored procedures
- scalar expressions
- CTEs
- derived tables
- vector columns
- vector functions
- vector indexes

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

