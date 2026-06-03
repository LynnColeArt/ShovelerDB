# ShovelerDB Concurrency Contract

This document is the authoritative Phase 6 concurrency contract for
`phase6-scalable-concurrency-01KT53SK`. The mission keeps ShovelerDB embedded
and local-first while making the already-correct MVCC behavior scalable enough
for many agent sessions sharing one database handle.

## Current Baseline

The first MVCC slice is complete in the SQL executor:

- A reader transaction sees a stable snapshot after `BEGIN`.
- Writer-local changes remain visible to the writer before commit.
- Writer commits serialize through a commit sequence.
- Rollback discards local staged changes and does not advance the commit
  sequence.

The current implementation still captures table snapshots eagerly at `BEGIN`.
Later Phase 6 work must keep the visible behavior while replacing eager clones
with cheap generation handles or an equivalent O(1) or near-O(1) snapshot model.

## Session Lifecycle

- A session is an embedded API object owned by the caller; it is not a server
  connection and has no network lifecycle.
- `BEGIN` starts one transaction for that session and captures the current
  committed generation.
- A session may read from its captured snapshot, from its writer-local staged
  changes, or from the latest committed state when no transaction is active.
- `COMMIT` publishes staged writes through the ordered commit path and leaves the
  session inactive.
- `ROLLBACK` clears staged writes locally and leaves the session inactive.
- Nested transactions, fully concurrent DDL, foreign keys, user-visible
  temporary tables, daemon behavior, and replication are out of scope.

## Snapshot Visibility

- Reader snapshots are stable: later commits, checkpoints, and vector overlay
  updates must not alter rows visible to an active read transaction.
- Snapshot acquisition must become O(1) or near-O(1) with respect to row count.
  The acceptable target is a generation handle, persistent row pages, or another
  structure with the same visible behavior.
- Snapshot identifiers are generation-like values. The public contract uses
  `SnapshotGeneration` in `src/db/concurrency.zig` so later WPs have a shared
  type for checkpoint and retention diagnostics.
- Snapshot retention may be bounded, but exhaustion must return a typed
  diagnostic instead of silently invalidating active readers.

## Commit Queue

- All writer commits pass through one ordered commit sequencer.
- The sequencer assigns monotonically increasing `CommitSequence` values.
- Commit sequence numbers advance only for commits that publish writes.
- Commit ordering is deterministic from the queue order; later implementation
  may use locks, bounded channels, or another embedded coordination structure.
- Rollback never enters the commit queue and never reserves a commit sequence.

## Backpressure Diagnostics

Backpressure is an explicit part of the API contract. Queue overload, snapshot
retention exhaustion, checkpoint contention, and vector overlay backlog must be
reported as typed diagnostics. WP01 introduces the shared diagnostic vocabulary
in `src/db/concurrency.zig`:

- `commit_queue_full`
- `snapshot_retention_exceeded`
- `checkpoint_already_running`
- `vector_overlay_backlog_exceeded`
- invalid configuration diagnostics for queue, snapshot retention, checkpoint,
  and vector overlay budgets

Later WPs should map these diagnostics to executor and connector-facing errors
without losing the typed reason or the relevant queue/generation budget.

## Checkpoints

- A checkpoint writes a committed generation to durable storage.
- Checkpoints must not mutate active reader snapshots.
- A failed checkpoint leaves the last durable generation intact and does not
  corrupt in-memory committed state.
- Only one checkpoint may run for a database handle at a time unless a later
  design proves equivalent safety. Overlapping requests should return the typed
  checkpoint diagnostic.

## Vector Overlay

- Committed vector writes must be visible to exact SQL/vector scans immediately
  after commit.
- The overlay is the bridge between committed row changes and a future
  background ANN index worker.
- The overlay must expose enough generation and backlog information for a future
  worker to drain committed deltas deterministically.
- No approximate nearest-neighbor index is required in Phase 6; exact scans plus
  committed overlay visibility are the contract.

## Acceptance Harness

The dedicated integration harness lives at
`tests/integration/concurrency_contract_acceptance.zig` and is wired into
`zig build test`. WP01 keeps it intentionally small:

- many active reader sessions keep their snapshot while a writer commits;
- rollback remains local and sequence-neutral;
- queue backpressure returns a typed diagnostic;
- checkpoint and vector overlay pressure hooks are named and testable.

WP02 through WP05 should extend this harness with cheap snapshot, queue,
checkpoint, vector overlay, stress, and benchmark assertions rather than adding
parallel dead-code tests.
