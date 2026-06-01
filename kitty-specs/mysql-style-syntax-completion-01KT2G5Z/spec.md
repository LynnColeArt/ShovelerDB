# Feature Specification: MySQL-Style Syntax Completion

**Mission**: `mysql-style-syntax-completion-01KT2G5Z`
**Target branch**: `main`
**Date**: 2026-06-01

## Summary

Complete the next compatibility slice for ShovelerDB's MariaDB/MySQL-like SQL
surface. The previous MVP kernel proved the embedded in-memory engine,
transactions, views, constrained procedures, persistence, vector values, CLI
smokes, and benchmarks. This mission closes the outstanding gaps now visible in
the docs and code: promised SQL constructs must either execute with tests or be
classified as intentionally rejected/deferred with stable diagnostics.

The first priority is executable syntax that already parses but does not yet
run, especially vector distance function calls inside `SELECT` projection,
`WHERE`, and `ORDER BY`. The broader target is a practical MySQL-style embedded
analytics/memory dialect: tables, rows, transactions, views, procedures,
derived query shapes, joins, grouping, and vector ranking, without foreign keys,
user-visible temporary tables, plugins, storage-engine selection, replication,
server administration, users, grants, or cloud/daemon baggage.

## Goals

- Make the current roadmap truthful after the completed MVP kernel mission.
- Move the MariaDB reference corpus from classification-only toward runnable
  adapted SQL coverage.
- Implement SQL function calls at execution time, including vector distances.
- Expand `SELECT` syntax from single-table scans to aliases, derived tables,
  CTEs, joins, grouping, and aggregate functions.
- Make stored procedures useful enough for local agent workflows: parameters,
  local variables, multi-statement bodies, `IF`, and bounded `WHILE`.
- Accept common MySQL DDL surface where it is semantically useful, such as
  `IF EXISTS`, `IF NOT EXISTS`, nullability/default metadata, primary keys,
  auto-increment metadata, and ordinary index definitions.
- Keep deliberate non-goals loudly rejected rather than silently ignored.
- Validate everything with Zig tests, integration tests, adapted MariaDB
  fixtures, and CLI smokes.

## Non-Goals

- Foreign-key enforcement or silent foreign-key acceptance.
- User-visible temporary tables.
- Replication, binlog SQL, server lifecycle SQL, auth, users, grants, roles, or
  privilege management.
- Storage-engine selection, plugin management, UDF loading, or server modules.
- Full historical MySQL mode compatibility.
- ANN/vector index implementation. Exact scan and planner-recognized vector
  ranking are enough for this mission.
- Full MariaDB stored-program parity: cursors, handlers, diagnostics areas,
  compound labels, and dynamic SQL can remain classified unless explicitly
  needed by accepted tests.

## User Scenarios

### Scenario 1: Vector Ranking Uses SQL

An agent memory application stores embeddings in a `VECTOR(N)` column and runs:

```sql
SELECT id, body, l2_distance(embedding, [1, 0, 0]) AS distance
FROM memories
WHERE cosine_distance(embedding, [1, 0, 0]) < 0.4
ORDER BY distance ASC
LIMIT 5;
```

The query returns rows ordered by distance, names the projected distance column,
and fails with typed diagnostics for dimension mismatches or invalid operands.

### Scenario 2: Query Shape Matches Everyday MySQL

A developer can write aliases, qualified columns, joins, derived tables, and
CTEs without dropping into application-side loops:

```sql
WITH ranked AS (
  SELECT m.id, m.body, l2_distance(m.embedding, [1, 0]) AS distance
  FROM memories AS m
  JOIN memory_tags AS t ON t.memory_id = m.id
  WHERE t.name = 'project'
)
SELECT id, body
FROM ranked
WHERE distance < 1.0
ORDER BY distance
LIMIT 10;
```

### Scenario 3: Aggregation Is Database Work

An application can summarize rows without fetching everything:

```sql
SELECT tag, COUNT(*) AS total, AVG(score) AS average_score
FROM memory_scores
GROUP BY tag
HAVING total > 1
ORDER BY average_score DESC;
```

### Scenario 4: Procedures Encapsulate Local Logic

A stored procedure can accept arguments, declare local variables, branch, loop
with a safety limit, and execute SQL statements in one transaction context:

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

### Scenario 5: Unsupported Syntax Is Explicit

Foreign keys, temp tables, engine clauses, plugins, replication commands, and
auth/admin SQL fail before execution with stable diagnostics and test coverage.
If a MariaDB reference test exercises one of those surfaces, the adapted fixture
records why ShovelerDB rejects it.

## Functional Requirements

- **FR-001**: Update `docs/project-plan.md`, `docs/sql-dialect.md`, and related
  test docs so completed MVP work is marked complete and the remaining syntax
  milestone is explicit.
- **FR-002**: Add an MTR-lite runner path that can execute accepted adapted
  `.test` fragments against the embedded SQL engine and report unsupported
  directives with reasons.
- **FR-003**: Execute SQL function-call expressions in projection, predicate,
  assignment where safe, and ordering contexts.
- **FR-004**: Implement vector SQL functions `l2_distance`,
  `squared_l2_distance`, and `cosine_distance` over vector values and vector
  literals.
- **FR-005**: Implement a small scalar function set needed by adapted tests and
  procedure code, including numeric absolute value and basic string casing or
  length functions if referenced by accepted fixtures.
- **FR-006**: Support projection aliases with `AS` and MySQL-style implicit
  aliases where unambiguous.
- **FR-007**: Support table aliases and qualified identifiers
  (`alias.column`, `table.column`) in query expressions.
- **FR-008**: Represent `FROM` sources as AST nodes rather than a single table
  string, including base tables, views, derived tables, joins, and CTE refs.
- **FR-009**: Execute `INNER JOIN`/plain `JOIN`, `CROSS JOIN`, and `LEFT JOIN`
  with `ON` predicates for in-memory row sources.
- **FR-010**: Execute derived tables and non-recursive CTEs.
- **FR-011**: Execute aggregate functions `COUNT`, `SUM`, `AVG`, `MIN`, and
  `MAX` with `GROUP BY` and `HAVING`.
- **FR-012**: Expand view execution so views can wrap the richer supported
  `SELECT` forms, not only simple `SELECT *` delegation.
- **FR-013**: Accept practical MySQL DDL modifiers: `CREATE/DROP ... IF
  [NOT] EXISTS`, column nullability, defaults, primary keys, auto-increment
  metadata, and ordinary indexes.
- **FR-014**: Implement stored procedure parameters, local variables,
  `DECLARE`, `SET`, multi-statement bodies, `IF`, and bounded `WHILE`.
- **FR-015**: Keep unsupported stored-program features classified and rejected
  with explicit diagnostics rather than partial execution.
- **FR-016**: Add integration tests covering SQL examples from this spec.
- **FR-017**: Add adapted MariaDB fixture descriptors for newly supported
  syntax and update the reference corpus snapshot.
- **FR-018**: Preserve all deliberate non-goal policy rejections.
- **FR-019**: Keep benchmark coverage current for vector ranking and joined or
  grouped scans once those paths exist.
- **FR-020**: Keep `docs/spec-kitty-system-notes.md` updated with repeated or
  new Spec Kitty tool anomalies observed during the mission.

## Acceptance Criteria

- `zig build test` passes.
- SQL unit tests cover parser/AST ownership for the new syntax.
- Executor tests prove vector functions in projection, `WHERE`, and `ORDER BY`.
- Integration tests prove aliases, joins, derived tables, CTEs, grouping,
  aggregate functions, richer views, and useful stored procedures.
- MTR-lite can execute at least one accepted adapted fixture and can classify or
  reject unsupported harness directives deterministically.
- CLI smoke commands still work for parse, classify, execute, and benchmark.
- Docs identify the supported subset and the explicit rejected/deferred subset.
- Spec Kitty system notes include new observations from this mission.

## Risks

- SQL grammar can sprawl quickly. The mission should prefer high-value MySQL
  syntax used by accepted tests and local agent memory workflows.
- Joins, CTEs, and grouping all pressure the current single-table executor.
  Work packages should widen the row-source abstraction once, then reuse it.
- Procedure control flow can become a second interpreter. Keep it small,
  bounded, and transactional.
- Compatibility shortcuts such as silently ignoring unsupported clauses are not
  allowed; they would make the dialect harder to trust.
