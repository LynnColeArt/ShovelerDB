# Adapted Fixture: Autoincrement Evidence

- Source path: `references/mariadb/mysql-test/main/insert_update_autoinc-7150.test`
- Source intent: preserve evidence around stable insert/update identity behavior.
- ShovelerDB adaptation: MVP SQL uses explicit integer keys while the row store
  preserves internal monotonic row IDs for transaction visibility and reopen.
- Native smoke:

```sql
CREATE TABLE memories (id INTEGER, body TEXT);
BEGIN;
INSERT INTO memories VALUES (1, 'first');
UPDATE memories SET body = 'updated' WHERE id = 1;
COMMIT;
SELECT id, body FROM memories WHERE id = 1;
```

- Removed MariaDB behavior: `AUTO_INCREMENT`, table options, engine-specific
  allocation details, and multi-session server harness assertions. Full SQL
  autoincrement syntax is deferred until the MVP decides whether it belongs in
  ShovelerDB's row/table metaphor.
