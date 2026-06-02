# Adapted Fixture: Procedure Control Flow

- Source paths:
  - `references/mariadb/mysql-test/main/sp-vars.test`
  - `references/mariadb/mysql-test/main/sp-fib.test`
  - `references/mariadb/mysql-test/main/sp-dynamic.test`
  - `references/mariadb/mysql-test/main/sp-cursor.test`
- Source intent: preserve evidence around stored procedure parameters,
  variables, branching, loops, and explicit rejection of stored-program
  features outside ShovelerDB's embedded scope.
- ShovelerDB adaptation: use one bounded loop with local variables and caller
  transaction state. Preserve dynamic SQL and cursor cases as expected
  unsupported diagnostics.
- Native smoke:

```sql
CREATE TABLE memories (id INTEGER, body TEXT);
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
BEGIN;
CALL remember(1, 'from proc');
COMMIT;
SELECT id, body FROM memories;
--error UnsupportedProcedure
CREATE PROCEDURE bad_cursor() BEGIN DECLARE cur CURSOR FOR SELECT * FROM memories; END;
--error UnsupportedProcedure
CREATE PROCEDURE bad_dynamic() BEGIN PREPARE stmt FROM 'SELECT 1'; END;
```

- Removed MariaDB behavior: delimiter directives, recursion, cursor fetch/open
  behavior, handlers, OUT/INOUT parameters, dynamic SQL execution, server
  variables, and function-returning stored routines.
- Deferred ShovelerDB behavior: recursive routines and cursor semantics are
  not planned for the embedded MVP.
