# ShovelerDB Performance Discipline

ShovelerDB benchmarks are a visibility tool first. They make the embedded
SQL/vector memory hot paths repeatable enough to compare during development,
without pretending that early local timings are production capacity numbers.

## Commands

Use the local smoke preset while editing benchmarked code:

```sh
zig build run -- benchmark --preset local-smoke
```

Use the acceptance preset when collecting mission or release evidence:

```sh
zig build run -- benchmark --preset acceptance-smoke --format json
```

The presets intentionally stay small enough for a developer machine:

| Preset | Rows | Vectors | Dimensions | Operations |
| --- | ---: | ---: | ---: | ---: |
| `local-smoke` | 1000 | 256 | 16 | 100 |
| `acceptance-smoke` | 2000 | 512 | 32 | 200 |

Ad hoc runs can still override individual values:

```sh
zig build run -- benchmark --rows 100 --vectors 32 --dimensions 8 --operations 10 --format json
```

## Output

Human-readable output remains the default. JSON output is available for tools
that should not scrape text. Each metric reports:

- `name`: stable metric identifier.
- `count`: the workload unit count for that metric.
- `elapsed_ns`: elapsed nanoseconds for the measured block.
- `throughput_per_s`: count divided by elapsed time.
- `allocation_count`: allocation calls observed through the benchmark counting
  allocator.
- `allocation_bytes`: bytes observed through the benchmark counting allocator.

The benchmark also reports the configured `rows`, `vectors`, `dimensions`, and
`operations`, plus a nearest-vector summary for the exact vector scan path.

## Metrics

Current benchmark metrics are:

- `insert_commit`: insert rows in a transaction and commit them.
- `select_scan`: scan the scalar memory table.
- `grouped_scan`: group scalar rows and order aggregate results.
- `joined_filter`: join memory rows to metadata tags and filter by tag.
- `point_lookup`: run indexed-shape point lookups separately from full scans.
- `rollback_updates`: update rows inside a transaction and roll them back.
- `exact_vector_scan`: run in-memory exact top-k vector search.
- `sql_vector_rank`: rank persisted vector rows with SQL distance ordering.
- `hybrid_filter_vector_rank`: combine metadata filtering with vector distance
  ordering.
- `persistence_checkpoint_reopen`: checkpoint a tiny durable database file,
  reopen it, and verify committed rows are intact.
- `snapshot_begin`: begin and roll back read snapshots.
- `queued_commit`: run ordered commit-queue writes.
- `concurrent_read_write`: keep a reader snapshot open while writes commit.
- `checkpoint_overlap`: verify overlapping checkpoint attempts are rejected
  while readers continue.
- `vector_overlay_visibility`: drain committed vector overlay candidates.

The Phase 6 metrics are intentionally preserved because they protect the
snapshot, queue, checkpoint, and vector-overlay behavior that makes ShovelerDB
agent-shaped rather than single-user toy storage.

## Baselines

`docs/performance-baselines.json` is the warn-only baseline artifact. It records
the stable presets, expected metric names, expected counts, and warning policy.
It does not set hard elapsed-time or allocation ceilings yet.

Automation may use the artifact to warn when:

- A documented metric disappears.
- A preset emits a different count than expected.
- Elapsed time or allocation deltas exceed the warn-only percentages after a
  local team baseline has been collected.

Warnings should prompt review, not block merges. Hard timing gates remain
deferred until the project has enough repeated runs on stable CI hardware to
separate real regressions from machine noise.

## Interpreting Results

Compare like with like: same preset, same build mode, same machine class, and a
quiet enough system to avoid obvious background noise. Treat a single run as a
hint. Treat a repeated trend as evidence.

Allocation fields are especially useful during engine work. A path that starts
allocating per row instead of per query deserves attention even if the timing
looks acceptable on a small smoke preset.

These benchmarks are not production load tests. They are local guardrails for
the embedded database paths that matter now: SQL execution, vector ranking,
durable checkpoint/reopen, and concurrency visibility.
