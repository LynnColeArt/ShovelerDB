# Phase 8 Performance Discipline Plan

**Branch**: `main`  
**Date**: 2026-06-04  
**Spec**: `kitty-specs/phase8-performance-discipline-01KT9RHT/spec.md`

## Summary

Phase 8 turns the existing benchmark CLI into a disciplined performance surface:
documented methodology, stable presets, structured output, allocation
visibility, smoke tests, and warn-only baseline guidance. The mission should
make costs visible before pursuing broad optimizations.

The implementation should preserve human-readable benchmark output while adding
machine-readable output for automation. It should not change SQL semantics or
introduce hidden global instrumentation.

## Technical Context

**Language/Version**: Zig, current local toolchain used by `zig build test`.  
**Primary Dependencies**: Zig standard library only.  
**Storage**: Embedded filesystem checkpoint/reopen path for persistence-facing
benchmark smokes.  
**Testing**: `zig build test`, benchmark output shape tests, CLI smoke commands,
and acceptance docs.  
**Target Platform**: Local embedded developer workflow; future CI-compatible
but not CI-gated on hard timing thresholds yet.  
**Project Type**: Single Zig library/CLI project.  
**Performance Goals**: Stable measurement of hot paths and allocation behavior;
warn-only regression signals until repeatability is proven.  
**Constraints**: No semantic rewrites without acceptance tests, no ANN work, no
server/connector benchmark scope, no hidden global instrumentation.  
**Scale/Scope**: Local smoke and acceptance-scale runs for thousands of rows and
hundreds of vectors; not production-scale load testing.

## Architecture Direction

### Benchmark CLI

Extend `src/cli/benchmark.zig` with a small option model for presets and output
format. Preserve the current text report, and add a JSON report that scripts can
consume without scraping.

Expected metric fields:

- name
- count
- elapsed_ns
- throughput_per_s
- allocation_count
- allocation_bytes
- optional detail fields for workload-specific values

### Allocation Measurement

Use explicit allocator instrumentation around each benchmark workload. The
measurement should be local to benchmark execution and must not alter
production allocator ownership. Prefer a small helper in the CLI benchmark area
unless a repo-wide allocator utility already exists.

### Workloads

Preserve existing metrics and add the missing product hot paths:

- insert/commit
- point lookup
- select scan
- grouped scan
- joined filter
- rollback updates
- exact vector scan
- SQL vector rank
- hybrid filter/vector rank
- persistence checkpoint/reopen smoke
- Phase 6 concurrency metrics

### Baselines

Add docs or config for baseline guidance in warn-only mode. Hard thresholds are
deferred until CI hardware and benchmark variance are understood.

Docs to add or refresh:

- `docs/performance.md`
- `docs/project-plan.md`
- `docs/acceptance-phase8-performance-discipline.md`

## Work Package Strategy

1. Benchmark option model, presets, and structured metric schema.
2. Allocation measurement and benchmark output tests.
3. Missing workload metrics: point lookup, hybrid vector/filter, and
   persistence checkpoint/reopen.
4. Warn-only baseline guidance and docs.
5. Acceptance evidence and validation.

The first WP should avoid changing workload behavior while establishing the
shape later WPs use.

## Testing Strategy

- Add tests that invoke benchmark helpers directly where possible.
- Add CLI-level smoke coverage for JSON output if the build system supports it
  without brittle wall-clock assertions.
- Assert metric names, counts, dimensions, and JSON shape.
- Do not assert absolute throughput in normal tests.
- Keep `zig build test` as the primary correctness gate.

## Risks

- Benchmarks can become misleading if tiny synthetic paths are mistaken for
real product workloads. Tie workloads to SQL/vector/concurrency acceptance
scenarios.
- JSON output can ossify too early. Keep the schema small and versionable.
- Allocation counters can hide ownership if they are too magical. Keep the
instrumentation explicit.
- Hard timing gates can become noisy. Start warn-only.

## Validation

- `zig build test`
- `zig build run -- benchmark --preset local-smoke`
- `zig build run -- benchmark --preset acceptance-smoke --format json`
- JSON output shape validation in tests.
- `docs/acceptance-phase8-performance-discipline.md` maps all FRs to evidence.

## Project Structure

```
kitty-specs/phase8-performance-discipline-01KT9RHT/
├── spec.md
├── plan.md
├── tasks.md
├── acceptance-matrix.json
└── tasks/

src/cli/
├── benchmark.zig
└── commands.zig

tests/integration/
docs/
```

**Structure Decision**: Keep performance work inside the existing CLI,
integration test, and docs surfaces. Add shared helper modules only if repeated
benchmark metric/allocation code becomes harder to understand inline.
