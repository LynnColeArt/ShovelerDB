# Phase 9 Embedding ABI Foundation Plan

**Branch**: `main`  
**Date**: 2026-06-05  
**Spec**: `kitty-specs/phase9-embedding-abi-foundation-01KTAQXB/spec.md`

## Summary

Phase 9 starts by making ShovelerDB embeddable through a small C ABI. The
implementation should wrap the existing Zig executor/persistence surfaces in
opaque handles, copied result/value accessors, stable diagnostics, and explicit
release functions. Language connectors can then bind this ABI without learning
ShovelerDB's internal allocator, row-store, transaction, or AST structures.

This plan deliberately avoids full language connector packages. The first
mission should finish the ABI contract, docs, header, and acceptance smoke that
future Go, Python, Java, PHP, TypeScript/Node, .NET, and Rust connectors share.

## Technical Context

**Language/Version**: Zig, using the current local toolchain and `zig build test`.  
**Primary Dependencies**: Zig standard library only; C ABI must not add runtime
dependencies or a server process.  
**Storage**: Existing filesystem snapshot/checkpoint database file managed by
`src/db/database.zig` and executor snapshot export/import.  
**Testing**: `zig build test`, ABI-focused integration tests, header existence
and symbol-shape checks, and connector fixture documentation review.  
**Target Platform**: Local embedded library consumers; ABI shape should be
portable across common C-compatible host runtimes.  
**Project Type**: Single Zig library/CLI project with docs and integration
tests.  
**Performance Goals**: ABI calls should avoid avoidable per-cell allocations
after result materialization, but safety and ownership clarity outrank
micro-optimization in this mission.  
**Constraints**: No daemon, sockets, auth, replication, plugins, storage-engine
selection, foreign keys, user-visible temp tables, or hidden global database
state.  
**Scale/Scope**: One ABI foundation and one shared connector fixture, not seven
language packages.

## Architecture Direction

### ABI Layer

Add `src/abi/c_api.zig` as the exported C boundary. It should own all handles
behind opaque pointers:

- database handle
- result handle
- error/status reporting surface

The ABI layer should initialize its own allocator per database or handle
bundle, call into `src/db/executor.zig` for SQL execution, and call persistence
helpers when opening, checkpointing, and closing filesystem-backed databases.
Foreign callers must never receive internal Zig slices or struct pointers.

### Header

Add `include/shovelerdb.h` as the checked-in ABI contract. The header should
declare:

- ABI version constants
- opaque handle typedefs
- status/diagnostic enum
- result kind enum
- value kind enum
- open/close/checkpoint functions
- SQL execute function
- result metadata, row count, column names, value accessors, and release
  functions

The Zig exports and header should stay intentionally boring: C integer return
codes, pointer out-params, and explicit release functions.

### Result and Value Representation

The ABI result handle owns copied result data. Value accessors should expose:

- null
- integer
- float
- boolean
- text bytes plus length
- blob bytes plus length
- vector float32 pointer, dimension, and element type

For this mission, result data may remain valid until the result handle is
released. Callers must copy data they want to keep after release.

### Diagnostics

Create a single ABI diagnostic enum that maps parser, object lookup,
transaction, type, vector, persistence, invalid-handle, and allocation failures.
The ABI should expose at least a stable code and a human-readable diagnostic
string. Connectors should map codes, not parse messages.

### Embedded Semantics

Transactions should be available through SQL execution (`BEGIN`, DML,
`COMMIT`, `ROLLBACK`) in this mission. Explicit foreign transaction objects can
wait until a later connector ergonomics mission if users need them.

### Documentation

Add `docs/embedding-abi.md` with:

- ABI lifecycle and ownership rules
- thread/concurrency expectations
- result/value access patterns
- vector encoding
- diagnostic mapping
- connector fixture commands and expected behavior
- clear non-goals for server lifecycle and full connector packages

Refresh README and `docs/project-plan.md` to say Phase 9 is active for ABI
foundation work, not complete for all language connectors.

## Work Package Strategy

1. **ABI Contract and Docs**: Write the header, ABI docs, diagnostic/value
   vocabulary, and roadmap refresh.
2. **Handle Lifecycle and SQL Execution**: Implement database/result handles,
   open-or-create, close, checkpoint, SQL execution, and cleanup.
3. **Result Iteration and Value Access**: Expose columns, row counts, value
   kinds, scalar/text/blob/vector accessors, and release behavior.
4. **Diagnostics and Acceptance Smoke**: Map typed errors, add ABI integration
   tests for success and failure paths, and validate reopen behavior.
5. **Connector Fixture Handoff**: Add reusable fixture docs and final
   acceptance evidence so future connector missions can bind the ABI without
   rediscovering semantics.

The first three packages are implementation-heavy and sequential. Docs and
acceptance work can still be reviewed independently because the ABI contract is
the authoritative surface.

## Testing Strategy

- Add a Zig integration test that calls the exported ABI functions directly,
  treating them as a foreign caller would.
- Cover handle lifecycle: null/invalid handles, idempotent release, and
  resource cleanup.
- Cover SQL execution: create table, begin, insert, commit, select, rollback,
  and mutation count.
- Cover vector result access through a nearest-neighbor query.
- Cover persistence: checkpoint/close/reopen and verify committed rows.
- Cover diagnostics: parse error, unknown object, transaction-required or
  transaction-state error, vector-dimension error, and invalid handle.
- Keep `zig build test` as the primary correctness gate.

## Risks

- **ABI overreach**: A broad ABI is harder to stabilize. Keep this mission to
  the minimum needed for real connectors.
- **Ownership leaks**: Exposing internal Zig memory would make connectors
  unsafe. Use opaque handles and copied/caller-borrowed data tied to result
  lifetime.
- **Diagnostic drift**: Connector-specific error names can fragment. Keep one
  ABI enum and document it.
- **Persistence split**: ShovelerDB currently has executor and persistence
  surfaces that meet through snapshot export/import. The ABI should bridge them
  deliberately rather than inventing a second engine path.
- **Connector scope creep**: Full language packages are Phase 9 follow-up
  missions after the ABI foundation lands.

## Project Structure

```
include/
└── shovelerdb.h

src/
├── abi/
│   └── c_api.zig
├── db/
├── sql/
└── vector/

tests/
└── integration/
    └── abi_acceptance.zig

docs/
├── embedding-abi.md
└── project-plan.md
```

**Structure Decision**: Keep the ABI in a dedicated `src/abi/` boundary module
and keep connector-facing docs in `docs/`. Do not put language-specific SDKs in
this mission; future missions can add `bindings/<language>/` or
`connectors/<language>/` after the C ABI is stable.
