# ShovelerDB Proposal

## Summary

ShovelerDB is a Zig-native embedded database for agent memory systems.

It keeps the parts of relational databases that are still powerful for local AI
workloads: SQL, transactions, tables, indexes, views, stored procedures, and
durable filesystem state. It rejects server-era complexity that does not serve
the target use case: foreign keys, user-visible temporary tables, replication,
storage engine selection, plugins, daemon-first deployment, and legacy MySQL
compatibility modes.

The intended result is a small database kernel that can be linked into an agent
application, used as a local memory tool, and queried through a MariaDB-like SQL
dialect with native vector support.

## Problem

Agent systems need memory that is:

- Local and cheap to operate.
- Fast under heavy concurrent reads and writes.
- Transactional enough to keep tool calls, observations, summaries, and vector
  indexes consistent.
- Queryable through a real language rather than a narrow key-value API.
- Friendly to semantic retrieval and hybrid metadata/vector search.

Common solutions tend to be either too operationally heavy, too narrow, or too
distributed-first for this role. Running a database server plus extensions is
often too much machinery for a local agent app. Lightweight embedded databases
are attractive, but many do not provide the combination of MariaDB-like SQL,
procedures, transactions, and native vector indexing.

## Product Thesis

ShovelerDB is an embedded transactional SQL/vector database for agent memory.

The database should feel like opening a local project file, not administering a
server:

```text
No daemon.
No ports.
No replication topology.
No storage engine menu.
No foreign key ceremony.
No temporary table namespace.
Just a local memory store with SQL, transactions, and vectors.
```

## Core Commitments

- **Zig implementation:** one language for the engine, CLI, test runner, and
  filesystem layer.
- **Embedded first:** the primary API opens a database path from an application
  process.
- **MariaDB-like dialect:** ShovelerDB follows useful MariaDB syntax and
  behavior, with documented intentional differences.
- **Transactions are sacred:** SQL transactions provide atomicity and isolation.
- **Durability is explicit:** transaction visibility and durable filesystem save
  points can be separate modes.
- **Tables stay central:** embeddings are columns, not sidecar objects.
- **Vectors are native:** vector type, distance functions, and vector indexes
  are first-class optimizer concepts.
- **Views and procedures are first-class:** reusable query surfaces and in-DB
  procedural workflows matter.
- **Concurrency is agent-shaped:** many snapshot readers, ordered writes, and
  background indexing/checkpointing.

## Non-Goals

- No foreign key enforcement.
- No user-created temporary tables.
- No MariaDB wire-protocol compatibility in the initial product.
- No replication or binlog subsystem.
- No plugin architecture.
- No multiple user-facing storage engines.
- No promise to pass the full MariaDB test suite.
- No cloud service operated by the project.

## SQL Surface

The target dialect is "MariaDB-like where useful."

Expected early support:

- `CREATE TABLE`
- `INSERT`, `UPDATE`, `DELETE`, `SELECT`
- primary keys and ordinary indexes
- transactions: `BEGIN`, `COMMIT`, `ROLLBACK`
- `CREATE VIEW`
- `CREATE PROCEDURE` and `CALL`
- scalar expressions and functions
- `VECTOR(N)`, vector literals, distance functions, vector indexes
- CTEs and derived tables as the replacement for user-visible temporary tables

Explicit rejection examples:

```sql
CREATE TEMPORARY TABLE t (...);
```

```sql
CREATE TABLE child (
  parent_id INT,
  FOREIGN KEY (parent_id) REFERENCES parent(id)
);
```

These should fail loudly rather than silently degrade.

## Test Strategy

MariaDB is the behavioral reference, not the implementation base.

ShovelerDB imports a curated set of MariaDB tests and classifies each as:

- `sacred`: should pass as-is or with minimal harness adaptation.
- `adapted`: useful behavior, but the test needs ShovelerDB-specific framing.
- `deferred`: desirable but not part of the current milestone.
- `rejected`: intentionally unsupported behavior.

This keeps the MariaDB dialect claim honest while preventing server-era features
from sneaking into the project by accident.

## Initial Milestone

The first living organism should be tiny:

```sql
CREATE TABLE memories (
  id INTEGER PRIMARY KEY,
  body TEXT,
  embedding VECTOR(4)
);

BEGIN;
INSERT INTO memories VALUES (1, 'hello', '[0.1, 0.2, 0.3, 0.4]');
COMMIT;

SELECT id
FROM memories
ORDER BY VEC_DISTANCE(embedding, '[0.1, 0.2, 0.3, 0.4]')
LIMIT 5;
```

That single path exercises the identity of the project: SQL, tables,
transactions, vectors, and local execution.

