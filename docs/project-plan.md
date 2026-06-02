# ShovelerDB Project Plan

Current roadmap position: the MVP SQL/vector memory kernel mission completed on
2026-06-01. ShovelerDB now has a Zig library/CLI, SQL policy and parser,
in-memory row storage, transaction sessions, basic DDL/DML execution, constrained
views and procedures, vector values/helpers, snapshot persistence, adapted
fixture descriptors, CLI smokes, and benchmark coverage. The active follow-up
mission is `mysql-style-syntax-completion-01KT2G5Z`, which turns the remaining
"supported by design" SQL syntax into tested behavior or explicit rejections.

## Phase 0: Repository Foundation

Status: complete.

- Create the Zig project skeleton.
- Create documentation for the proposal, dialect, and test strategy.
- Copy curated MariaDB reference tests with provenance.
- Create the GitHub remote.
- Add a placeholder Zig library and CLI.

Exit criteria:

- Repository exists locally and remotely.
- `docs/proposal.md` and `docs/project-plan.md` define the initial direction.
- MariaDB reference tests are present under `references/mariadb/`.

## Phase 1: Test Import and Classification

Status: complete for the initial corpus; continuing as syntax expands.

Goal: turn MariaDB tests into an actionable ShovelerDB roadmap.

Tasks:

- Write a manifest format for imported tests.
- Build a small classifier for MariaDB `.test` files.
- Label tests as `sacred`, `adapted`, `deferred`, or `rejected`.
- Start with vector, transaction, view, procedure, numeric, string, and JSON
  references.
- Document every intentional incompatibility.

Exit criteria:

- A curated test manifest exists.
- At least 25 MariaDB tests are classified.
- Foreign key and temporary table tests are explicitly rejected by policy.

## Phase 2: MTR-Lite Runner

Status: started; the skeleton runner executes adapted fixture descriptors.

Goal: run a useful subset of MariaDB SQL regression tests against ShovelerDB.

Tasks:

- Parse simple `.test` commands.
- Support `--error`, `--replace_regex`, and expected result comparison.
- Ignore or reject server-only harness directives with clear diagnostics.
- Produce stable, reviewable output.

Exit criteria:

- The runner can execute selected vector and transaction reference tests in dry
  mode.
- Unsupported directives are reported with reasons.

## Phase 3: Minimal SQL Core

Status: complete for the MVP kernel.

Goal: build the smallest SQL path that can execute real statements.

Tasks:

- Tokenizer and parser for the initial dialect.
- Catalog for tables and columns.
- In-memory row storage.
- Basic expression evaluation.
- `CREATE TABLE`, `INSERT`, `SELECT`, `UPDATE`, `DELETE`.
- `BEGIN`, `COMMIT`, `ROLLBACK` with in-memory transaction semantics.

Exit criteria:

- Native Zig tests cover basic SQL execution.
- The first curated MariaDB DML tests can be adapted and run.

## Phase 4: Vector MVP

Status: partially complete; SQL-level vector distance functions now execute in
projection, filtering, and ordering, while vector index/planner optimization
remains future work.

Goal: make vectors a core type, not an add-on.

Tasks:

- `VECTOR(N)` type.
- Binary and text vector literal parsing.
- Distance functions.
- Exact top-k vector search.
- Planner recognition of `ORDER BY distance LIMIT n`.

Exit criteria:

- A small vector table can be created, loaded, and queried.
- The first MariaDB vector reference tests are passing or classified.

## Phase 5: Embedded Filesystem Store

Status: complete for the MVP snapshot/reopen path.

Goal: move from in-memory prototype to local durable database path.

Tasks:

- Define database directory layout.
- Add append-only log or generation files.
- Add explicit save/checkpoint action.
- Add recovery checks.
- Add crash-simulation tests.

Exit criteria:

- A database can be opened, mutated, saved, closed, and reopened.
- Failed saves do not corrupt the previous durable generation.

## Phase 6: Concurrency Model

Status: planned.

Goal: make ShovelerDB useful as an agent memory kernel.

Tasks:

- MVCC snapshots for readers.
- Ordered write/commit sequencer.
- Backpressure for write queues.
- Background checkpoint worker.
- Background vector index worker.

Exit criteria:

- Many concurrent readers see stable snapshots.
- Concurrent writers commit in a deterministic order.
- Vector writes are visible through an overlay before background indexing.

## Phase 7: Views and Procedures

Status: partially complete; simple views and constrained procedure control flow
work, while richer view expansion and unsupported stored-program surfaces remain
classified through the active syntax-completion mission.

Goal: support reusable schema logic without reintroducing server baggage.

Tasks:

- `CREATE VIEW` and view expansion.
- `CREATE PROCEDURE` and `CALL`.
- Procedure variables, `IF`, `WHILE`, and SQL statements in bodies.
- Procedure transaction behavior.

Exit criteria:

- A practical subset of MariaDB view and stored procedure tests is passing or
  classified.

## Phase 8: Performance Discipline

Status: started.

Goal: make speed measurable from the beginning.

Tasks:

- Add benchmark harness.
- Track allocation counts in hot paths.
- Benchmark insert, point lookup, scan, transaction commit, vector top-k, and
  hybrid filter/vector queries.
- Add regression thresholds once the engine stabilizes.

Exit criteria:

- Every major feature lands with a benchmark.
- Performance regressions are visible in CI.
