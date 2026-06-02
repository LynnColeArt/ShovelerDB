# Phase 6 Scalable Concurrency Plan

## Current State

The current engine has correct first-slice MVCC behavior:

- Sessions can begin transactions.
- Reader snapshots remain stable while a writer commits.
- Writer commits serialize and expose commit sequence numbers.
- The benchmark includes `snapshot_read_write`.

The known scaling limit is that snapshots are currently captured by cloning
table metadata and row stores at `BEGIN`. That is good enough for correctness,
but it will be too expensive for agent workloads with many concurrent reads.

## Architecture Direction

### Snapshot Generations

Introduce an owned committed generation concept. A reader transaction should
hold a stable generation handle instead of cloning all rows. Writers continue to
stage changes locally, then publish a new committed generation during commit.

The exact implementation can start simple:

- immutable row batches or cloned table generations at commit time;
- generation IDs tied to commit sequence;
- explicit retain/release-style accounting if needed;
- no public exposure of internal generation structs.

### Commit Queue

Add an ordered commit queue between writer sessions and committed state. The
first version can execute synchronously inside the process, but it should expose
the shape future worker threads need:

- bounded queue capacity;
- queued commit batches;
- deterministic commit sequence assignment;
- typed backpressure errors;
- rollback paths that never enqueue work.

### Checkpoint Coordination

Checkpointing should write a committed generation. Active readers keep their
generation handles; checkpoint work must not mutate those handles. Failed writes
preserve the previous durable generation and leave in-memory state untouched.

### Vector Overlay

Exact vector scans must see committed vector writes immediately. Future ANN
indexing can lag, so this mission should introduce a committed vector-delta
overlay contract that exact scans include and background workers can drain later.

## Work Package Strategy

1. Define contracts and stress harness.
2. Replace clone-on-`BEGIN` with cheap snapshots.
3. Add commit queue and backpressure.
4. Coordinate checkpoint and vector overlay workers.
5. Harden stress tests and benchmarks.

## Risks

- Generation ownership can become memory-leaky if retain/release semantics are
  unclear. Tests should cover session deinit/rollback/commit cleanup.
- Queue semantics can accidentally change SQL transaction behavior. Existing
  transaction tests must remain stable.
- Vector overlay work can drift into ANN implementation. Keep it exact-scan and
  contract-only for this mission.
- Spec Kitty ownership metadata may still under-model integration touchpoints.
  WPs include primary owned files and describe integration surfaces explicitly.

## Validation

- `zig build test`
- Benchmark smoke with Phase 6 metrics:
  `zig build run -- benchmark --rows 100 --vectors 32 --dimensions 8 --operations 25`
- Targeted acceptance docs under
  `docs/acceptance-phase6-scalable-concurrency.md`
