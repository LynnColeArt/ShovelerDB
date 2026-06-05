# Phase 9 Embedding ABI Foundation Spec

## Mission

Make ShovelerDB embeddable from other runtimes by defining and implementing the
first stable C ABI boundary. Phase 9 is the bridge from "the embedded engine
works in Zig" to "agents and applications can safely use it from the language
stacks they already run."

This mission should not try to ship every language connector at once. It should
create the small ABI contract, ownership rules, diagnostics vocabulary, and
smoke fixture that Go, Python, Java, PHP, TypeScript/Node, .NET, and Rust
connectors can share.

## Current Baseline

- ShovelerDB has a Zig library and CLI with SQL execution, transactions,
  persistence checkpoint/reopen, vector values/functions, constrained views and
  procedures, snapshot-reader concurrency, ordered writes, and benchmark
  discipline.
- `src/db/executor.zig` exposes an internal Zig SQL execution surface through
  `Database`, `Session`, `ExecutionResult`, `ResultSet`, and typed diagnostic
  mapping.
- `src/db/database.zig` exposes an embedded persistence API for
  open/create/checkpoint/close against filesystem-backed snapshot files.
- Result values currently use Zig-owned structures and allocator discipline;
  they are not safe to expose directly across foreign-function boundaries.
- The roadmap's Phase 9 goal is language connectors and embedding SDKs, but the
  first durable contract must be a small C ABI that all connectors can test
  against.

## Scope

- Add a documented C ABI design for opening/closing databases, executing SQL,
  iterating result rows, reading typed values, reporting typed errors, and
  releasing caller-visible resources.
- Add an ABI implementation layer that owns all exported handles and never
  exposes internal Zig pointers or allocator-owned slices directly.
- Add a generated or checked-in C header describing the exported ABI surface.
- Add integration tests/smokes that exercise the ABI boundary through the same
  product path future connectors will call.
- Add shared connector fixture docs that specify the minimum behavior every
  connector must pass before it is considered real.
- Refresh roadmap/docs to mark Phase 9 as active and preserve the embedded,
  no-server product boundary.

## Non-Goals

- Do not add a server, daemon, socket protocol, auth layer, replication, plugin
  surface, storage-engine selection, or user-visible temporary-table behavior.
- Do not ship full Go, Python, Java, PHP, TypeScript/Node, .NET, and Rust
  packages in this mission.
- Do not stabilize a broad SQL compatibility promise beyond the already
  accepted ShovelerDB dialect surface.
- Do not expose internal Zig allocator ownership, row-store pointers, AST
  nodes, transaction structs, or result slices directly to foreign callers.
- Do not implement approximate vector indexing or planner optimization; exact
  SQL vector ranking remains the connector-facing vector behavior for now.

## User Scenarios

### Scenario 1: A Host Runtime Opens an Embedded Database

A connector can call the C ABI to open or create a filesystem-backed database
file, receive an opaque database handle, and close it without leaking memory or
requiring a daemon process.

### Scenario 2: A Connector Executes SQL and Iterates Results

A connector can execute SQL through the ABI, detect whether the statement
returned rows or a mutation count, read column names, iterate rows, read typed
values, and release the result handle.

### Scenario 3: A Connector Runs Transactions

A connector can execute `BEGIN`, DML, `COMMIT`, and `ROLLBACK` through the same
ABI path and observe the same transaction behavior as native Zig tests.

### Scenario 4: A Connector Maps Errors

If SQL parsing, object lookup, type checking, vector dimensions, transaction
state, or persistence opening fails, the ABI returns a stable diagnostic code
and message surface that connectors can map to language-native errors.

### Scenario 5: A Connector Moves Vector Values

A connector can read vector result values as tagged float32 vectors with
dimension metadata and no hidden ownership assumptions. Future connector writes
must use the same representation.

## Functional Requirements

- **FR-001**: Add `docs/embedding-abi.md` documenting the ABI purpose, handle
  lifecycle, thread/concurrency expectations, ownership rules, error model,
  result iteration, vector representation, and connector fixture contract.
- **FR-002**: Add a C ABI module and header with opaque handle types for
  database, result, row/value access, and error/status reporting.
- **FR-003**: Support open-or-create and close for filesystem-backed embedded
  database files without requiring a daemon or global singleton.
- **FR-004**: Support SQL execution through the ABI for DDL, DML, transaction
  statements, and SELECT queries over the accepted ShovelerDB dialect subset.
- **FR-005**: Expose result metadata and row/value iteration for null, integer,
  float, boolean, text, blob, and float32 vector values.
- **FR-006**: Make ABI-owned results and strings explicitly releasable, with
  idempotent cleanup and no caller responsibility for internal Zig allocators.
- **FR-007**: Expose stable ABI diagnostic/status codes for parser, object,
  transaction, type, vector, persistence, invalid-handle, and allocation
  failures.
- **FR-008**: Add an ABI acceptance smoke that opens a database, creates a
  table, inserts rows inside a transaction, queries a vector ranking result,
  observes a typed error, checkpoints/closes, reopens, and verifies committed
  rows.
- **FR-009**: Add connector fixture documentation that future language
  packages can reuse without duplicating behavior assumptions.
- **FR-010**: Keep all existing SQL, transaction, persistence, view/procedure,
  vector, concurrency, adapted fixture, and benchmark tests passing.
- **FR-011**: Refresh roadmap and README status so Phase 9 is active only for
  the ABI foundation, not for every language connector package.

## Acceptance

- `zig build test` passes.
- ABI tests validate handle lifecycle, SQL execution, result iteration,
  vector result access, diagnostic mapping, and cleanup.
- `docs/embedding-abi.md` documents the ABI and connector fixture contract.
- A C header exists and matches the exported ABI symbols.
- `docs/project-plan.md` and README truthfully describe Phase 9 as active for
  ABI foundation work.
- No server lifecycle, network protocol, replication, plugin, auth, storage
  engine selection, or user-visible temporary-table surface is introduced.

## Risks

- A too-large ABI will become painful to support. Keep the first ABI small and
  versioned.
- Exposing internal Zig data directly would make connector memory safety
  brittle. Use opaque handles and copied/read-only value accessors.
- Error mapping can drift if each connector invents names. Keep diagnostic
  codes centralized at the ABI boundary.
- Transactions can become ambiguous if connectors mix explicit handles and SQL
  transaction statements too early. Start with SQL execution semantics and
  document the path clearly.
- Vector values can become expensive if copied unnecessarily, but safety comes
  first for the first connector contract.
