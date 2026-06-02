# Phase 6 Scalable Concurrency Spec

## Mission

Finish the remaining Phase 6 concurrency shape for ShovelerDB: move from the
first correct clone-on-`BEGIN` MVCC slice to a scalable embedded concurrency
model for agent memory workloads.

The prior mission `agent-concurrency-mvcc-01KT499P` established correctness:
reader snapshots stay stable and writer commits serialize deterministically. This
mission keeps those semantics sacred while replacing the obvious scaling limits
with structures that can support hundreds or thousands of local agent reads and
writes.

## Scope

- Define the durable concurrency contract for sessions, snapshots, commits,
  checkpoints, and vector overlays.
- Replace eager snapshot cloning with generation-style snapshot handles or an
  equivalent cheap read snapshot model.
- Add an ordered commit queue with explicit queue depth, commit sequencing, and
  typed backpressure diagnostics.
- Coordinate checkpoints with committed generations so readers are not blocked
  by save activity.
- Add a vector write overlay contract so exact vector reads see newly committed
  vectors before future ANN/background indexing exists.
- Expand concurrency stress tests and benchmark metrics enough to make
  regressions visible.

## Non-Goals

- No server daemon, network protocol, replication, auth, plugins, or cloud
  service.
- No foreign keys or user-visible temporary tables.
- No approximate nearest-neighbor index implementation in this mission.
- No language connector work; that belongs in future Phase 9.
- No promise of lock-free internals. Correct bounded coordination is acceptable
  before chasing fancy lock-free designs.
- No fully concurrent DDL. DDL may remain serialized and conservative.

## Functional Requirements

- **FR-001**: Document the Phase 6 concurrency contract, including session
  lifecycle, snapshot visibility, write ordering, backpressure, checkpointing,
  and vector overlay visibility.
- **FR-002**: Read transactions must acquire snapshots in O(1) or near-O(1)
  time with respect to row count; they must not clone every row at `BEGIN`.
- **FR-003**: Reader snapshots must remain stable while later writer commits,
  checkpoint operations, and vector overlay updates occur.
- **FR-004**: Writer commits must pass through one ordered commit sequencer that
  assigns monotonically increasing commit sequence numbers.
- **FR-005**: The commit sequencer must expose bounded queue configuration and a
  typed backpressure diagnostic when write pressure exceeds the configured
  budget.
- **FR-006**: Rollback must remain local to the writer session and must not
  enqueue commit work or advance the commit sequence.
- **FR-007**: Checkpoint requests must snapshot a committed generation and write
  durable state without mutating active reader snapshots.
- **FR-008**: Checkpoint failures must leave the last durable generation intact
  and must not corrupt in-memory committed state.
- **FR-009**: Vector writes must be visible to exact SQL/vector scans through a
  committed overlay even before a future background vector index is built.
- **FR-010**: The vector overlay contract must expose enough hooks for a future
  background vector index worker to drain committed vector deltas.
- **FR-011**: Concurrency tests must cover many interleaved readers and writers,
  queue backpressure, rollback under pressure, checkpoint overlap, and vector
  overlay visibility.
- **FR-012**: The benchmark CLI must report separate metrics for snapshot begin,
  queued commit, concurrent read/write, checkpoint overlap, and vector overlay
  visibility.
- **FR-013**: Existing SQL, transaction, view, procedure, vector, MTR-lite, and
  persistence acceptance tests must continue to pass.
- **FR-014**: The implementation must preserve embedded-first APIs and must not
  introduce server lifecycle concepts.

## Acceptance

- `zig build test` passes.
- `zig build run -- benchmark --rows 100 --vectors 32 --dimensions 8 --operations 25`
  reports the new Phase 6 concurrency metrics.
- A stress test proves readers keep stable snapshots while writers commit and a
  checkpoint runs.
- A test proves queue backpressure returns a typed diagnostic without corrupting
  transaction state.
- A test proves committed vector rows are visible through the overlay path before
  any future ANN index worker is implemented.
- `docs/concurrency.md` and `docs/project-plan.md` describe the updated Phase 6
  semantics and remaining future work.
