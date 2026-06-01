# Adapted Fixture: Single Statement Procedure

- Source path: `references/mariadb/mysql-test/main/sp.test`
- Source intent: validate stored procedure creation, invocation, and removal.
- ShovelerDB adaptation: restrict the procedure body to one supported SQL
  statement inside `BEGIN ... END`.
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

- Removed MariaDB behavior: delimiter commands, control flow, cursors,
  handlers, variables, OUT parameters, and multiple statements per procedure
  body.
