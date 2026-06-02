# Adapted Fixture: Query Syntax

- Source path: `references/mariadb/mysql-test/main/view_alias.test`
- Source intent: preserve evidence around aliases, nested query sources, and
  reusable query definitions.
- ShovelerDB adaptation: use native CTEs, derived tables, table aliases,
  qualified identifiers, joins, vector filtering, and view expansion. Omit
  information-schema view serialization checks and server harness variables.
- Native smoke:

```sql
CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));
CREATE TABLE memory_tags (id INTEGER, memory_id INTEGER, name TEXT);
BEGIN;
INSERT INTO memories VALUES (1, 'project plan', [1, 0]);
INSERT INTO memories VALUES (2, 'project note', [0.8, 0.2]);
INSERT INTO memories VALUES (3, 'personal note', [0, 1]);
INSERT INTO memory_tags VALUES (1, 1, 'project');
INSERT INTO memory_tags VALUES (2, 2, 'project');
INSERT INTO memory_tags VALUES (3, 3, 'personal');
COMMIT;
WITH ranked AS (
  SELECT m.id, m.body, l2_distance(m.embedding, [1, 0]) AS distance
  FROM memories AS m
  JOIN memory_tags AS t ON t.memory_id = m.id
  WHERE t.name = 'project'
)
SELECT id, body
FROM ranked
WHERE distance < 0.3
ORDER BY distance ASC
LIMIT 10;
SELECT d.id, t.name
FROM (SELECT id FROM memories WHERE id < 4) AS d
LEFT JOIN memory_tags AS t ON t.memory_id = d.id AND t.name = 'missing'
ORDER BY d.id ASC;
SELECT m.id, t.name
FROM memories AS m
CROSS JOIN memory_tags AS t
ORDER BY m.id ASC, t.id ASC
LIMIT 4;
CREATE VIEW project_memory_tags AS
SELECT m.id AS memory_id, t.name AS tag
FROM memories AS m
JOIN memory_tags AS t ON t.memory_id = m.id
WHERE t.name = 'project'
ORDER BY m.id DESC;
SELECT memory_id, tag FROM project_memory_tags ORDER BY memory_id ASC;
DROP VIEW project_memory_tags;
```

- Removed MariaDB behavior: `SHOW CREATE VIEW`, `INFORMATION_SCHEMA.VIEWS`,
  `eval`, `let`, included harness files, generated identifier edge cases,
  privilege metadata, and view definer/security clauses.
- Deferred ShovelerDB behavior: expected-row comparison is still handled by
  native Zig acceptance tests until fixture descriptors grow structured result
  assertions.
