# Adapted Fixture: Vector Values

- Source path: `references/mariadb/mysql-test/main/vector.test`
- Source intent: verify vector literals, vector columns, and ordinary row
  persistence around vector data.
- ShovelerDB adaptation: use native `VECTOR(2)` columns and bracket vector
  literals supported by the MVP parser.
- Native smoke:

```sql
CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));
BEGIN;
INSERT INTO memories VALUES (1, 'alpha', [1, 0]);
COMMIT;
SELECT id, body FROM memories WHERE id = 1;
```

- Removed MariaDB behavior: engine selection, server variables, diagnostic
  formatting, and vector helper functions outside the current exact-scan MVP.
