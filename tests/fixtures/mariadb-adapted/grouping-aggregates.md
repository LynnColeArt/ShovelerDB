# Adapted Fixture: Grouping and Aggregates

- Source path: `references/mariadb/mysql-test/main/sp-group.test`
- Source intent: preserve behavior-level evidence around grouping, aggregate
  evaluation, grouped query cleanup, and view/query interactions.
- ShovelerDB adaptation: use native aggregate functions, aliases, `GROUP BY`,
  `HAVING`, and deterministic ordering over an embedded in-memory table.
- Native smoke:

```sql
CREATE TABLE memory_scores (id INTEGER, tag TEXT, score FLOAT);
BEGIN;
INSERT INTO memory_scores VALUES (1, 'project', 0.4);
INSERT INTO memory_scores VALUES (2, 'project', 0.8);
INSERT INTO memory_scores VALUES (3, 'personal', 0.2);
INSERT INTO memory_scores VALUES (4, 'idea', 1.0);
INSERT INTO memory_scores VALUES (5, 'idea', 3.0);
COMMIT;
SELECT tag, COUNT(*) AS total, AVG(score) AS average_score
FROM memory_scores
GROUP BY tag
HAVING total > 1
ORDER BY average_score DESC;
SELECT COUNT(*), SUM(score), AVG(score), MIN(score), MAX(score)
FROM memory_scores
WHERE tag = 'idea';
--error InvalidGrouping
SELECT id, COUNT(*) FROM memory_scores GROUP BY tag;
```

- Removed MariaDB behavior: `sql_mode`, `INFORMATION_SCHEMA`, storage engine
  clauses, triggers, server crash-regression scaffolding, and harness error
  code variants.
- Deferred ShovelerDB behavior: strict MariaDB `ONLY_FULL_GROUP_BY` mode
  toggles are not exposed; invalid grouped projections report the stable
  ShovelerDB `InvalidGrouping` diagnostic.
