# Phase 7 Views and Procedures Hardening Plan

**Branch**: `main`  
**Date**: 2026-06-04  
**Spec**: `kitty-specs/phase7-views-procedures-hardening-01KT9RHH/spec.md`

## Summary

Phase 7 hardens ShovelerDB's reusable SQL logic. Views and procedures already
exist at an MVP depth; this mission makes their behavior reliable across richer
query sources, transactions, persistence, adapted MariaDB fixtures, and stable
unsupported diagnostics.

The implementation should reuse the existing parser, row-source executor,
catalog, persistence, and procedure-body evaluator. It should not create a
separate stored-program runtime or accept MariaDB server metadata.

## Technical Context

**Language/Version**: Zig, current local toolchain used by `zig build test`.  
**Primary Dependencies**: Zig standard library only for core engine/runtime.  
**Storage**: Embedded filesystem snapshot/reopen path in `src/db/persistence.zig`.  
**Testing**: `zig build test`, integration tests, adapted fixture execution,
CLI smoke commands, and acceptance docs.  
**Target Platform**: Embedded local Linux/developer checkout; no daemon.  
**Project Type**: Single Zig library/CLI project.  
**Performance Goals**: Preserve Phase 6 benchmark coverage; no avoidable
per-row clone explosions from view/procedure execution.  
**Constraints**: No foreign keys, temp tables, auth/admin SQL, replication,
plugins, server lifecycle, or full MariaDB stored-program parity.  
**Scale/Scope**: Correctness for practical agent-memory schemas and fixtures;
not full MariaDB compatibility.

## Architecture Direction

### Views

Views should remain catalog entries that store supported `SELECT` definitions.
Execution should flow through the same row-source executor used by direct
queries, including aliases, qualified identifiers, joins, CTEs, derived tables,
grouping, ordering, limits, and vector functions where already supported.

Key modules:

- `src/db/view.zig`
- `src/db/catalog.zig`
- `src/db/executor.zig`
- `src/db/query_source.zig`
- `src/db/persistence.zig`
- `src/sql/parser.zig`
- `src/sql/ast.zig`

The implementation should prefer tightening name/alias behavior and lifecycle
diagnostics over broad new syntax.

### Procedures

Procedures should stay constrained and transactional. `CALL` should bind
arguments, execute supported body statements through the caller session, and
preserve rollback/commit behavior equivalent to direct SQL. Unsupported body
syntax should reject before partial catalog mutation where possible.

Key modules:

- `src/db/procedure.zig`
- `src/sql/procedure_body.zig`
- `src/db/executor.zig`
- `src/db/transaction.zig`
- `src/db/catalog.zig`
- `src/db/persistence.zig`

Bounded loops and local variables are in scope. Cursors, handlers, recursion,
dynamic SQL, packages, routine functions, `OUT`/`INOUT`, and server diagnostics
areas remain out of scope.

### Fixtures and Docs

Adapted fixtures are the bridge from MariaDB references to ShovelerDB-native
behavior. Phase 7 should expand or split the current view/procedure descriptors
only when they add executable acceptance value.

Docs to refresh:

- `docs/project-plan.md`
- `docs/sql-dialect.md`
- `docs/reference-corpus-snapshot.md`
- `docs/acceptance-phase7-views-procedures.md`

## Work Package Strategy

1. View expansion and lifecycle diagnostics.
2. View persistence/reopen and adapted fixture coverage.
3. Procedure argument binding and transaction semantics.
4. Procedure diagnostics and loop/body hardening.
5. Acceptance docs, roadmap refresh, and validation.

Keep integration touchpoints explicit in WP descriptions because parser,
executor, catalog, persistence, and tests will overlap conceptually even when
owned-file metadata is narrow.

## Testing Strategy

- Add focused integration tests under `tests/integration/`.
- Extend `tests/fixtures/mariadb-adapted/` only for durable behavior evidence.
- Keep unsupported stored-program tests as expected diagnostics.
- Run full `zig build test` before any WP handoff.
- Include CLI smoke examples for representative view/procedure paths when they
help acceptance evidence.

## Risks

- View execution may accidentally fork direct-query semantics. Reuse the
row-source executor.
- Procedure execution may become a second interpreter. Keep it small and
delegate SQL statements to the existing executor.
- MariaDB fixtures contain server metadata. Adapt behavior, not the server
model.
- Spec Kitty lane ownership may under-model integration touchpoints. Document
them in each WP before implementation begins.

## Validation

- `zig build test`
- Targeted CLI execute smoke for a rich view.
- Targeted CLI execute smoke for a procedure using variables, branch, and loop.
- MTR-lite adapted fixture execution for promoted view/procedure descriptors.
- `docs/acceptance-phase7-views-procedures.md` maps all FRs to evidence.

## Project Structure

```
kitty-specs/phase7-views-procedures-hardening-01KT9RHH/
├── spec.md
├── plan.md
├── tasks.md
├── acceptance-matrix.json
└── tasks/

src/db/
├── catalog.zig
├── executor.zig
├── persistence.zig
├── procedure.zig
├── query_source.zig
└── view.zig

src/sql/
├── ast.zig
├── parser.zig
└── procedure_body.zig

tests/integration/
tests/fixtures/mariadb-adapted/
docs/
```

**Structure Decision**: Use the existing single-project Zig layout. Add new
modules only if the current view/procedure modules become too broad to hold in
one head.
