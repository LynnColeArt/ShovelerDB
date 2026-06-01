# Adapted Fixture: Vector Distance Functions

- Source path: `references/mariadb/mysql-test/main/vector_funcs.test`
- Source intent: verify SQL-callable vector distance functions.
- ShovelerDB adaptation: use native `VECTOR(2)` columns, bracket vector
  literals, and exact in-memory ordering through built-in distance functions.
- Native smoke:

```sql
CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));
BEGIN;
INSERT INTO memories VALUES (1, 'alpha', [1, 0]);
INSERT INTO memories VALUES (2, 'beta', [0, 1]);
INSERT INTO memories VALUES (3, 'near', [2, 0]);
SELECT id, l2_distance(embedding, [1, 0]) FROM memories ORDER BY l2_distance(embedding, [1, 0]) ASC LIMIT 2;
SELECT id FROM memories WHERE squared_l2_distance(embedding, [1, 0]) < 1.1 ORDER BY id ASC;
SELECT cosine_distance(embedding, [1, 0]) FROM memories WHERE id = 2;
COMMIT;
```

- Removed MariaDB behavior: engine selection, server variables, binary vector
  formatting details, and harness-level result formatting.
