# ShovelerDB Concurrency Contract

This document tracks the intended Phase 6 concurrency semantics.

## Current Baseline

The first MVCC slice is complete:

- A reader transaction sees a stable snapshot after `BEGIN`.
- Writer commits serialize through a commit sequence.
- Writer-local changes remain visible to the writer before commit.
- Rollback discards local staged changes.

The current implementation is intentionally simple and clones row stores at
reader `BEGIN`. The scalable Phase 6 mission must preserve the semantics while
making snapshot acquisition cheap.

## Target Semantics

- Readers acquire a committed generation handle.
- Writers stage changes locally and publish through one ordered commit
  sequencer.
- Commit sequence numbers are monotonically increasing.
- Backpressure is explicit and typed; overload must not silently drop writes.
- Checkpoints write committed generations and do not mutate active reader
  snapshots.
- Exact vector scans include committed vector overlay deltas before future ANN
  indexing exists.

## Non-Goals

- No daemon or network server.
- No replication.
- No user-visible temporary tables.
- No foreign keys.
- No ANN vector index in this phase.
- No fully concurrent DDL yet.

## Acceptance Shape

The concurrency implementation is not considered ready until tests cover:

- many readers holding stable snapshots while writers commit;
- writer queue ordering and backpressure;
- rollback under queue pressure;
- checkpoint overlap with active readers;
- committed vector writes visible through exact scan overlay;
- benchmark metrics for snapshot begin, queued commit, checkpoint overlap, and
  vector overlay visibility.
