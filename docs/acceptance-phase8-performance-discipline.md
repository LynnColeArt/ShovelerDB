# Phase 8 Performance Discipline Acceptance

Generated during WP05 of `phase8-performance-discipline-01KT9RHT`.

## Validation Summary

```text
zig build test
status: pass
```

Required benchmark presets:

```text
zig build run -- benchmark --preset local-smoke
status: pass
```

```text
zig build run -- benchmark --preset acceptance-smoke --format json
status: pass
```

Additional JSON evidence checks:

```text
jq validation: acceptance-smoke emits valid JSON, all metrics include
allocation_count/allocation_bytes, and documented metric counts match
docs/performance-baselines.json.
status: pass
```

## Metric Contract

Phase 8 accepts these stable metric names:

- `insert_commit`
- `select_scan`
- `grouped_scan`
- `joined_filter`
- `point_lookup`
- `rollback_updates`
- `exact_vector_scan`
- `sql_vector_rank`
- `hybrid_filter_vector_rank`
- `persistence_checkpoint_reopen`
- `snapshot_begin`
- `queued_commit`
- `concurrent_read_write`
- `checkpoint_overlap`
- `vector_overlay_visibility`

## Requirement Evidence

| Requirement | Status | Evidence |
| --- | --- | --- |
| FR-001 | pass | `docs/performance.md` documents benchmark purpose, commands, presets, output fields, metric interpretation, limitations, and warn-only baseline policy. |
| FR-002 | pass | `src/cli/benchmark.zig` preserves text output and adds `--format json`; `src/cli/benchmark_metrics.zig` renders both text and JSON reports. |
| FR-003 | pass | `src/cli/benchmark.zig` defines `local-smoke` and `acceptance-smoke`; `docs/performance.md` and `docs/performance-baselines.json` document their row/vector/dimension/operation counts. |
| FR-004 | pass | `src/cli/benchmark_metrics.zig` implements `CountingAllocator`, `AllocationStats`, and allocation fields; `tests/integration/benchmark_output_acceptance.zig` validates allocation fields in text and JSON output. |
| FR-005 | pass | `src/cli/benchmark.zig` emits `point_lookup`; local and acceptance JSON smokes validate the metric name and count. |
| FR-006 | pass | `src/cli/benchmark.zig` emits `hybrid_filter_vector_rank` using metadata tag filtering plus vector distance ordering; `tests/integration/benchmark_workload_acceptance.zig` validates the metric contract. |
| FR-007 | pass | `src/cli/benchmark_workloads.zig` implements `runPersistenceCheckpointReopen`; its tests and benchmark smokes verify checkpoint/reopen preserves committed rows and cleans the smoke file. |
| FR-008 | pass | `src/cli/benchmark_workloads.zig` preserves Phase 6 metric names: `snapshot_begin`, `queued_commit`, `concurrent_read_write`, `checkpoint_overlap`, and `vector_overlay_visibility`; tests and CLI smokes validate they still appear. |
| FR-009 | pass | `tests/integration/benchmark_output_acceptance.zig` and `tests/integration/benchmark_workload_acceptance.zig` validate JSON shape, metric names, counts, and allocation fields without asserting absolute timings. |
| FR-010 | pass | `docs/performance-baselines.json` records warn-only preset counts and advisory delta thresholds with `hard_ci_gate: false`. |
| FR-011 | pass | `docs/project-plan.md` now describes Phase 8 as complete with presets, JSON, allocation visibility, workload metrics, acceptance evidence, post-merge review, and warn-only baseline guidance. |
| FR-012 | pass | `zig build test` passes with the full SQL, transaction, persistence, vector, view/procedure, adapted fixture, concurrency, and benchmark integration suites. |

## Accepted State

Phase 8 has made performance visible and repeatable enough for local
development and mission acceptance. The benchmark harness now has stable
presets, JSON output, allocation visibility, missing product workload metrics,
documented methodology, and warn-only baseline guidance.

Hard timing gates remain intentionally deferred. The project should collect
repeated baseline samples on stable CI hardware before turning performance
warnings into merge blockers.

## Spec Kitty Notes

Spec Kitty workflow anomalies observed during this mission were added to
`docs/spec-kitty-system-notes.md`, including protected-main status drift,
dependent lane base drift, and review allocation failures on status artifacts.
