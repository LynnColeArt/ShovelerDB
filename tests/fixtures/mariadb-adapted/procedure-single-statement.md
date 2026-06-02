# Adapted Fixture: Single Statement Procedure

- Source path: `references/mariadb/mysql-test/main/sp.test`
- Source intent: validate stored procedure creation, invocation, and removal.
- ShovelerDB adaptation: keep this fixture as the minimal procedure lifecycle
  smoke; richer parameters, variables, and control flow are covered by the
  procedure acceptance tests.
- Native smoke:

```sql
CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));
CREATE PROCEDURE remember() BEGIN INSERT INTO memories VALUES (1, 'from proc', [1, 0]); END;
BEGIN;
CALL remember();
COMMIT;
SELECT body FROM memories;
DROP PROCEDURE remember;
```

- Removed MariaDB behavior: delimiter commands, cursors, handlers, OUT
  parameters, dynamic SQL, and other server-oriented stored-program surfaces.
