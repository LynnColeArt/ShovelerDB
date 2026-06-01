# Adapted Fixture: Basic View

- Source path: `references/mariadb/mysql-test/main/view.test`
- Source intent: prove a named view can expose a reusable `SELECT` query.
- ShovelerDB adaptation: keep a single-table projection view and omit MySQL
  definer/security metadata.
- Native smoke:

```sql
CREATE TABLE memories (id INTEGER, body TEXT);
CREATE VIEW recent AS SELECT id, body FROM memories ORDER BY id DESC LIMIT 1;
BEGIN;
INSERT INTO memories VALUES (1, 'first');
COMMIT;
SELECT * FROM recent;
DROP VIEW recent;
```

- Removed MariaDB behavior: view algorithm clauses, definer clauses, privilege
  metadata, information schema assertions, and temporary-table interactions.
