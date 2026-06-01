# ShovelerDB MVP SQL Vector Memory Kernel

**Mission slug:** `mvp-sql-vector-memory-kernel-01KT1MHB`
**Mission type:** `software-dev`
**Target branch:** `main`
**Spec date:** 2026-06-01
**Status:** Drafted for Spec Kitty planning

## Intent Summary

Build the first usable ShovelerDB kernel: an embedded, filesystem-backed,
Zig-native SQL database for agent memory workloads. The milestone keeps SQL,
tables, rows, views, procedures, and transactions as first-class concepts while
adding vector storage and exact vector search. It deliberately excludes the
MariaDB/MySQL server estate: replication, binlogs, pluggable storage engines,
user/admin/auth surfaces, foreign keys, and user-visible temp tables.

The primary actor is an agent application embedding ShovelerDB locally or in a
cloud worker. The trigger is an application process opening a database file,
running many concurrent reads and writes, and committing durable changes when it
chooses. The desired outcome is a compact, testable kernel that can accept a
small MariaDB-like SQL subset, execute transactional table/vector operations in
memory, and persist committed state to disk with clear crash semantics.

## Product Thesis

ShovelerDB is not a MariaDB fork with less code. It is a new embedded database
that borrows behavior and test wisdom from MariaDB where that helps preserve a
familiar SQL dialect. It should feel natural to developers who know SQL, but its
operational model should be closer to an embeddable library: no daemon required,
no network protocol required, no storage-engine selection, and no inherited
legacy compatibility obligations unless they protect the sacred SQL contract.

The database is optimized for agent memory systems:

- Agent apps can issue hundreds or thousands of concurrent reads.
- Writes are fast because they mutate an in-memory transactional state first.
- Durability is explicit at transaction commit and database checkpoint points.
- Vector columns and vector search are native, not bolted on through plugins.
- Test imports from MariaDB guide dialect behavior, but ShovelerDB owns its own
  narrower policy and rejects legacy surfaces loudly.

## Existing Foundation

The repository already contains a small Zig project and a reference-test intake
surface:

- `zig build test` passes on Zig 0.16.0.
- `src/sql/tokenizer.zig` tokenizes SQL while skipping comments and quoted text.
- `src/sql/policy.zig` accepts or rejects statements according to the current
  ShovelerDB SQL policy.
- `src/mariadb/test_analyzer.zig` extracts statements from MariaDB `.test`
  files and accounts for comments, directives, harness commands, delimiters,
  and expected errors.
- `src/mariadb/test_classifier.zig` classifies imported tests as
  `sacred-candidate`, `adaptation-candidate`, `rejected-by-policy`, or
  `deferred-candidate`.
- `references/mariadb/` contains a curated MariaDB test slice from commit
  `a06be0288f63f520aec95982cc6f872d26c4f23c`.
- `docs/reference-corpus-snapshot.md` records the current 97-file corpus
  baseline: 2 sacred candidates, 35 adaptation candidates, 60 rejected by
  policy, and 16,028 accepted statements out of 16,398 total statements.

## Domain Language

| Term | Meaning |
| --- | --- |
| ShovelerDB | The Zig-native embedded database being built in this repository. |
| Reference test | A MariaDB/MySQL test file used as behavioral evidence, not copied blindly as a required compatibility contract. |
| Sacred SQL | SQL features that must remain first-class: transactions, tables, rows, views, procedures, and query semantics. |
| Policy rejection | A deliberate refusal of unsupported legacy behavior such as foreign keys, temp tables, engine selection, replication, auth, or plugins. |
| Kernel | The embeddable storage, transaction, SQL, and vector core, excluding any daemon or cloud control plane. |
| Commit | The transaction boundary at which changes become visible according to transaction semantics and eligible for durable persistence. |
| Checkpoint | A database-level persistence operation that writes a consistent committed snapshot or log state to the filesystem. |

## User Stories

### US-001: Embedded Agent Memory Store

As an agent application, I can open a local ShovelerDB database, create tables
with scalar and vector columns, insert memories, search them by SQL predicates
and vector distance, and commit changes explicitly.

Acceptance:

- The workflow runs through a Zig API and a CLI smoke command.
- No background server process is required.
- Vector inserts and exact nearest-neighbor queries work on committed rows.
- Rollback discards uncommitted rows and vector entries.

### US-002: MariaDB-Like SQL Subset

As a developer familiar with MariaDB/MySQL, I can use a recognizable SQL dialect
for the supported subset and get clear errors for intentionally removed features.

Acceptance:

- Core DDL/DML syntax is parsed into an AST instead of accepted only by string
  policy checks.
- Unsupported constructs produce stable ShovelerDB diagnostics.
- Imported MariaDB tests are either adapted, rejected by policy, or deferred
  with a recorded reason.

### US-003: Fast In-Memory Transaction Loop

As an agent runtime with many concurrent operations, I can run read-heavy and
write-heavy memory workloads without paying daemon, plugin, or legacy overhead.

Acceptance:

- The initial executor uses in-memory table/index state for active transactions.
- Concurrent readers can operate while writers build transaction-local changes.
- The benchmark suite records read, write, commit, rollback, and vector-scan
  timing on local hardware.

### US-004: Spec Kitty Long-Horizon Execution

As the project owner, I can hand this whole milestone to Spec Kitty and have it
track implementation work packages, acceptance checks, and any Spec Kitty tool
bugs encountered during the run.

Acceptance:

- This mission has a substantive spec, plan, and work-package breakdown.
- Work packages are small enough for isolated implementation and review.
- Tooling anomalies are logged in `docs/spec-kitty-system-notes.md`.

## Functional Requirements

| ID | Status | Requirement | Acceptance |
| --- | --- | --- | --- |
| FR-001 | Required | Preserve the SQL policy gate as the first filter before deeper parsing. | `check-sql` still accepts supported statements and rejects foreign keys, temp tables, engine selection, replication/binlog, auth/admin, and plugins with stable reasons. |
| FR-002 | Required | Add a real parser and AST for the MVP SQL subset. | Parser covers `CREATE TABLE`, `DROP TABLE`, `INSERT`, `SELECT`, `UPDATE`, `DELETE`, `BEGIN`, `COMMIT`, `ROLLBACK`, `CREATE VIEW`, `DROP VIEW`, `CREATE PROCEDURE`, and `CALL` at MVP depth. |
| FR-003 | Required | Implement a typed catalog with tables, columns, views, procedures, and vector metadata. | Catalog APIs can create/drop/list tables, views, and procedures; duplicate names and missing references return typed errors. |
| FR-004 | Required | Implement an in-memory row store for scalar columns. | Tables can store integer, float, boolean, text, blob, null, and vector values with stable row IDs. |
| FR-005 | Required | Implement a native fixed-dimension `VECTOR(N)` type. | Vector values validate dimension and element type at insert/update; invalid dimensions fail before mutation. |
| FR-006 | Required | Implement exact vector distance functions for MVP. | SQL can evaluate at least L2 distance and cosine distance against vector columns using an exact scan. |
| FR-007 | Required | Implement basic `SELECT` execution. | Executor supports projection, table scan, simple `WHERE`, `ORDER BY`, `LIMIT`, and vector-distance ordering for a single table. |
| FR-008 | Required | Implement basic mutation execution. | Executor supports insert, update, and delete for a single table inside transaction context. |
| FR-009 | Required | Implement transaction sessions with `BEGIN`, `COMMIT`, and `ROLLBACK`. | Changes inside a transaction are isolated from other sessions until commit; rollback discards all transaction-local changes. |
| FR-010 | Required | Define initial commit and checkpoint persistence semantics. | Committed state can be written to disk and reopened; partial or failed writes never produce a silently corrupted database. |
| FR-011 | Required | Provide an embedded Zig API for opening a database and executing statements. | Public API exposes open/close, execute, query, begin/commit/rollback, and error diagnostics without requiring the CLI. |
| FR-012 | Required | Keep the CLI useful as a smoke and development harness. | CLI can run policy checks, parse statements, execute simple SQL against a database path, classify reference tests, and run benchmark commands. |
| FR-013 | Required | Convert selected MariaDB reference tests into ShovelerDB-native fixtures. | At least one sacred candidate and three adaptation candidates are represented by native tests or fixture files with documented deltas. |
| FR-014 | Required | Preserve and expand the MariaDB reference classification workflow. | Full corpus classification remains runnable; summary output includes file counts, bucket counts, accepted/rejected statements, and first rejection details. |
| FR-015 | Required | Add benchmark coverage for the memory-kernel path. | Benchmarks report table insert, point lookup or predicate scan, transaction commit, rollback, and exact vector scan timings. |
| FR-016 | Required | Track Spec Kitty tooling issues observed during this mission. | `docs/spec-kitty-system-notes.md` records command, observed behavior, impact, workaround, and report-readiness for each issue. |
| FR-017 | Required | Exclude foreign-key execution from the MVP. | Any `FOREIGN KEY`, `REFERENCES`, or equivalent constraint syntax is rejected by policy before catalog mutation. |
| FR-018 | Required | Exclude user-visible temp tables from the MVP. | Any `TEMPORARY` or `TEMP` table syntax is rejected by policy before parser/executor mutation. |
| FR-019 | Required | Exclude MariaDB plugin and storage-engine surfaces from the MVP. | `ENGINE=`, `INSTALL PLUGIN`, `UNINSTALL PLUGIN`, storage-engine selection, and plugin loading are rejected by policy. |
| FR-020 | Required | Exclude daemon, replication, binlog, user, grant, and auth surfaces from the MVP. | Policy rejects these statements and docs keep them listed as non-goals. |
| FR-021 | Required | Keep procedures in scope at an MVP-constrained depth. | Stored procedure definitions can be registered and called for simple statement bodies, with unsupported body syntax producing typed diagnostics. |
| FR-022 | Required | Keep views in scope at an MVP-constrained depth. | Views can be registered over supported `SELECT` statements and expanded or executed by the query path. |

## Non-Functional Requirements

| ID | Status | Requirement | Measurement |
| --- | --- | --- | --- |
| NFR-001 | Required | The core implementation remains Zig-native for this milestone. | `zig build test` builds the library and CLI without introducing C/C++/Rust/Go core runtime dependencies. |
| NFR-002 | Required | The MVP is embedded-first and does not require a server process. | Acceptance workflow opens and queries a database file through the library or CLI without starting a daemon. |
| NFR-003 | Required | The test suite remains fast enough for tight iteration. | `zig build test` should complete in under 10 seconds on the current development machine unless a benchmark mode is explicitly requested. |
| NFR-004 | Required | Benchmarks are reproducible and explicit. | Benchmark commands print dataset size, vector dimension, operation count, elapsed time, and throughput. |
| NFR-005 | Required | Policy rejection diagnostics are stable. | Tests assert diagnostic categories, not ad hoc prose that changes between runs. |
| NFR-006 | Required | Persistence writes are crash-conscious. | Disk writes use a staged or journaled pattern with validation on reopen; tests cover truncated or invalid files where practical. |
| NFR-007 | Required | Concurrency behavior is deterministic under tests. | Transaction tests exercise at least two sessions and assert visibility before commit, after commit, and after rollback. |
| NFR-008 | Required | Memory ownership is explicit. | Public APIs document allocator ownership; tests run under Zig's test allocator or leak-detecting allocator where practical. |
| NFR-009 | Required | MariaDB reference material stays separated from native ShovelerDB tests. | Adapted tests live outside `references/mariadb/`, and docs distinguish behavioral evidence from supported product contract. |
| NFR-010 | Required | The milestone remains reviewable by Spec Kitty work packages. | No work package should own broad overlapping globs such as all of `src/**`; each package declares a focused authoritative surface. |

## Constraints

| ID | Status | Constraint | Rationale |
| --- | --- | --- | --- |
| C-001 | Active | Do not implement foreign keys in this milestone. | The project deliberately rejects FK semantics as operationally undesirable for this product shape. |
| C-002 | Active | Do not implement user-visible temp tables in this milestone. | Temp tables conflict with the desired clean transaction and memory model. |
| C-003 | Active | Do not implement a daemon, network protocol, cloud service, or admin/auth layer in this milestone. | The kernel is embedded-first; server/cloud wrappers can be separate future products if needed. |
| C-004 | Active | Do not preserve MariaDB storage-engine selection. | ShovelerDB has one kernel storage model for the MVP. |
| C-005 | Active | Do not preserve MariaDB plugin loading. | Plugin indirection is intentionally excluded from the operational model. |
| C-006 | Active | Do not mutate `references/mariadb/` when creating native tests. | Reference imports remain evidence snapshots. |
| C-007 | Active | Do not silently accept unsupported SQL. | Unsupported syntax must produce typed diagnostics before state mutation. |
| C-008 | Active | Use structured parser/executor APIs instead of stringly execution once a statement passes policy. | The policy gate is not a substitute for semantics. |
| C-009 | Active | Keep all milestone work compatible with Zig 0.16.0 unless an explicit upgrade decision is made. | The local toolchain is already installed and verified. |
| C-010 | Active | Log Spec Kitty tool anomalies during this mission. | The user wants actionable notes to report back to Rebert. |

## MVP SQL Surface

### In Scope

- `CREATE TABLE` with scalar columns and `VECTOR(N)`.
- `DROP TABLE`.
- `INSERT INTO ... VALUES ...`.
- `SELECT` with projection, single-table `FROM`, simple `WHERE`, `ORDER BY`,
  `LIMIT`, and vector-distance expressions.
- `UPDATE` and `DELETE` with simple predicates.
- `BEGIN`, `COMMIT`, and `ROLLBACK`.
- `CREATE VIEW`, `DROP VIEW`, and querying simple views.
- `CREATE PROCEDURE`, `DROP PROCEDURE`, and `CALL` for simple statement bodies.
- Built-in vector functions for exact L2 and cosine distance.

### Out of Scope

- Foreign keys and referential actions.
- User-visible temp tables.
- Replication, binlog, GTID, clustering, and server failover.
- Storage engine selection and plugin loading.
- Authentication, grants, users, roles, TLS, or network protocol surfaces.
- MariaDB compatibility bugs, permissive legacy quirks, and deprecated syntax
  unless explicitly promoted by a later policy decision.
- Approximate nearest-neighbor indexes. Exact scan is enough for this milestone;
  ANN can become a later performance slice.

## Execution Model

ShovelerDB should treat the active database as an in-memory transactional state
with explicit persistence boundaries.

1. Opening a database loads the latest valid committed state.
2. A session without an explicit transaction may run in autocommit mode only if
   this is deliberately specified by the API or CLI.
3. `BEGIN` creates a transaction-local mutation context.
4. Reads inside the transaction see the transaction's own writes.
5. Reads outside the transaction do not see uncommitted writes.
6. `ROLLBACK` drops the transaction-local mutation context.
7. `COMMIT` validates constraints, publishes the transaction atomically to the
   committed in-memory state, and makes that state eligible for durable write.
8. Persistence writes use a recoverable format: either append-only journal plus
   checkpoint or atomic snapshot replacement. The plan may choose the simpler
   path for MVP, but it must define crash behavior before implementation.

## Reference Test Strategy

The MariaDB reference corpus is a guide, not a cage.

1. Keep running the full classifier over `references/mariadb`.
2. Promote small useful tests into native ShovelerDB fixtures.
3. For each promoted test, record its source file, source intent, ShovelerDB
   adaptation, and unsupported MariaDB behavior removed.
4. Keep rejections explicit: a rejected reference test is successful evidence
   when it exercises a deliberate non-goal.
5. Expand the analyzer only when it unlocks better reference extraction or
   clearer classification, not to emulate every mysql-test-run behavior.

Initial reference targets:

| Source | Initial Use |
| --- | --- |
| `references/mariadb/mysql-test/main/vector_utf16.test` | Sacred vector behavior evidence; extract vector-literal and charset-relevant expectations if useful. |
| `references/mariadb/mysql-test/main/sp-fib.test` | Procedure adaptation candidate; convert simple procedure call behavior. |
| `references/mariadb/mysql-test/main/view*.test` | View adaptation candidates; extract supported view creation/query behavior while rejecting temp-table cases. |
| `references/mariadb/mysql-test/main/insert_update_autoinc-7150.test` | Sacred candidate; inspect whether autoincrement behavior belongs in MVP or should be deferred with a documented reason. |

## Observability and Diagnostics

MVP diagnostics should be boring and stable:

- Policy errors expose a category such as `foreign_key`, `temporary_table`, or
  `plugin_surface`.
- Parser errors expose location and expected token category where practical.
- Executor errors expose typed categories such as `unknown_table`,
  `unknown_column`, `type_mismatch`, `vector_dimension_mismatch`, and
  `transaction_required`.
- Persistence errors distinguish invalid format, unsupported format version,
  checksum or validation failure, and I/O failure.
- CLI commands print human-friendly output by default and machine-readable JSON
  where useful for Spec Kitty validation.

## Acceptance Criteria

The mission is acceptable when all of the following are true:

1. `zig build test` passes.
2. Existing CLI commands still work:
   - `zig build run -- check-sql "CREATE TABLE memories (id INTEGER PRIMARY KEY, embedding VECTOR(4));"`
   - `zig build run -- classify-test $(find references/mariadb -name '*.test' | sort)`
3. New parser tests cover accepted MVP syntax and rejected non-goals.
4. New executor tests cover table creation, insert, select, update, delete,
   rollback, commit visibility, vector insertion, and exact vector ordering.
5. Reopen tests prove a committed database can be persisted and read back.
6. At least four MariaDB-derived native fixtures exist with documented deltas.
7. A benchmark command reports baseline timings for scalar and vector memory
   workloads.
8. `docs/spec-kitty-system-notes.md` exists and records any Spec Kitty issues
   encountered, including the `init --here` drift and telemetry warnings seen
   during mission setup.
9. Spec Kitty work packages are finalized and validated without ownership
   overlap.

## Risks

| Risk | Mitigation |
| --- | --- |
| Parser scope expands into full SQL compatibility. | Keep the MVP grammar narrow and reject unsupported syntax early. |
| Procedure support becomes a full stored-program VM too soon. | Start with stored statement bodies and simple `CALL`; document unsupported control flow. |
| Persistence design stalls implementation. | Choose the smallest recoverable format that can satisfy reopen and corruption tests. |
| Vector performance expectations outrun exact scan. | Benchmark exact scan now; defer ANN indexes until the table/vector semantics are stable. |
| Spec Kitty metadata blocks progress. | Maintain `docs/spec-kitty-system-notes.md` and use CLI validation outputs to repair artifacts as needed. |

## Open Decisions Deferred Beyond MVP

- Whether to support autocommit by default or require explicit transaction
  blocks through the embedded API.
- Whether autoincrement belongs in the first executor milestone or a follow-up.
- Whether procedure bodies should support variables/control flow in MVP or only
  stored single-statement bodies.
- Whether the first durable format is snapshot-only, journal-plus-snapshot, or
  append-only log with compaction.
- Whether to expose C ABI bindings after the Zig API stabilizes.
