# Research: SQL Literal Escaping Hardening

## Research Scope

This research answers only the questions needed to plan the focused correction:

1. Where does the accepted baseline lose literal-boundary information?
2. Which layer should decode doubled single quotes?
3. How can unterminated literals be detected without guessing from the final
   byte?
4. Which existing test surface proves public C ABI and durable behavior?
5. How can single-quote semantics change without redefining double quotes or
   backtick identifiers?

The user-supplied semantic contract is authoritative. Local source and
documentation establish the current behavior, suitable change boundary, and
available validation seams.

## Decision R-01: Single quotes have one escape representation

**Decision**: Within a single-quoted SQL literal, `''` represents one decoded
apostrophe. A single non-doubled `'` closes the literal. Backslash is an
ordinary byte and does not escape or consume any following byte.

**Rationale**: This is the approved mission invariant. It is deterministic,
does not require a mutable SQL mode, and makes source bytes sufficient to
derive boundaries. It also aligns with the project's rule to reject historical
SQL modes that do not directly serve the embedded workload.

**Alternatives considered**:

- Preserve the current backslash escape: rejected because it contradicts the
  approved invariant and makes a backslash change lexical boundaries.
- Support both backslash and doubled-quote escaping: rejected because the same
  input becomes dialect-mode dependent and the mission explicitly forbids a
  new escape mode.
- Add prepared statements in this mission: rejected as broader caller-facing
  API work. Parameter binding remains valuable future work but does not correct
  the parser's current semantic defect.

**Evidence**: SRC-001, SRC-004; findings E-001 and E-004.

## Decision R-02: Termination must be explicit tokenizer evidence

**Decision**: The token boundary must carry explicit evidence that a matching
closing delimiter was consumed, either as a small token property or an
equivalently unambiguous token state. The parser will reject a single-quoted
token lacking that evidence.

**Rationale**: The tokenizer alone knows whether it consumed a non-doubled
closing quote or reached end-of-input. The final lexeme byte is insufficient:
an input consisting of an opening quote followed by a doubled pair reaches EOF
with a quote byte but has no closing delimiter.

**Alternatives considered**:

- Infer termination with `lexeme[lexeme.len - 1] == quote`: rejected because it
  accepts the unterminated doubled-pair edge case.
- Change `Tokenizer.next` to an error union: rejected as a disproportionate
  signature change affecting parser, procedure-body, and policy consumers.
- Decode and allocate in the tokenizer: rejected because it mixes lexical
  boundaries with AST ownership and creates unnecessary allocation for policy
  consumers.

**Evidence**: SRC-002; findings E-002 and E-003.

## Decision R-03: The parser owns decoded bytes

**Decision**: For a valid single-quoted token, the parser allocates one decoded
value, strips the outer delimiter, reduces each doubled single quote to one
apostrophe, and copies all other bytes unchanged in one linear pass.

**Rationale**: The parser already owns allocation for AST string values through
`cloneStringLiteral`. Keeping allocation there preserves visible ownership and
the existing out-of-memory path. A one-pass decoder is simple, bounds its output
to no more than the interior input length, and preserves UTF-8 without
normalization.

**Alternatives considered**:

- Keep only delimiter stripping: rejected because `O''Reilly` currently stores
  the encoded bytes instead of `O'Reilly`.
- Decode in the executor or storage layer: rejected because every downstream
  consumer would receive a defective AST and decoding could occur more than
  once.
- Generalize all quote forms through one new decoder: rejected because this
  mission does not redefine double-quoted strings or backtick identifiers.

**Evidence**: SRC-003; finding E-003.

## Decision R-04: Make the single-quote path explicit

**Decision**: Preserve the accepted behavior for double-quoted strings and
backtick identifiers by making the new ordinary-backslash/termination rule
specific to single quotes. Refactor the shared scanner only as far as required
to express that policy clearly.

**Rationale**: Baseline `readQuoted` handles `'`, `"`, and backtick with one
branch. Removing its backslash branch globally would cause an unrequested
dialect change. A quote-policy argument or focused single-quote scanner keeps
the new invariant local and reviewable.

**Alternatives considered**:

- Remove backslash skipping globally: rejected because it changes two
  compatibility surfaces without requirement or evidence.
- Redesign all quoted forms now: rejected by mission scope and locality of
  change.

**Evidence**: SRC-002, SRC-004; findings E-002 and E-004.

## Decision R-05: Reuse the existing ABI acceptance lifecycle

**Decision**: Add hostile text, boundary, and durable round-trip checks to
`tests/integration/abi_acceptance.zig`; do not add a test executable or modify
`build.zig`.

**Rationale**: The existing test already calls the exported C ABI to open a
database, execute SQL, read text, checkpoint, close, reopen, and query again.
Extending it proves the consumer-visible path with less setup and no additional
build surface. Native module tests remain responsible for exhaustive token and
decoder cases.

**Alternatives considered**:

- Create a new ABI test executable: rejected because it duplicates the same
  lifecycle and requires a build change without adding isolation.
- Test only parser internals: rejected because the defect blocks an external
  embedding consumer and persistence adds distinct end-to-end evidence.
- Put every malformed case through checkpoint/reopen: rejected as redundant;
  durable proof is proportionate for representative valid hostile values,
  while invalid cases prove zero mutation before checkpoint.

**Evidence**: SRC-005; finding E-005.

## Hostile-Case Conclusions

- Correctly encoded hostile data containing backslash plus apostrophe must use
  doubled apostrophe bytes and round-trip as data.
- A raw backslash followed by a single apostrophe must close the literal; an
  intentionally incomplete mutation with `OR 1=1 --` after that boundary must
  fail as a whole and leave row/mutation counts unchanged.
- Comment markers and semicolons are data only while the literal remains open.
- Unterminated inputs must fail even when their final byte is backslash or the
  second byte of a doubled quote pair.
- Unicode and newline bytes require exact copying, not character-level
  normalization or escape interpretation.

## Risks and Open Questions

There are no open planning questions.

Residual implementation risks are:

- Zig source escaping may obscure the actual SQL byte sequence. Tests must use
  named byte fixtures or hex commentary where ambiguity is possible.
- A convenience refactor could alter double/backtick semantics. Reviewer
  guidance must compare their baseline behavior explicitly.
- A boundary test could accidentally submit valid injected SQL rather than an
  intentionally incomplete statement. The fixed contract therefore specifies
  exact bytes and expected zero mutation.
- Decoder allocation must be released on every parse failure. Existing
  `std.testing.allocator` coverage is the required leak detector.

## Research Completion

All plan unknowns are resolved. The smallest accepted design is a tokenizer
boundary correction, parser-owned single-quote decoder/rejection path, and an
extension of the existing ABI acceptance lifecycle. No dependency, public API,
storage format, build file, or unrelated dialect work is justified.
