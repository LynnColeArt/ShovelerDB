# ShovelerDB Connector Fixtures

This fixture defines the minimum shared behavior every language connector must
pass before it is considered real. It exercises the C ABI as the product
boundary: embedded database handles, SQL execution, typed result access,
diagnostics, cleanup, checkpoint, and reopen.

The fixture must not require a daemon, socket listener, network protocol,
auth configuration, replication setup, plugin installation, storage-engine
selection, or user-visible temporary table behavior.

## Scope

Future Go, Python, Java, PHP, TypeScript/Node, .NET, and Rust connectors should
all implement this fixture against the checked-in `include/shovelerdb.h` ABI.
Language-specific tests may wrap the fixture in idiomatic APIs, but the
observable behavior must stay identical so connector drift is easy to catch.

Connector packages may add more tests for host-runtime ergonomics. Those tests
are supplemental; they do not replace this shared fixture.

## Preconditions

- Load or link the ShovelerDB C ABI and verify version `0.1.0` through both the
  header constants and runtime version functions.
- Create a fresh filesystem-backed database path for each fixture run.
- Serialize calls that share one `shovelerdb_database` handle.
- Release every non-null `shovelerdb_result` returned by
  `shovelerdb_execute`.
- Treat all ABI strings, byte views, vector views, rows, results, and database
  handles as ShovelerDB-owned unless copied into language-owned memory.

## Required Fixture

1. Open or create a database:

   ```c
   shovelerdb_database *db = NULL;
   shovelerdb_status status = shovelerdb_open_or_create(path, &db);
   ```

   Expect `SHOVELERDB_STATUS_OK` and a non-null database handle.

2. Create a table with scalar and vector columns:

   ```sql
   CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));
   ```

   Release the returned result, even when the result kind is empty.

3. Insert rows inside an explicit SQL transaction:

   ```sql
   BEGIN;
   INSERT INTO memories VALUES (1, 'origin', [1, 0]);
   INSERT INTO memories VALUES (2, 'side', [0, 1]);
   COMMIT;
   ```

   Each insert must return a mutation count of `1`.

4. Query vector ranking through the same SQL execution path:

   ```sql
   SELECT id, body, l2_distance(embedding, [1, 0])
   FROM memories
   ORDER BY l2_distance(embedding, [1, 0]) ASC
   LIMIT 2;
   ```

   Expect a rows result with row count `2`. The first row must contain:

   | Column | Accessor | Expected value |
   | --- | --- | --- |
   | `id` | `shovelerdb_row_value_int64` | `1` |
   | `body` | `shovelerdb_row_value_text` | `origin` |
   | distance | `shovelerdb_row_value_float64` | `0.0` |

   Iterating past the second row must return `SHOVELERDB_STATUS_OK` and write
   `NULL` to the output row pointer.

5. Query and read a vector value:

   ```sql
   SELECT embedding FROM memories WHERE id = 1;
   ```

   Read the first column with `shovelerdb_row_value_vector_f32`. Expect a
   borrowed float32 vector view with length `2` and values `[1.0, 0.0]`.

6. Trigger a typed diagnostic:

   ```sql
   SELECT l2_distance(embedding, [1, 0, 0]) FROM memories;
   ```

   Expect `SHOVELERDB_STATUS_VECTOR_ERROR`, a null result pointer, and
   `shovelerdb_database_last_diagnostic` returning
   `SHOVELERDB_DIAGNOSTIC_VECTOR`. Connectors should assert status and
   diagnostic code; user-facing message text is fallback reporting, not the
   primary compatibility contract.

7. Verify invalid-handle behavior:

   ```c
   status = shovelerdb_checkpoint(NULL);
   ```

   Expect `SHOVELERDB_STATUS_INVALID_HANDLE`.

8. Checkpoint, close, reopen, and verify persistence:

   ```c
   shovelerdb_checkpoint(db);
   shovelerdb_close(db);
   shovelerdb_open_or_create(path, &db);
   ```

   Then run:

   ```sql
   SELECT id FROM memories ORDER BY id ASC;
   ```

   Expect row count `2`; the first row's `id` must be `1`.

9. Release and close through simple cleanup paths:

   ```c
   shovelerdb_result_release(result);
   shovelerdb_result_release(NULL);
   shovelerdb_close(db);
   shovelerdb_close(NULL);
   ```

   Null result and database cleanup calls must be no-ops.

## Ownership Rules

Rows are borrowed from the result that produced them. String, byte, and vector
views are borrowed from the same result. A connector that exposes row values
after result release must copy them into language-owned memory first.

Host runtimes must not free ABI memory with their own allocators. The only ABI
cleanup functions in this fixture are `shovelerdb_result_release` and
`shovelerdb_close`.

## Evidence

The canonical in-repo fixture is `tests/integration/abi_acceptance.zig`, wired
into `zig build test` by `build.zig`. `docs/embedding-abi.md` explains the ABI
contract in prose, and `include/shovelerdb.h` is the authoritative C surface for
connectors.
