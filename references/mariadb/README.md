# MariaDB Reference Tests

This directory contains a curated subset of MariaDB reference tests copied from
MariaDB Server commit:

```text
a06be0288f63f520aec95982cc6f872d26c4f23c
```

These files are not an unfiltered compatibility promise. They are source
material for ShovelerDB's behavior-level test suite.

## Included Areas

- vector SQL tests
- stored procedure SQL tests
- view SQL tests
- transaction and DML tests
- selected InnoDB MVCC, locking, deadlock, snapshot, and autoincrement tests
- decimal, string, JSON, SQL helper, and InnoDB C/C++ unit-test references

## Policy

Copied files should stay unchanged. ShovelerDB-native tests should be written
under `tests/`, with references back to these files when useful.

Foreign keys, temporary tables, server auth, replication, storage engine
selection, and plugins are outside ShovelerDB's intended surface unless a future
design decision says otherwise.

