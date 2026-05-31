# ShovelerDB

ShovelerDB is an experimental Zig-native embedded database for agent memory systems.

The project goal is a MariaDB-like SQL dialect over a small, fast, transactional,
filesystem-backed core with native vector columns and indexes. ShovelerDB is not
a MariaDB fork. It uses curated MariaDB tests as behavioral references and keeps
the parts of the SQL/database model that fit local agent memory workloads.

## Design Commitments

- Zig-native implementation.
- Embedded first: no daemon required.
- MariaDB-like SQL dialect where useful.
- Transactions, tables, views, and stored procedures are core features.
- Vector columns, vector functions, and vector indexes are core features.
- No foreign keys.
- No user-visible temporary tables.
- No replication, binlog, storage engine selection, or plugin ecosystem.
- Explicit durability modes: in-memory transaction commits and durable save/checkpoint actions.
- High-concurrency agent memory model: many snapshot readers, ordered writes, background indexing.

## Repository Layout

- `docs/`: proposal, project plan, and dialect notes.
- `src/`: Zig source for the future engine and CLI.
- `tests/`: ShovelerDB-native tests.
- `references/mariadb/`: curated MariaDB test and license references.
- `tools/`: future import/classification tooling for MariaDB tests.

## Status

This repository is an early build scaffold. The engine does not exist yet, but
the first dialect-policy code is in place.

## First Commands

```bash
zig build test
zig build run
zig build run -- check-sql "CREATE TABLE memories (id INTEGER PRIMARY KEY, embedding VECTOR(4));"
```

The `check-sql` command currently performs a lightweight dialect-policy pass. It
accepts the intended ShovelerDB surface and rejects early non-goals such as
foreign keys, user-visible temporary tables, storage engine selection,
replication/binlog statements, grants/users, and plugins.
