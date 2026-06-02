# Agent Concurrency MVCC Plan

## Current State

ShovelerDB already has transaction-local overlays and atomic commit by cloning a
row store then replacing the committed store. That gives a useful correctness
base, but read-only transactions currently scan the latest committed table when
they have no local writes. A reader that begins before a writer commits can
therefore observe later rows, which is not acceptable for an agent memory kernel
with many readers.

## Design

1. Capture committed table snapshots at session `BEGIN`.
2. Let transaction-local writes override the snapshot for tables a session
   mutates, preserving read-your-writes behavior.
3. Route scans through this visibility order:
   - active table transaction overlay
   - active session snapshot
   - current committed table store
4. Add a database commit sequence and serialized commit path.
5. Keep snapshot table metadata owned by the snapshot so future DDL work has a
   safe foundation.
6. Add tests and benchmark coverage before optimizing clone cost.

## Risks

- Clone-on-BEGIN is intentionally simple and may be expensive for large tables.
  This is acceptable for the first semantics milestone; later missions can move
  to shared immutable pages, reference-counted row batches, or version chains.
- Concurrent DDL is not handled in this slice.
- SQL auto-increment values under overlapping writer sessions may need a later
  dedicated allocator policy once row-id sequencing is promoted from internal
  row identity to SQL-visible identity.

## Validation

- Unit tests for reader snapshot stability and ordered writer commits.
- Existing integration tests and adapted MariaDB fixture execution.
- Benchmark smoke with the new `snapshot_read_write` metric.
