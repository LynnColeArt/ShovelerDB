# Adapted Fixture: Rich View

- Source path: `references/mariadb/mysql-test/main/view_alias.test`
- Source intent: preserve reusable query definitions with aliases, joins, and
  ordered projections.
- ShovelerDB adaptation: combine native table aliases, qualified identifiers,
  joins, vector distance aliases, and outer queries over a view. Persisted
  executor snapshots store the supported `SELECT` body so the view can be
  reopened without MariaDB server metadata.
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
CREATE VIEW project_memory AS
SELECT m.id AS memory_id, m.body, l2_distance(m.embedding, [1, 0]) AS distance
FROM memories AS m
JOIN memory_tags AS t ON t.memory_id = m.id
WHERE t.name = 'project'
ORDER BY distance ASC
LIMIT 10;
SELECT v.memory_id, v.body
FROM project_memory AS v
WHERE v.distance < 0.3
ORDER BY v.memory_id ASC;
DROP VIEW project_memory;
```

- Removed MariaDB behavior: `SHOW CREATE VIEW`, `INFORMATION_SCHEMA.VIEWS`,
  definer/security clauses, privilege metadata, temporary-table interactions,
  and server-side serialized view metadata assertions.
- Deferred ShovelerDB behavior: structured result assertions remain in native
  Zig acceptance tests.
