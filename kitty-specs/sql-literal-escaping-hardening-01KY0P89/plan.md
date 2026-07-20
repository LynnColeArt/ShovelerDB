# Implementation Plan: SQL Literal Escaping Hardening

**Branch**: `kitty/mission-sql-literal-escaping-hardening-01KY0P89` | **Date**: 2026-07-20 | **Spec**: [spec.md](spec.md)
**Input**: Approved security/correctness specification in
`/home/lynn/projects/shovelerdb/kitty-specs/sql-literal-escaping-hardening-01KY0P89/spec.md`

## Summary

Correct the existing single-quoted SQL literal boundary in place. The tokenizer
will stop treating backslash as an escape for single-quoted string literals,
continue to consume doubled quote pairs as literal content, and expose whether the closing
delimiter was actually found. The parser will reject unterminated literals and
decode doubled single quotes into one apostrophe while preserving every other
byte. Focused tokenizer/parser regressions must fail against baseline commit
`fc7539a3874293540a4de6d228b3ea670a8ca2e8` before production code changes;
the existing C ABI acceptance test then proves hostile data, statement
boundaries, checkpoint, close, and reopen through the public product path.

## Technical Context

**Language/Version**: Zig 0.16.0
**Primary Dependencies**: Zig standard library and existing ShovelerDB SQL,
executor, persistence, and C ABI modules; no new dependency
**Storage**: Existing ShovelerDB snapshot/checkpoint persistence, unchanged
**Testing**: In-module Zig tokenizer/parser tests plus
`tests/integration/abi_acceptance.zig`, all run by `zig build test`
**Target Platform**: Supported macOS and Linux development environments
**Project Type**: Single Zig library/CLI with a public C ABI
**Performance Goals**: Preserve linear scanning/decoding in literal byte length;
complete repository test execution remains within existing project expectations
**Constraints**: No public ABI or storage-format change; no new SQL mode; no
double-quote or backtick redesign; exact UTF-8 byte preservation; red-first TDD
**Scale/Scope**: Two SQL implementation modules and one existing ABI acceptance
file; one cohesive work package with six focused subtasks

## Charter Check

*GATE: Passed before research and re-checked after design.*

| Charter rule | Plan evidence | Result |
| --- | --- | --- |
| Use the declared project language and tools | Zig 0.16.0, the standard library, the existing build, and Spec Kitty only | Pass |
| Use the project's declared test approach | Red-first in-module unit tests plus the existing public ABI integration path | Pass |
| Keep CLI operations typically under two seconds | No CLI code or new startup path; literal scanning remains linear | Pass |
| Support macOS and Linux developer environments | No platform-specific behavior or dependency is added | Pass |
| Require focused review before merge | Mission acceptance requires an independent reviewer | Pass |
| Keep planning and implementation artifacts consistent | Fixed semantic contract, requirement refs, hostile matrix, and one ownership map remain aligned | Pass |

There are no charter exceptions or deferred decisions.

## Baseline and Defect Boundary

At baseline `fc7539a3874293540a4de6d228b3ea670a8ca2e8`:

- `/home/lynn/projects/shovelerdb/src/sql/tokenizer.zig` method `readQuoted`
  skips the byte after every backslash and consumes doubled quote pairs.
- `/home/lynn/projects/shovelerdb/src/sql/parser.zig` method
  `cloneStringLiteral` removes only the first and last bytes, leaving doubled
  quotes undecoded and unable to distinguish a missing delimiter.
- `/home/lynn/projects/shovelerdb/tests/integration/abi_acceptance.zig` already
  exercises public SQL execution, typed text reads, checkpoint, close, and
  reopen, so it can carry the required black-box regression without a new test
  binary or build change.

The source of truth is the specification's single-quote invariant. Existing
double-quoted strings and backtick identifiers are compatibility surfaces, not
targets for generalized quote refactoring.

## Design Decisions

### D-01: Preserve lexical evidence until parsing

The tokenizer must expose enough information for the parser to distinguish a
valid closing delimiter from end-of-input after a doubled quote. A small token
property or equivalently explicit token kind is acceptable; inferring
termination from the final lexeme byte is not, because an unterminated sequence
can end on the second byte of a doubled pair.

The tokenizer remains responsible only for byte boundaries and quote-pair
recognition. It does not allocate or decode the value.

### D-02: Decode exactly once in the parser

The parser owns the allocated AST literal value. For a valid single-quoted
token it removes outer delimiters and performs a single linear pass that copies
ordinary bytes unchanged and reduces each `''` pair to one `'`. Backslashes,
newlines, comment markers, semicolons, and UTF-8 bytes receive no special
treatment. The decoder must use visible allocator ownership and return
out-of-memory through the existing parse error surface.

### D-03: Separate single-quote policy from other quoted forms

The existing shared quote scanner may be split or parameterized only as much as
needed to keep current double-quote and backtick behavior stable. Backslash is
ordinary data specifically for single-quoted string literals. This mission does
not silently redefine accepted identifier escaping or turn double-quoted
strings into a new dialect.

### D-04: Reject unterminated literals before AST execution

The parser must produce a diagnostic for an unterminated single-quoted token
before returning a statement or expression. The diagnostic may reuse the
existing `unexpected_end` or `unexpected_token` vocabulary if its offset/token
is stable and the black-box status remains a parse failure. No public diagnostic
enum or ABI version is added for this fix.

### D-05: Use one fixed hostile-case matrix at every layer

Native tests own exact tokenizer boundaries and decoded parser values. The ABI
test reuses the security-relevant subset to prove statement scope and durable
round-trip. The contract at `contracts/sql-literal-semantics.md` names the cases
and expected bytes so the two layers cannot drift.

## Project Structure

### Documentation and planning artifacts

```text
/home/lynn/projects/shovelerdb/kitty-specs/sql-literal-escaping-hardening-01KY0P89/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── sql-literal-semantics.md
├── research/
│   ├── evidence-log.csv
│   └── source-register.csv
├── wps.yaml
├── tasks.md
└── tasks/
    └── WP01-sql-literal-boundary-and-abi-regression.md
```

### Source and test surfaces

```text
/home/lynn/projects/shovelerdb/
├── src/sql/tokenizer.zig
├── src/sql/parser.zig
└── tests/integration/abi_acceptance.zig
```

**Structure Decision**: Keep all changes in existing modules. Do not modify
`build.zig`, add a decoder module, add a dependency, or add a second integration
test executable unless red-first evidence proves the existing surfaces cannot
express the contract.

## Test-Driven Execution Strategy

1. Add focused tokenizer cases that demonstrate baseline failure for doubled
   quotes, ordinary backslashes, hostile suffix boundaries, and unterminated
   input. Capture the failing command/output in the WP activity log.
2. Add parser cases for decoded bytes, including empty, apostrophe,
   backslashes, comments/semicolons, Unicode/newline, and rejection. Confirm
   they fail on the baseline implementation.
3. Make the smallest tokenizer boundary and termination-evidence change that
   passes tokenizer tests while preserving backtick coverage.
4. Make the smallest parser decoding/rejection change that passes parser tests
   with allocator cleanup verified by `std.testing.allocator`.
5. Extend the existing ABI acceptance test with hostile values and a boundary
   probe that detects unintended predicate/comment/statement effects. Reuse its
   checkpoint/close/reopen lifecycle to verify exact returned text.
6. Run focused tests after each change, then `zig build test` as the required
   repository regression gate.

Tests must not merely assert token lexemes that encode the old defect. They must
assert semantic boundaries, decoded bytes, parse failure, row cardinality, and
mutation scope.

## Implementation Concern Map

### IC-01 — Literal Boundary and Decoding

- **Purpose**: Establish correct single-quote termination, ordinary-backslash
  treatment, decoded AST bytes, and unterminated rejection with red-first
  native evidence.
- **Relevant requirements**: FR-001, FR-002, FR-003, FR-004, FR-005, FR-006,
  FR-009, NFR-001, NFR-002, NFR-004, NFR-005, C-001, C-002, C-004, C-005
- **Affected surfaces**:
  `/home/lynn/projects/shovelerdb/src/sql/tokenizer.zig`,
  `/home/lynn/projects/shovelerdb/src/sql/parser.zig`
- **Sequencing/depends-on**: none
- **Risks**: termination inferred from lexeme shape; allocator leak during
  decoding; accidental double-quote/backtick drift; tests written green against
  the defective baseline

### IC-02 — Public ABI and Durable Hostile-Text Proof

- **Purpose**: Prove the corrected parser is the behavior public embedding
  consumers receive and that hostile values remain exact after checkpoint and
  reopen without unintended SQL effects.
- **Relevant requirements**: FR-007, FR-008, NFR-001, NFR-002, NFR-003,
  NFR-004, C-003, C-006
- **Affected surfaces**:
  `/home/lynn/projects/shovelerdb/tests/integration/abi_acceptance.zig`
- **Sequencing/depends-on**: IC-01
- **Risks**: a test that checks text but not statement scope; SQL source strings
  whose Zig escaping obscures intended SQL bytes; redundant persistence setup

## Work-Package Strategy

Use one work package. IC-01 and IC-02 are sequential parts of one red-green
security correction and share the same semantic matrix. Splitting production
and ABI evidence would create an avoidable interval in which the fix could be
reviewed without its public regression, while two packages would not run safely
in parallel because both require the same red-first baseline and final full
suite.

The package should contain six subtasks matching the execution strategy and own
exactly the three source/test files above. Planning artifacts are not owned by
the implementation package.

## Risk Controls

| Risk | Control | Acceptance evidence |
| --- | --- | --- |
| Backslash still consumes the following quote | Token boundary test uses backslash-apostrophe followed by predicate/comment text | Token end offset and black-box row/mutation scope |
| Doubled quotes remain encoded in stored data | Parser and ABI compare exact `O'Reilly` bytes | Native AST value and ABI text view |
| Unterminated doubled pair looks closed | Explicit termination evidence, not final-byte inference | Unterminated variants all reject |
| Decoder corrupts Unicode or newlines | Byte-exact UTF-8/newline fixtures | Pre/post-reopen byte equality |
| Backtick or double-quote semantics drift | Existing suite plus focused compatibility cases | Full suite green; no unrelated contract change |
| C ABI behavior diverges from native parsing | Reuse exported execute/value accessors | ABI integration test green |
| Scope grows into query construction policy | Reject prepared statements and interpolation work as out of scope | Three-file ownership and review diff |

## Acceptance and Handoff

Implementation is ready for review only when:

- baseline red evidence is recorded for both malformed boundary and decoded
  value behavior;
- all native hostile cases and unterminated forms pass;
- public ABI tests prove exact values and zero unintended SQL effects;
- checkpoint/close/reopen preserves the selected hostile cases;
- `zig build test` passes;
- the diff changes no public ABI, storage format, build configuration, or
  unrelated dialect behavior; and
- an independent reviewer checks the raw SQL bytes represented by Zig test
  strings, not just their source spelling.

## Post-Design Charter Re-check

The design remains local, explicit, dependency-free, test-driven, portable,
and independently reviewable. It introduces no charter violation, exception,
or undocumented observable behavior.
