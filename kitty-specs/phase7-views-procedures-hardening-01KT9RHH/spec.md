# Phase 7 Views and Procedures Hardening Spec

## Mission

Make ShovelerDB's reusable SQL logic trustworthy enough for agent memory
workloads. The previous missions established the core engine, richer query
sources, constrained views, constrained stored procedures, and explicit
unsupported diagnostics. This mission turns Phase 7 from "partially complete"
into a reviewable slice: views and procedures should either execute with
acceptance coverage or fail loudly with stable diagnostics.

The goal is not full MariaDB stored-program parity. ShovelerDB keeps the useful
row/table/SQL abstraction for embedded agent memory while rejecting server-era
metadata, admin behavior, and stored-program surfaces that would make the
kernel large, slow, or surprising.

## Current Baseline

- `CREATE VIEW`, `DROP VIEW`, and simple view execution exist.
- Query-source work already supports aliases, joins, CTEs, derived tables,
  grouping, aggregates, and vector distance expressions.
- `CREATE PROCEDURE`, `DROP PROCEDURE`, and `CALL` exist for a constrained
  procedure body language.
- Procedure bodies already cover useful `IN` parameters, `DECLARE`, `SET`,
  `IF`, bounded `WHILE`, and supported SQL statements.
- Adapted MariaDB fixtures exist for basic views, query syntax,
  single-statement procedures, and procedure control flow.

## Scope

- Harden view expansion over the supported `SELECT` surface.
- Tighten view lifecycle behavior, diagnostics, and catalog persistence.
- Harden procedure parsing, storage, `CALL` argument binding, transaction
  behavior, and cleanup.
- Expand adapted fixture coverage for view/procedure behavior that belongs in
  ShovelerDB.
- Keep unsupported view/procedure surfaces explicitly rejected and documented.
- Refresh roadmap, dialect, and acceptance docs so Phase 7 status is truthful.

## Non-Goals

- No foreign keys or user-visible temporary tables.
- No server daemon, wire protocol, auth, grants, roles, definer/security model,
  information schema compatibility layer, or server lifecycle SQL.
- No MariaDB view algorithm/definer/security clauses.
- No full stored-program parity: cursors, handlers, recursion, dynamic SQL,
  `OUT`/`INOUT` parameters, function-returning routines, packages, diagnostics
  areas, and labeled compound statements remain unsupported unless a later
  mission explicitly reopens one.
- No approximate nearest-neighbor index implementation.
- No language connector work; that remains Phase 9.

## User Scenarios

### Scenario 1: A View Encapsulates a Memory Query

An agent application can create a reusable ranked memory view over the supported
query surface and read from it deterministically:

```sql
CREATE VIEW project_memory AS
SELECT m.id AS memory_id, m.body, l2_distance(m.embedding, [1, 0]) AS distance
FROM memories AS m
JOIN memory_tags AS t ON t.memory_id = m.id
WHERE t.name = 'project'
ORDER BY distance ASC
LIMIT 10;

SELECT memory_id, body FROM project_memory WHERE distance < 0.5;
```

### Scenario 2: A Procedure Performs Local Agent Logic

A stored procedure can receive input, use local variables, branch, loop within a
bounded safety guard, and execute supported SQL in the caller's transaction
context:

```sql
CREATE PROCEDURE remember(IN p_id INT, IN p_body TEXT)
BEGIN
  DECLARE attempts INT DEFAULT 0;
  IF p_id > 0 THEN
    WHILE attempts < 1 DO
      INSERT INTO memories (id, body) VALUES (p_id, p_body);
      SET attempts = attempts + 1;
    END WHILE;
  END IF;
END;
```

### Scenario 3: Unsupported Stored-Program Surfaces Fail Loudly

Attempting cursor or dynamic SQL behavior returns a stable ShovelerDB diagnostic
before partial execution:

```sql
CREATE PROCEDURE bad_cursor()
BEGIN
  DECLARE cur CURSOR FOR SELECT * FROM memories;
END;
```

## Functional Requirements

- **FR-001**: Views over supported `SELECT` statements must execute correctly
  when the select includes aliases, qualified identifiers, joins, derived
  tables, CTE references, grouping/aggregates, ordering, limits, and vector
  distance expressions.
- **FR-002**: View column names and aliases must be stable in result metadata
  and usable by outer queries where the current row-source model supports them.
- **FR-003**: View lifecycle operations must preserve catalog consistency:
  duplicate creation, dropping missing views, and querying dropped views must
  return typed diagnostics instead of stale data or crashes.
- **FR-004**: Persisted snapshots must reopen views and their referenced query
  definitions without losing executable behavior.
- **FR-005**: Procedure `CALL` must validate procedure existence, argument
  count, argument type compatibility where known, and body execution failures
  with stable diagnostics.
- **FR-006**: Procedure execution must use the caller session and transaction
  context consistently: caller-visible writes, rollback behavior, and committed
  results must match equivalent direct SQL statements.
- **FR-007**: Procedure local variables, parameter references, assignment,
  `IF`, and bounded `WHILE` behavior must be covered by integration tests,
  including the loop safety cap.
- **FR-008**: Unsupported procedure constructs must remain rejected with stable
  diagnostics and no partial catalog mutation.
- **FR-009**: Adapted MariaDB fixture descriptors for views and procedures must
  execute through MTR-lite or be explicitly classified with a documented
  deferral/rejection reason.
- **FR-010**: `docs/sql-dialect.md`, `docs/project-plan.md`,
  `docs/reference-corpus-snapshot.md`, and a new Phase 7 acceptance document
  must describe supported, deferred, and rejected view/procedure behavior.
- **FR-011**: Existing SQL, transaction, persistence, vector, concurrency,
  adapted fixture, and benchmark tests must continue to pass.
- **FR-012**: No Phase 7 implementation may introduce server lifecycle,
  auth/admin, replication, plugin, foreign-key, or user-visible temporary table
  behavior.

## Acceptance

- `zig build test` passes.
- View integration tests cover rich view expansion, result metadata, lifecycle
  diagnostics, and persistence/reopen behavior.
- Procedure integration tests cover argument binding, local variables, branch
  and loop execution, caller transaction semantics, rollback behavior, and
  unsupported stored-program diagnostics.
- Adapted view/procedure fixtures run through MTR-lite or remain documented as
  deliberate deferrals.
- A Phase 7 acceptance doc maps every functional requirement to test, fixture,
  or documentation evidence.
- The roadmap marks Phase 7 complete only for the covered subset and preserves
  explicit future exclusions.

## Risks

- View expansion can accidentally duplicate query-executor semantics. Prefer
  reusing the existing row-source executor and adding focused integration tests.
- Procedure execution can drift into a second SQL runtime. Keep procedure body
  evaluation small, bounded, and tied to existing executor entry points.
- MariaDB reference tests mix useful reusable SQL behavior with server metadata.
  Adapt behavior, not server machinery.
