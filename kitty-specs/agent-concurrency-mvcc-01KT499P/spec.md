# Agent Concurrency MVCC Spec

## Mission

Give ShovelerDB its first agent-shaped concurrency layer: stable reader
snapshots, deterministic write commit ordering, and benchmark evidence that the
engine can interleave reads and writes without losing transaction semantics.

This is the first MVCC slice, not the final lock-free architecture. The goal is
to establish correct visibility rules now, then optimize the data structures
and background workers in later missions.

## Scope

- Session-level snapshots captured at `BEGIN`.
- Read-only transactions continue to see their begin-time rows after later
  writer commits.
- Writer transactions keep read-your-writes behavior and commit through one
  ordered sequencer.
- Commit sequence numbers expose deterministic write order for tests and future
  checkpoint/index workers.
- Benchmarks include an interleaved snapshot-reader/writer workload.
- Existing SQL, view, procedure, vector, and MTR-lite coverage remains passing.

## Non-Goals

- Approximate vector indexes.
- Background checkpoint workers.
- Background vector index workers.
- Multi-threaded public API guarantees beyond serialized commit sequencing.
- Full DDL MVCC. Concurrent DDL remains outside this slice.
- MariaDB wire protocol, server mode, auth, replication, temp tables, or foreign
  keys.

## Functional Requirements

- **FR-001**: A session beginning a transaction captures a stable snapshot of
  committed table rows.
- **FR-002**: A reader with an active snapshot must not see rows committed after
  its `BEGIN`.
- **FR-003**: After the reader commits or rolls back, subsequent reads see the
  latest committed database state.
- **FR-004**: Writers can begin before each other commits and still land through
  deterministic commit ordering.
- **FR-005**: Commit sequence numbers increment once per write transaction and
  do not increment for read-only transaction close.
- **FR-006**: Writer-local inserts, updates, deletes, views, procedures, joins,
  grouping, and vector queries continue to use the visible row source for the
  session.
- **FR-007**: Snapshot tables own their table metadata so snapshot row stores do
  not depend on mutable catalog pointers.
- **FR-008**: The benchmark CLI reports a snapshot read/write metric alongside
  existing hot paths.

## Acceptance

- `zig build test` passes.
- `zig build run -- benchmark --rows 20 --vectors 8 --dimensions 3 --operations 5`
  reports `snapshot_read_write`.
- A test proves a read transaction stays stable while a writer commits.
- A test proves two writers begun before either commit can commit in sequence
  and leave both rows visible.
