# Mission Specification: SQL Literal Escaping Hardening

**Mission Branch**: `kitty/mission-sql-literal-escaping-hardening-01KY0P89`
**Created**: 2026-07-20
**Status**: Ready for planning
**Input**: Correct single-quoted SQL literal boundaries and decoded values so
hostile client text cannot become trailing SQL, while preserving the accepted
ShovelerDB dialect outside this focused fix.

## Intent Summary

The primary actor is an embedding application that submits SQL containing
ordinary user text. The trigger is a single-quoted SQL string literal containing
an apostrophe, a backslash, a newline, Unicode, or SQL-looking punctuation. The
successful outcome is that the complete literal is parsed as one value, decoded
once, stored exactly, and returned unchanged through both native execution and
the public embedding boundary.

The invariant is strict: doubled single quotes are the only way to encode a
single quote inside a single-quoted literal. A backslash is ordinary data and
never changes where a literal ends. The main exception is an unterminated
literal, which must be rejected without executing any suffix. Backtick-quoted
identifier behavior is outside this mission unless an existing rule must be
preserved while separating identifier and string scanning.

## User Scenarios & Testing

### User Story 1 - Store Text Without Changing SQL Boundaries (Priority: P1)

As an embedding application, I can store text containing apostrophes,
backslashes, Unicode, newlines, comment markers, and semicolons without any of
those bytes becoming SQL syntax.

**Why this priority**: Incorrect boundaries can corrupt stored text and expose
an unintended statement suffix.

**Independent Test**: Submit literals that cover `O''Reilly`, trailing and
interior backslashes, a backslash immediately before a quote, SQL comment
markers, semicolons, Unicode, and newlines; retrieve the values and compare
their decoded bytes exactly.

**Acceptance Scenarios**:

1. **Given** the literal `'O''Reilly'`, **When** it is parsed and executed,
   **Then** its value is exactly `O'Reilly`.
2. **Given** a literal containing interior or trailing backslashes, **When** it
   is parsed and executed, **Then** every backslash is preserved as ordinary
   data.
3. **Given** the hostile text represented by `'\''' OR 1=1 --'`, **When** the
   input is tokenized, **Then** the backslash does not escape the following
   quote and no comment or predicate suffix is absorbed into the literal.
4. **Given** literal contents containing `--`, `/* */`, `#`, or `;`, **When**
   the literal remains open, **Then** those bytes remain data rather than trivia
   or statement delimiters.

---

### User Story 2 - Reject Ambiguous or Incomplete Input (Priority: P1)

As an embedding application, I receive a parse failure when a single-quoted
literal is not terminated, and no apparent suffix is executed.

**Why this priority**: Silent acceptance makes caller mistakes and boundary
confusion indistinguishable from valid data.

**Independent Test**: Submit unterminated literals at end of input and before
SQL-looking comment, predicate, and statement suffixes; observe rejection and
unchanged database state.

**Acceptance Scenarios**:

1. **Given** an opening single quote with no closing quote, **When** parsing
   completes, **Then** the statement is rejected.
2. **Given** an unterminated literal followed by comment markers or a
   semicolon-delimited mutation, **When** execution is attempted, **Then** the
   complete input is rejected and the mutation is not applied.

---

### User Story 3 - Trust the Public Embedding Boundary (Priority: P1)

As a connector author, I observe the same literal semantics through the public
C ABI as through native ShovelerDB execution, including after a durable
checkpoint and reopen.

**Why this priority**: The defect was discovered by an external embedding
consumer, so parser-only evidence is insufficient.

**Independent Test**: Through the public ABI, insert the hostile-case values,
read them back, checkpoint, close, reopen, and verify the same decoded bytes and
row cardinality.

**Acceptance Scenarios**:

1. **Given** all required hostile values inserted through the public ABI,
   **When** they are queried, **Then** each returned text value matches the
   expected decoded bytes and no unintended row is affected.
2. **Given** those committed values have been checkpointed and the database
   reopened, **When** they are queried again, **Then** the decoded values and
   row cardinality remain unchanged.

### Edge Cases

- Empty literal `''`.
- One decoded apostrophe represented as `''''`.
- Consecutive doubled quotes within a longer value.
- A backslash at the beginning, in the middle, and immediately before the
  closing delimiter.
- A backslash immediately before an apostrophe followed by `OR 1=1 --`.
- Embedded `--`, `#`, `/* */`, and semicolons while the literal is open.
- Literal content spanning a newline.
- Multi-byte UTF-8 before and after doubled quotes and backslashes.
- Unterminated input immediately after an opening quote, a data byte, a
  backslash, or the first quote of a would-be doubled pair.
- Existing double-quoted string behavior and backtick identifier behavior.

## Requirements

### Functional Requirements

| ID | Title | Requirement | Priority | Status |
| --- | --- | --- | --- | --- |
| FR-001 | Single-quote delimiter rule | Single-quoted SQL string literals MUST use two consecutive single quotes as the only representation of one embedded single quote. | High | Approved |
| FR-002 | Decoded literal value | A successfully parsed single-quoted literal MUST produce decoded value bytes with outer delimiters removed and every doubled single quote reduced to one single quote. | High | Approved |
| FR-003 | Ordinary backslashes | Every backslash inside a single-quoted literal MUST remain ordinary data and MUST NOT escape or consume the following byte. | High | Approved |
| FR-004 | Boundary-safe SQL-looking data | Comment markers, semicolons, whitespace, newlines, and operator text inside an open literal MUST remain literal data; the first non-doubled single quote MUST end the literal. | High | Approved |
| FR-005 | Unterminated rejection | Any single-quoted literal without a valid closing delimiter MUST be rejected before statement execution, with no suffix or partial mutation executed. | High | Approved |
| FR-006 | Native regression coverage | Automated native tests MUST cover token boundaries and decoded parser values for the complete hostile-case matrix. | High | Approved |
| FR-007 | Public ABI regression coverage | Automated public C ABI tests MUST insert and retrieve the hostile-case values and prove that SQL-looking suffixes do not alter row selection or mutation scope. | High | Approved |
| FR-008 | Durable round trip | The public ABI regression MUST checkpoint, close, reopen, and verify the decoded hostile-case values wherever persistence adds distinct evidence. | Medium | Approved |
| FR-009 | Identifier compatibility | Backtick-quoted identifier behavior MUST remain unchanged unless an existing documented rule requires a directly related correction. | High | Approved |

### Non-Functional Requirements

| ID | Title | Requirement | Category | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| NFR-001 | Complete hostile matrix | The automated regression suite MUST pass 100% of the required cases: `O'Reilly`, trailing and interior backslashes, backslash-before-apostrophe plus `OR 1=1 --`, comment markers, semicolons, Unicode, newline, empty text, and unterminated forms. | Security | High | Approved |
| NFR-002 | Byte fidelity | For every valid case, returned text MUST equal the expected decoded UTF-8 byte sequence exactly before and after any checkpoint/reopen step. | Correctness | High | Approved |
| NFR-003 | No unintended effects | Across all hostile suffix cases, acceptance tests MUST observe zero unintended statements, rows, or mutations. | Security | High | Approved |
| NFR-004 | Baseline compatibility | All pre-existing automated tests MUST continue to pass on supported macOS and Linux development targets. | Compatibility | High | Approved |
| NFR-005 | Focused change | Production changes MUST remain limited to the tokenizer/parser literal boundary; any wider source change requires a documented necessity and focused review. | Maintainability | Medium | Approved |

### Constraints

| ID | Title | Constraint | Category | Priority | Status |
| --- | --- | --- | --- | --- | --- |
| C-001 | Zig implementation | Production code and native regression tests remain in the repository's declared Zig toolchain and existing build system. | Technology | High | Approved |
| C-002 | Red-first evidence | The implementation must first add a focused regression that fails against baseline commit `fc7539a3874293540a4de6d228b3ea670a8ca2e8`, then make the smallest production correction that passes it. | Process | High | Approved |
| C-003 | Public surface stability | The public C ABI signatures, ownership rules, and version numbers MUST NOT change for this internal parsing correction. | Compatibility | High | Approved |
| C-004 | No backslash escape mode | This mission MUST NOT add a configuration mode or alternate dialect in which backslash escapes single quotes. | Scope | High | Approved |
| C-005 | No unrelated quote redesign | Double-quoted string and backtick-quoted identifier semantics are not redesigned in this mission. | Scope | High | Approved |
| C-006 | Focused review | At least one independent focused reviewer must approve the completed mission before merge. | Governance | High | Approved |

## Domain Language

- **Single-quoted SQL string literal**: Text delimited by single quotes whose
  embedded single quotes are represented only by doubled single quotes.
- **Decoded value**: The literal's data after outer delimiters are removed and
  doubled single quotes are reduced to one byte; all other bytes are preserved.
- **Literal boundary**: The opening and first non-doubled closing single quote.
- **SQL-looking data**: Literal bytes such as comment markers, predicates, or
  semicolons that have no syntactic meaning while the literal is open.
- **Hostile-case matrix**: The fixed valid and invalid cases named in NFR-001.

## Assumptions and Dependencies

- The existing accepted SQL dialect remains authoritative outside the explicit
  single-quoted literal rules above.
- Input strings are byte slices containing UTF-8 text; decoding changes quote
  representation only and performs no Unicode normalization.
- The existing tokenizer, parser, executor, persistence, and C ABI paths are
  sufficient; no new dependency or public API is required.
- The existing ABI acceptance harness provides the proportionate durable
  checkpoint/reopen proof, so a new integration executable is unnecessary.
- The invoice-manager consumer will repin ShovelerDB only after this mission is
  independently reviewed, accepted, and merged.

## Success Criteria

### Measurable Outcomes

- **SC-001**: All valid hostile-case literals produce the exact expected bytes
  in 100% of native parser and public embedding acceptance runs.
- **SC-002**: All invalid or boundary-confusion cases produce zero unintended
  statements, selected rows, or mutations.
- **SC-003**: All unterminated cases are rejected before execution in 100% of
  regression runs.
- **SC-004**: Valid hostile values remain byte-identical after checkpoint,
  close, and reopen.
- **SC-005**: The complete pre-existing test suite passes with no public ABI or
  backtick-identifier compatibility regression.

## Out of Scope

- Parameter binding, prepared statements, query builders, or invoice-manager
  interpolation policy.
- General SQL dialect expansion or standards certification.
- Escape-string prefixes, backslash escape modes, alternate delimiters, or
  Unicode normalization.
- Redesign of comments, statement batching, double-quoted strings, or backtick
  identifiers.
- Storage format, transaction, checkpoint, or ABI version changes.
