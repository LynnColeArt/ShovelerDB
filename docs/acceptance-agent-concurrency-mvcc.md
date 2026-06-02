# Agent Concurrency MVCC Acceptance

Generated for `agent-concurrency-mvcc-01KT499P`.

## Target Evidence

- Reader sessions capture a stable snapshot at `BEGIN`.
- Writer commits serialize through a commit sequence.
- Overlapping writer sessions can commit in order without losing staged rows.
- The benchmark CLI reports `snapshot_read_write`.

## Validation Summary

```text
zig build test
status: pass
```

Benchmark smoke:

```bash
zig build run -- benchmark --rows 20 --vectors 8 --dimensions 3 --operations 5
```

The benchmark reports the existing hot paths plus the new concurrency metric:

```text
insert_commit
select_scan
grouped_scan
joined_filter
rollback_updates
exact_vector_scan
sql_vector_rank
snapshot_read_write
```

Observed small-run `snapshot_read_write` evidence:

```text
count: 5
elapsed_ns: 567596
throughput_per_s: 8809
```

## Notes

This mission establishes correctness before optimizing snapshot cost. Snapshot
capture currently clones table metadata and row stores at `BEGIN`; later
missions can replace that with shared immutable pages or version chains.
