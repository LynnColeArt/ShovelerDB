# ShovelerDB Embedding ABI

ShovelerDB's embedding ABI is the connector-facing contract for using the
database from host runtimes without introducing a server, daemon, network
protocol, replication layer, plugin surface, auth system, or storage-engine
selection. The ABI is intentionally small: future Go, Python, Java, PHP,
TypeScript/Node, .NET, and Rust connectors should all be thin adapters over the
same C boundary.

Phase 9 starts by stabilizing the contract before shipping language packages.
The checked-in header is authoritative for symbol names and enum values. This
document explains lifetime, ownership, diagnostics, and connector fixture
expectations that are easier to express in prose than in C declarations.

## Versioning

The first ABI surface is versioned as `0.1.0`:

- `SHOVELERDB_ABI_VERSION_MAJOR`
- `SHOVELERDB_ABI_VERSION_MINOR`
- `SHOVELERDB_ABI_VERSION_PATCH`

Major version `0` means the project is still allowed to revise the ABI while
the implementation and first connectors are being built. Connectors must check
the header/runtime version before claiming compatibility.

## Handles

The ABI uses opaque handles. Callers must not inspect, allocate, copy, or free
the underlying structures.

- `shovelerdb_database` owns an embedded database session rooted at a local
  filesystem path.
- `shovelerdb_result` owns the result of one SQL execution.
- `shovelerdb_row` is a row view owned by the result that produced it.

There is no global database singleton. Opening two database handles points to
two independent embedded instances, subject to the same filesystem and
checkpoint rules as the native Zig engine.

## Lifecycle

The minimum lifecycle is:

1. Call `shovelerdb_open_or_create(path, &db)`.
2. Execute SQL with `shovelerdb_execute(db, sql, &result)`.
3. Inspect the result kind, mutation count, columns, rows, and values.
4. Release each result with `shovelerdb_result_release(result)`.
5. Call `shovelerdb_checkpoint(db)` when the host wants durable persistence.
6. Close with `shovelerdb_close(db)`.

Every result returned through the ABI must be released, including mutation
results and empty results. `shovelerdb_result_release(NULL)` and
`shovelerdb_close(NULL)` are no-ops so connector cleanup paths can be simple.

## Ownership

ABI-visible memory is owned by ShovelerDB unless a function explicitly says
otherwise. Callers must not free strings, blobs, vectors, rows, results, or
database handles with host-runtime allocators.

String, blob, and vector accessors return borrowed views. A borrowed view is
valid until the owning `shovelerdb_result` is released. Connectors that expose
values after result release must copy the bytes into language-owned memory.

The ABI never exposes internal Zig row-store pointers, AST nodes, transaction
objects, allocator-owned slices, or result containers. Later implementation
work may copy more than the optimal amount of data at this boundary; safety and
predictable ownership are the Phase 9 priority.

## SQL Execution

`shovelerdb_execute` accepts one SQL statement using the currently accepted
ShovelerDB dialect. Connectors should route DDL, DML, `SELECT`, `BEGIN`,
`COMMIT`, and `ROLLBACK` through the same execution path rather than creating
language-specific transaction APIs in the first pass.

Result kinds are:

- `SHOVELERDB_RESULT_EMPTY`: the statement completed without rows or a mutation
  count.
- `SHOVELERDB_RESULT_MUTATION_COUNT`: the statement completed with a count of
  affected rows.
- `SHOVELERDB_RESULT_ROWS`: the statement produced row data.

The ABI does not expand the accepted SQL surface. Foreign keys, user-visible
temporary tables, replication/binlog SQL, users/grants/auth SQL, storage engine
selection, plugin/UDF management, daemon lifecycle commands, and historical SQL
mode compatibility remain rejected by design.

## Result Iteration

Connectors inspect result metadata before iterating:

- `shovelerdb_result_column_count`
- `shovelerdb_result_column_name`
- `shovelerdb_result_kind`
- `shovelerdb_result_mutation_count`

Rows are read with `shovelerdb_result_next(result, &row)`. The function returns
`SHOVELERDB_STATUS_OK` while a row is available and writes `NULL` to `row` at
end of stream. A row belongs to its result and is invalid after result release.

Values are accessed by column index from a row. Callers should first ask for
the `shovelerdb_value_kind`, then call the matching accessor. Calling a scalar
accessor for the wrong value kind returns `SHOVELERDB_STATUS_TYPE_ERROR`.

## Value Model

The first ABI value kinds map to the native ShovelerDB value model:

- `SHOVELERDB_VALUE_NULL`
- `SHOVELERDB_VALUE_INTEGER` (`int64_t`)
- `SHOVELERDB_VALUE_FLOAT` (`double`)
- `SHOVELERDB_VALUE_BOOLEAN` (`uint8_t`, `0` or `1`)
- `SHOVELERDB_VALUE_TEXT` (UTF-8 byte view)
- `SHOVELERDB_VALUE_BLOB` (opaque byte view)
- `SHOVELERDB_VALUE_VECTOR_F32` (`float` element view plus dimension)

Vector values are exposed as contiguous `float32` elements plus a dimension.
The view is borrowed from the result. Connectors should expose vector values as
language-native float arrays or typed-array views only after copying when their
runtime cannot enforce the result lifetime.

The first ABI does not add vector index/planner behavior. Connector vector
queries observe the exact SQL vector ranking already implemented in the Zig
engine.

## Diagnostics

Every ABI function returns a `shovelerdb_status`. `SHOVELERDB_STATUS_OK` is the
only success value. All other values are stable categories that connectors can
map to language-native exceptions or error types.

The status categories include:

- invalid argument
- invalid handle
- allocation failure
- parser error
- object/catalog error
- transaction error
- type error
- vector error
- persistence/open/checkpoint error
- I/O error
- unsupported SQL surface
- unknown internal error

`shovelerdb_status_diagnostic_code` maps statuses to broader diagnostic codes,
and `shovelerdb_status_message` returns a static English message for fallback
reporting. `shovelerdb_database_last_diagnostic` returns the last detailed
database-handle diagnostic when one is available. The returned diagnostic
message is borrowed and must be copied by connectors that need to keep it.

## Threading and Concurrency

The ABI inherits the embedded engine's concurrency model: many snapshot readers
can observe stable committed generations while writes are ordered through the
database's write path. The first ABI does not promise that one
`shovelerdb_database` handle is safe for arbitrary concurrent calls from
multiple host threads.

Connector rules for Phase 9:

- A connector may create separate host-runtime objects around separate database
  handles.
- A connector must serialize calls that share a single database handle unless a
  later ABI revision documents a stronger guarantee.
- A connector must not release a result while another host thread is reading
  rows or borrowed value views from it.
- A connector must keep checkpoint calls explicit and host-controlled.

## Connector Fixtures

Every future language connector must share the same acceptance behavior before
it is considered real:

1. Open or create a filesystem-backed database.
2. Create a table with scalar and vector columns.
3. Insert rows inside an explicit SQL transaction.
4. Commit and query rows back.
5. Run an exact vector ranking query.
6. Trigger and map a typed diagnostic, such as a vector-dimension mismatch or
   missing object error.
7. Release every result.
8. Checkpoint, close, reopen, and verify committed rows persist.

The connector fixture should not require a daemon process, background service,
network listener, auth configuration, replication setup, plugin installation,
or external storage engine.
