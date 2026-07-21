# ShovelerDB Tests

Native ShovelerDB tests will live here.

The project will also maintain curated MariaDB reference tests under
`references/mariadb/`. Those files are references and import candidates, not an
unfiltered compatibility promise.

Tests and adapted fixture descriptors are development material outside the
ShovelerDB engine distribution. In particular,
`tests/fixtures/mariadb-adapted/**` is excluded from the Invoice Manager
vendored engine export. See the root `NOTICE` for the exact export boundary.
