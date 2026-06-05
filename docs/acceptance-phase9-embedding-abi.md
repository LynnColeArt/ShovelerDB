# Phase 9 Acceptance: Embedding ABI Foundation

Mission: `phase9-embedding-abi-foundation-01KTAQXB`

Phase 9 completes the embedding ABI foundation that future language connectors
will share. This mission intentionally stops at the C ABI, connector fixture,
diagnostics vocabulary, ownership rules, and acceptance smoke. Full Go, Python,
Java, PHP, TypeScript/Node, .NET, and Rust connector packages remain follow-up
work.

## Validation

The Phase 9 acceptance set is:

```sh
zig build test
zig fmt --check build.zig src/abi/c_api.zig src/abi/diagnostics.zig src/abi/handles.zig src/abi/result.zig src/abi/value_access.zig src/lib.zig tests/integration/abi_acceptance.zig
git diff --check
printf '#include "include/shovelerdb.h"\nint main(void) { return (int)shovelerdb_status_diagnostic_code(SHOVELERDB_STATUS_VECTOR_ERROR); }\n' | cc -x c -std=c99 -Wall -Wextra -pedantic -fsyntax-only -
```

## Requirement Evidence

| Requirement | Evidence |
| --- | --- |
| FR-001: Document ABI purpose, lifecycle, threading, ownership, error model, result iteration, vector representation, and connector fixture contract. | `docs/embedding-abi.md` covers versioning, handles, lifecycle, ownership, SQL execution, result iteration, value model, diagnostics, threading/concurrency, and connector fixtures. |
| FR-002: Add a C ABI module and header with opaque handles, row/value access, and status reporting. | `include/shovelerdb.h` declares opaque `shovelerdb_database`, `shovelerdb_result`, and `shovelerdb_row` handles; status, diagnostic, result, and value enums; view structs; lifecycle, execution, result, value, and diagnostic symbols. `src/abi/c_api.zig` exports the matching C ABI. |
| FR-003: Support open-or-create and close for filesystem-backed embedded databases without daemon or singleton requirements. | `shovelerdb_open_or_create`, `shovelerdb_checkpoint`, and `shovelerdb_close` are implemented through `src/abi/c_api.zig` and `src/abi/handles.zig`. `tests/integration/abi_acceptance.zig` opens a temporary database path, checkpoints, closes, reopens, and verifies persisted rows. |
| FR-004: Support SQL execution through the ABI for DDL, DML, transactions, and SELECT over the accepted dialect. | `shovelerdb_execute` in `src/abi/c_api.zig` routes statements through the embedded SQL path. `tests/integration/abi_acceptance.zig` executes `CREATE TABLE`, `BEGIN`, `INSERT`, `COMMIT`, vector-ranking `SELECT`, and persistence verification `SELECT` through the ABI. |
| FR-005: Expose result metadata and row/value iteration for null, integer, float, boolean, text, blob, and float32 vector values. | `include/shovelerdb.h` declares result metadata, row iteration, `shovelerdb_row_value_kind`, scalar accessors, text/blob view accessors, and `shovelerdb_row_value_vector_f32`. `src/abi/result.zig` and `src/abi/value_access.zig` implement the result/value layer. The ABI acceptance smoke reads integer, text, float, and vector values and exercises type-error status on a mismatched accessor. |
| FR-006: Make ABI-owned results and strings explicitly releasable, with idempotent cleanup and no caller responsibility for Zig allocators. | Results are released by `shovelerdb_result_release`; null release is accepted in `tests/integration/abi_acceptance.zig`. Text, blob, vector, and diagnostic message views are explicitly documented as result- or database-owned borrowed views in `docs/embedding-abi.md` and `docs/connector-fixtures.md`; callers copy them only when host-runtime lifetime requires it. |
| FR-007: Expose stable ABI diagnostic/status codes for parser, object, transaction, type, vector, persistence, invalid-handle, and allocation failures. | `include/shovelerdb.h` declares status and diagnostic enums. `src/abi/diagnostics.zig` centralizes status-to-diagnostic mapping and fallback messages. `shovelerdb_status_diagnostic_code`, `shovelerdb_status_message`, and `shovelerdb_database_last_diagnostic` are exported from `src/abi/c_api.zig`. The ABI acceptance smoke validates vector-error mapping and invalid-handle checkpoint status. |
| FR-008: Add an ABI acceptance smoke covering open, table creation, transaction inserts, vector ranking, typed error, checkpoint/close/reopen, and persistence verification. | `tests/integration/abi_acceptance.zig` is the canonical smoke and covers the full lifecycle. `build.zig` wires it into `zig build test`. |
| FR-009: Add reusable connector fixture documentation. | `docs/connector-fixtures.md` defines the shared fixture future language connectors must pass and points back to `tests/integration/abi_acceptance.zig`, `docs/embedding-abi.md`, and `include/shovelerdb.h`. |
| FR-010: Keep the existing SQL, transaction, persistence, view/procedure, vector, concurrency, adapted fixture, and benchmark tests passing. | `zig build test` is the acceptance command and includes the library, CLI, integration, adapted fixture, vector, concurrency, and benchmark-output/workload checks wired in `build.zig`. |
| FR-011: Refresh roadmap and README status so Phase 9 is active only for ABI foundation. | `README.md` and `docs/project-plan.md` describe Phase 9 as active for the embedding ABI foundation and call out full language connector packages as follow-up work. |

## Boundary Check

Phase 9 did not add a server lifecycle, daemon, socket protocol, network
listener, auth layer, replication/binlog surface, plugin system, storage-engine
selection, or user-visible temporary-table behavior. Connector integration is
through the embedded C ABI only.

## Spec Kitty Notes

WP05 did not expose a new Spec Kitty workflow anomaly class. The repeated
protected-main, lane-state, and owned-files/integration-touchpoint patterns
observed during Phase 9 are already tracked in `docs/spec-kitty-system-notes.md`.
