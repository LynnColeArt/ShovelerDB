# Quickstart: Validate SQL Literal Escaping Hardening

Run from `/home/lynn/projects/shovelerdb` or the Spec Kitty lane worktree
assigned to WP01.

## Prerequisites

- Zig 0.16.0 available as `zig`
- A WP01 lane based on baseline
  `fc7539a3874293540a4de6d228b3ea670a8ca2e8`
- No unrecorded source changes outside the WP ownership map

## 1. Confirm the baseline

```bash
zig version
git rev-parse HEAD
git status --short
```

Before production edits, add the focused native regressions from
`contracts/sql-literal-semantics.md` and run:

```bash
zig test src/sql/tokenizer.zig
zig test src/sql/parser.zig
```

Record the expected failures for doubled-quote decoding, trailing backslash,
unterminated doubled-pair detection, and the raw backslash boundary. A test that
is already green at the accepted baseline is not red-first evidence.

## 2. Make the tokenizer correction

Implement explicit single-quote scanning semantics and explicit termination
evidence. Keep double-quote and backtick behavior unchanged. Re-run:

```bash
zig test src/sql/tokenizer.zig
```

Inspect the I05 token end offset/lexeme bytes, not only its token kind.

## 3. Make the parser correction

Reject unterminated single-quoted tokens and decode doubled apostrophes once in
parser-owned allocation. Re-run:

```bash
zig test src/sql/parser.zig
```

The tests must compare exact decoded bytes for V01-V10 and use
`std.testing.allocator` so leaked error-path allocations fail.

## 4. Extend the public ABI regression

Add the contract's public subset to
`/home/lynn/projects/shovelerdb/tests/integration/abi_acceptance.zig`:

- insert correctly encoded hostile values;
- read and compare exact text bytes;
- submit the intentionally incomplete I05/I06 boundary probes and verify zero
  unintended rows/mutations;
- checkpoint, close, reopen, and compare representative hostile values plus row
  cardinality.

The ABI integration test is already part of the repository build, so no
`build.zig` change is expected.

## 5. Run the complete gate

```bash
zig build test
git diff --check
git status --short
```

Review the final diff and confirm it is limited to:

```text
src/sql/tokenizer.zig
src/sql/parser.zig
tests/integration/abi_acceptance.zig
```

## Expected Result

- All contract cases pass at their required layers.
- All unterminated cases return a parse failure before execution.
- The I05/I06 probes produce zero unintended mutations.
- Representative hostile values remain byte-identical after reopen.
- The complete existing suite remains green.
- No public ABI, build, storage, double-quote, or backtick contract changes.
