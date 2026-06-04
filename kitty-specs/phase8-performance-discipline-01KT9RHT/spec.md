# Phase 8 Performance Discipline Spec

## Mission

Make ShovelerDB performance measurable, repeatable, and hard to regress while
the engine is still small enough to understand. Earlier missions added a
benchmark CLI and metrics for SQL execution, vector ranking, and Phase 6
concurrency. This mission turns that ad hoc benchmark surface into a disciplined
local performance harness with documented methodology, machine-readable output,
allocation visibility, and early regression signals.

The goal is not to chase peak numbers yet. The goal is to make cost visible for
the embedded agent-memory paths that define the product.

## Current Baseline

- `zig build run -- benchmark` reports text metrics for insert/commit,
  scanning, grouped scans, joined filters, rollback updates, exact vector scan,
  SQL vector ranking, snapshot begin, queued commit, concurrent read/write,
  checkpoint overlap, and vector overlay visibility.
- `zig build test` covers benchmark-adjacent behavior through integration
  tests, but benchmark output itself has limited structured validation.
- Allocation behavior is not yet reported by the benchmark harness.
- Regression thresholds are not yet defined, which is appropriate while the
  engine shape is still changing.

## Scope

- Add a documented benchmark methodology for local developer runs and future
  CI use.
- Make benchmark output available in a stable machine-readable format while
  preserving the human-readable CLI output.
- Track allocation counts/bytes for benchmarked hot paths where Zig allocator
  instrumentation can do so without hiding ownership or changing semantics.
- Cover the key embedded memory workloads: insert/commit, point lookup, scan,
  grouped scan, joined filter, transaction rollback, exact vector top-k,
  hybrid filter/vector ranking, persistence checkpoint/reopen smoke, and Phase
  6 concurrency metrics.
- Add benchmark smoke tests that validate metric names, dimensions, and basic
  nonzero counts without depending on wall-clock timing.
- Introduce a conservative regression-baseline document or config in warn-only
  mode until the engine stabilizes enough for hard thresholds.

## Non-Goals

- No benchmark-driven semantic changes without matching acceptance tests.
- No approximate nearest-neighbor index implementation.
- No unsafe allocator tricks, global hidden instrumentation, or production
  behavior changes solely for benchmark convenience.
- No cloud benchmark service, daemon benchmark runner, or multi-node test
  harness.
- No hard CI performance gate until repeatability has been proven on the
  target developer/CI machines.
- No language connector benchmark work; connector packages remain Phase 9.

## User Scenarios

### Scenario 1: A Developer Runs a Stable Benchmark Preset

A contributor can run a documented local preset and see the core hot paths:

```bash
zig build run -- benchmark --preset local-smoke
```

The command reports the same metric names each time and explains the configured
rows, vectors, dimensions, operations, and warmup/sample behavior.

### Scenario 2: Automation Reads Benchmark Results

A script can request JSON output and compare metric names, counts, elapsed
time, throughput, and allocation data without parsing human text:

```bash
zig build run -- benchmark --rows 1000 --vectors 256 --dimensions 16 --operations 100 --format json
```

### Scenario 3: Allocation Regressions Become Visible

If a hot path starts allocating per row where it previously allocated per
query, the benchmark output surfaces allocation counts/bytes so the regression
is visible before a user feels it.

### Scenario 4: Thresholds Start as Guidance

The project can store benchmark baseline guidance in docs or config and report
warn-only deltas. Hard failure thresholds can wait until the engine and CI
environment are stable enough to make the signal meaningful.

## Functional Requirements

- **FR-001**: Add `docs/performance.md` documenting benchmark purpose,
  methodology, presets, interpretation, and current limitations.
- **FR-002**: Keep existing human-readable benchmark output stable enough for
  developers, while adding a `--format json` or equivalent structured output
  mode.
- **FR-003**: Add benchmark presets for at least `local-smoke` and
  `acceptance-smoke`, with documented row/vector/dimension/operation counts.
- **FR-004**: Report allocation counts and bytes for benchmarked workloads
  using explicit Zig allocator instrumentation.
- **FR-005**: Add a point-lookup metric distinct from full table scans.
- **FR-006**: Add or refine a hybrid filter/vector ranking metric that combines
  metadata filtering with vector distance ordering.
- **FR-007**: Add a persistence-facing metric or smoke path that measures
  checkpoint/save and reopen behavior without corrupting durable state.
- **FR-008**: Preserve and validate existing Phase 6 metrics:
  `snapshot_begin`, `queued_commit`, `concurrent_read_write`,
  `checkpoint_overlap`, and `vector_overlay_visibility`.
- **FR-009**: Add benchmark output tests that validate metric names, counts,
  dimensions, and JSON shape without asserting fragile absolute timing.
- **FR-010**: Add a baseline or threshold artifact in warn-only mode that can
  later become a CI gate after repeatability is proven.
- **FR-011**: Refresh roadmap and acceptance docs so Phase 8 status reflects
  the benchmark harness and remaining performance work honestly.
- **FR-012**: Existing SQL, transaction, persistence, vector, view/procedure,
  adapted fixture, and concurrency tests must continue to pass.

## Acceptance

- `zig build test` passes.
- `zig build run -- benchmark --preset local-smoke` passes and reports all
  documented metrics.
- `zig build run -- benchmark --preset acceptance-smoke --format json` passes
  and emits valid JSON with metric names, counts, elapsed time, throughput, and
  allocation fields.
- A test validates structured benchmark output shape without depending on
  machine-specific timings.
- `docs/performance.md` explains how to run, read, and compare benchmark
  output.
- A Phase 8 acceptance doc maps every functional requirement to test, CLI, or
  documentation evidence.

## Risks

- Benchmarks can become fake comfort if they only measure tiny happy paths.
  Keep workloads tied to product workflows and acceptance fixtures.
- Hard timing thresholds can become noisy before CI hardware is stable. Start
  with warn-only baselines and promote them later.
- Allocation instrumentation must not obscure ownership. Prefer explicit local
  counting wrappers over hidden global state.
- Performance work can tempt broad rewrites. This mission should expose cost
  first and only make narrowly justified optimizations when tests demand them.
