---
work_package_id: WP01
title: SQL Literal Boundary and ABI Regression
dependencies: []
requirement_refs:
- FR-001
- FR-002
- FR-003
- FR-004
- FR-005
- FR-006
- FR-007
- FR-008
- FR-009
- NFR-001
- NFR-002
- NFR-003
- NFR-004
- NFR-005
- C-001
- C-002
- C-003
- C-004
- C-005
- C-006
tracker_refs: []
planning_base_branch: main
merge_target_branch: main
branch_strategy: Planning artifacts for this mission were generated on main. During /spec-kitty.implement this WP may branch from a dependency-specific base, but completed changes must merge back into main unless the human explicitly redirects the landing branch.
base_branch: kitty/mission-sql-literal-escaping-hardening-01KY0P89
base_commit: ffce7aea1f8832b327a33346bfce7be732dead0e
created_at: '2026-07-20T21:46:56.584874+00:00'
subtasks:
- T001
- T002
- T003
- T004
- T005
- T006
agent: "codex:gpt-5:implementer-ivan:implementer"
shell_pid: "1807838"
history: []
agent_profile: reviewer-renata
authoritative_surface: src/sql
create_intent: []
execution_mode: code_change
model: gpt-5
owned_files:
- src/sql/tokenizer.zig
- src/sql/parser.zig
- tests/integration/abi_acceptance.zig
role: reviewer
tags: []
---

# Work Package Prompt: WP01 - SQL Literal Boundary and ABI Regression

## ⚡ Do This First: Load Agent Profile

Use the `/ad-hoc-profile-load` skill to load the agent profile specified in the
frontmatter, and behave according to its guidance before parsing the rest of
this prompt.

- **Profile**: `implementer-ivan`
- **Role**: `implementer`
- **Agent/tool**: `codex`

If no profile is available, run `spec-kitty agent profile list` and select the
best match for this work package's source/test bug-fix scope.

---

## Objective

Correct single-quoted SQL literal boundaries and decoded values with red-first
Zig evidence, then prove the behavior through the existing public C ABI and
checkpoint/reopen path. Keep the implementation local to the three owned files,
preserve existing double-quote and backtick behavior, and make no public ABI,
storage-format, dependency, or build change.

## Context

At accepted baseline commit
`fc7539a3874293540a4de6d228b3ea670a8ca2e8`, tokenizer `readQuoted` handles
single quotes, double quotes, and backticks together. It consumes the byte after
every backslash and consumes doubled quote pairs. Parser `cloneStringLiteral`
then strips only outer bytes. Consequently `O''Reilly` stays encoded, backslash
can change the token boundary, and the parser cannot reliably reject every
unterminated literal.

The binding semantics are in
`kitty-specs/sql-literal-escaping-hardening-01KY0P89/contracts/sql-literal-semantics.md`:

- `''` is the only representation of one apostrophe inside a single-quoted
  literal;
- backslash is ordinary data for single-quoted literals and never consumes the
  following byte;
- a non-doubled single quote closes the token;
- parser output is decoded exactly once;
- EOF before a real closing delimiter is a parse failure; and
- double-quoted string and backtick identifier behavior remain unchanged.

The plan deliberately combines native and ABI work in one package so the
security correction cannot be reviewed without its public consumer regression.
Use `spec-kitty agent action implement WP01 --agent <name>` to claim the package
before editing.

### Subtask T001: Add red-first tokenizer boundary and termination tests

**Purpose**: Prove the lexical defect at the accepted baseline before changing
production scanning, including the edge case that defeats last-byte inference.

**Steps**:

1. In `src/sql/tokenizer.zig`, add focused tests derived from contract cases
   V02-V06, I01-I05, and the compatibility cases.
2. Assert exact token kind, offset, and lexeme bytes. For I05, assert that the
   single-quoted token ends immediately after the raw backslash plus closing
   quote and does not absorb `OR 1=1 --`.
3. Cover unterminated input after:
   - an opening quote;
   - ordinary data;
   - a terminal backslash; and
   - an opening quote plus a doubled quote pair that reaches EOF.
4. The doubled-pair-at-EOF case must prove why
   `lexeme[lexeme.len - 1] == quote` is not valid termination detection.
5. Add focused compatibility assertions for the accepted double-quoted string
   and backtick-identifier behavior before production edits.
6. Run `zig test src/sql/tokenizer.zig` against the baseline-derived lane.
   Record the command, baseline commit, and expected failing assertions in the
   WP activity log or implementation handoff.

**Files**: `src/sql/tokenizer.zig` only; tests remain beside the tokenizer.

**Validation**:

- At least V05, I04, and I05 fail for the expected boundary/termination reason
  before production changes.
- The failure is semantic, not a compile failure caused by referencing an API
  that has not been added yet; structure the first assertions against observable
  baseline tokens where possible.
- Existing tokenizer tests still compile.

### Subtask T002: Add red-first parser decoded-value and rejection tests

**Purpose**: Demonstrate that the baseline AST preserves doubled quotes and
accepts incomplete literal shapes instead of producing the required decoded
value or parse failure.

**Steps**:

1. In `src/sql/parser.zig`, add expression or statement tests for every valid
   contract case V01-V10.
2. Compare the exact allocated AST string bytes for:
   - empty text;
   - `O'Reilly` from `'O''Reilly'`;
   - one and consecutive decoded apostrophes;
   - interior and trailing backslashes;
   - correctly doubled hostile text `\' OR 1=1 --`;
   - comment markers and semicolons;
   - newline; and
   - multi-byte UTF-8.
3. Add I01-I04 parser cases and require a diagnostic instead of an expression
   or statement.
4. Use contract hex bytes for ambiguous punctuation cases so the Zig source
   representation cannot hide an extra or missing apostrophe.
5. Preserve normal AST deinitialization in every branch. Let
   `std.testing.allocator` expose leaks from successful and diagnostic paths.
6. Run `zig test src/sql/parser.zig` before production edits and record the
   expected V02 decoded-value and I04 termination failures.

**Files**: `src/sql/parser.zig` only.

**Validation**:

- The red run shows `O''Reilly` differs from expected `O'Reilly`.
- Unterminated cases return diagnostics after the fix, never an owned literal.
- No test weakens byte comparison to substring or normalized text comparison.

### Subtask T003: Implement explicit single-quote scanning and termination evidence

**Purpose**: Make lexical boundaries correct without globally changing the
shared quote behavior for double quotes and backticks.

**Steps**:

1. Introduce the smallest explicit representation of quote termination on a
   token, or an equivalent unambiguous token state that the parser can consume.
2. Do not infer termination only from the last lexeme byte. I04 ends in quote
   but remains unterminated because the final two quote bytes are a doubled pair.
3. Make the single-quote path explicit in `Tokenizer.next`/`readQuoted`:
   - a doubled single quote is interior data;
   - a non-doubled single quote terminates;
   - a backslash advances exactly one ordinary byte; and
   - EOF preserves unterminated evidence.
4. Preserve the existing behavior for double-quoted strings and backtick
   identifiers. Do not globally delete the backslash branch from the generic
   scanner unless equivalent quote-specific policy preserves those forms.
5. Keep token lexemes borrowed from the original input and preserve offsets.
   Do not allocate or decode inside the tokenizer.
6. Avoid changing `Tokenizer.next` to an error union unless a concrete blocker
   proves explicit token state cannot work; such expansion requires handoff
   rationale before proceeding.
7. Run `zig fmt` on the changed source and rerun
   `zig test src/sql/tokenizer.zig`.

**Files**: `src/sql/tokenizer.zig`; expected change is small and local.

**Validation**:

- T001 cases are green.
- I05 token boundaries are byte-exact.
- I04 remains explicitly unterminated.
- Double-quote and backtick compatibility assertions retain baseline results.

### Subtask T004: Implement parser-only single-quote decoding and rejection

**Purpose**: Convert a valid token into one allocator-owned decoded AST value
and reject invalid termination before statement execution.

**Steps**:

1. Pass the token or equivalent quote/termination metadata to the string
   cloning path; a bare lexeme is insufficient for I04.
2. Before allocating a successful value, reject an unterminated single-quoted
   token through the existing parser diagnostic vocabulary.
3. For a valid single-quoted token, perform one linear decode pass:
   - skip the outer delimiters;
   - reduce every `''` pair to one `'`;
   - copy every other byte unchanged; and
   - return an owned slice no longer than the source interior.
4. Preserve backslashes, newlines, comment markers, semicolons, and all UTF-8
   bytes without escape interpretation or Unicode normalization.
5. Apply the new decoder only to single-quoted lexemes. Keep accepted
   double-quoted string transformation unchanged.
6. Keep allocation and failure ownership visible. Clean up temporary capacity
   on out-of-memory and parse-diagnostic paths through existing parser/AST
   deinitialization.
7. Do not add a public diagnostic enum or ABI status. Reuse the existing parse
   failure mapping with a stable offset/token.
8. Run `zig fmt` and `zig test src/sql/parser.zig`.

**Files**: `src/sql/parser.zig`; no executor or storage changes.

**Validation**:

- T002 valid cases return exact bytes.
- I01-I04 produce diagnostics before a statement/expression escapes.
- Test allocator reports no leak.
- Decode complexity is linear in source bytes with no speculative abstraction.

### Subtask T005: Extend the public ABI hostile/boundary/reopen regression

**Purpose**: Prove embedding consumers receive the corrected behavior and that
SQL-looking data cannot alter statement scope when encoded by the contract.

**Steps**:

1. Extend `tests/integration/abi_acceptance.zig`; reuse its current database,
   execute helper, text accessor, checkpoint, close, and reopen lifecycle.
2. Insert representative valid contract values through exported
   `shovelerdb_execute`, including:
   - `O'Reilly` encoded with doubled quote;
   - interior and trailing backslashes;
   - correctly doubled `\' OR 1=1 --` data;
   - comment markers and semicolons;
   - Unicode; and
   - newline.
3. Retrieve each value through `shovelerdb_row_value_text` and compare exact
   bytes and expected row cardinality.
4. Add an intentionally incomplete I05 or I06 mutation using exact source bytes
   where raw backslash plus one apostrophe closes the literal and the remaining
   predicate/comment or semicolon suffix leaves the statement invalid.
5. Require the existing public parse-error status, a null result, and zero
   unintended mutations/rows. Do not design an input that is itself a valid
   multi-row mutation and then expect the engine to ignore valid SQL.
6. Checkpoint, close, reopen, and compare the representative hostile values and
   row cardinality again.
7. Keep public ABI signatures, version, handle ownership, and diagnostics
   unchanged. Do not modify `build.zig`; this test already runs in
   `zig build test`.

**Files**: `tests/integration/abi_acceptance.zig` only.

**Validation**:

- Public text views equal contract bytes before and after reopen.
- I05/I06 produce zero unintended effects.
- All result handles are released and database lifecycle remains balanced.

### Subtask T006: Run full gates and prepare review evidence

**Purpose**: Confirm the focused fix has no dialect, ABI, persistence, platform,
or ownership regression and provide an auditable red-green handoff.

**Steps**:

1. Run focused commands after the final implementation:

   ```bash
   zig test src/sql/tokenizer.zig
   zig test src/sql/parser.zig
   ```

2. Run the required repository gate:

   ```bash
   zig build test
   git diff --check
   ```

3. Run `zig fmt --check` on the three owned Zig files if supported by the
   installed Zig 0.16.0 CLI; otherwise use the repository's established format
   check and record the exact command.
4. Inspect `git diff --name-only` and require exactly the three owned files.
5. Record in the WP Activity Log or handoff:
   - baseline commit;
   - red commands and expected failures;
   - green focused/full commands;
   - exact hostile cases exercised;
   - checkpoint/reopen result; and
   - confirmation of unchanged double/backtick/public ABI behavior.
6. Commit only the owned implementation files with an intentional message.
7. Move the WP to `for_review` using Spec Kitty and provide the commit/diff
   evidence to an independent reviewer.

**Files**: no additional files; evidence is recorded through the WP workflow.

**Validation**:

- Every command exits successfully in the final state.
- Worktree is clean after the implementation commit and status transition.
- No requirement or contract case is left without evidence.

## Definition of Done

- [ ] T001 records genuine tokenizer red evidence at the accepted baseline.
- [ ] T002 records genuine parser red evidence at the accepted baseline.
- [ ] Single-quoted backslash is ordinary data and explicit termination state
  handles I04 without final-byte inference.
- [ ] Doubled single quotes decode exactly once in the parser.
- [ ] Unterminated literals fail before execution with allocator safety.
- [ ] Double-quoted string and backtick identifier behavior is unchanged.
- [ ] Public ABI hostile values round-trip byte-exactly.
- [ ] Boundary probes produce zero unintended rows or mutations.
- [ ] Representative values survive checkpoint, close, and reopen.
- [ ] `zig build test` and diff/format checks pass.
- [ ] Only the three owned files changed.
- [ ] Red/green/full-suite evidence is in the review handoff.
- [ ] An independent reviewer can verify raw SQL bytes from the contract.

## Risks

- **False termination inference**: a lexeme ending in quote may still be
  unterminated after a doubled pair. Require explicit evidence.
- **Global scanner regression**: changing shared `readQuoted` behavior can
  redefine double quotes/backticks. Use quote-specific policy and compatibility
  tests.
- **Ambiguous Zig escaping**: source spelling can hide actual SQL bytes. Use the
  contract's hex sequences or explicit byte concatenation for critical cases.
- **Green-first tests**: a test may accidentally assert current defective
  behavior. Record semantic failures before production edits.
- **Valid injection test**: a supposedly hostile suffix may be valid SQL. Use
  an intentionally incomplete statement for zero-mutation rejection and a
  separately correctly doubled value for round-trip.
- **Allocator regression**: a new decode buffer can leak on diagnostics. Keep
  ownership local and rely on `std.testing.allocator`.
- **Scope creep**: parameter binding is useful but not part of this correction.
  Do not add APIs, dependencies, build entries, or storage changes.

## Reviewer Guidance

Review raw bytes before source spelling. In particular:

1. Verify I04 cannot pass through a last-byte quote heuristic.
2. Verify the single-quote correction does not globally remove backslash
   behavior for double-quoted strings or backtick identifiers.
3. Verify parser decoding is restricted to valid single-quoted tokens and
   reduces every doubled pair exactly once.
4. Verify the ABI valid hostile case uses doubled apostrophe bytes, while the
   I05/I06 rejection probe intentionally uses a raw closing apostrophe and an
   incomplete surrounding statement.
5. Verify row cardinality and mutation count, not only returned text.
6. Verify pre/post-reopen bytes and all handle cleanup.
7. Compare the final file list with frontmatter ownership and reject any
   undocumented surface expansion.
8. Require chronological red evidence from baseline plus final focused and
   full-suite green results before approval.

## Activity Log

- 2026-07-20T21:47:39Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=1807838 – Assigned agent via action command
- 2026-07-20T21:52:35Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=1807838 – RED at accepted baseline fc7539a3874293540a4de6d228b3ea670a8ca2e8 (lane source unchanged; tests added only): zig test src/sql/tokenizer.zig exit 1 with semantic V05 boundary expected 27 74 61 69 6c 5c 27 but absorbed ' NEXT', V06 closed early after backslash plus doubled quote, and I05 absorbed ' OR 1=1 --'; double-quote/backtick compatibility remained green. zig test src/sql/parser.zig exit 1: V02 actual 4f 27 27 52 65 69 6c 6c 79 vs expected 4f 27 52 65 69 6c 6c 79; I01-I03 yielded expressions; I04 bytes 27 27 27 yielded expression despite doubled pair at EOF. All failures were compiled semantic assertions, not API/compile failures.
- 2026-07-20T21:54:12Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=1807838 – RED public boundary before production edits: zig build test --summary failures exit 1; 181/188 passed. The new ABI regression compiled and failed during the valid literal insertion matrix with transaction_error where ok was required (baseline scanner misbounded backslash/apostrophe input). Native failures remained the same 6 semantic assertions. Public ABI test already checks exact returned bytes/row ids, parse_error plus null result for I05/I06, unchanged row set, and checkpoint-close-reopen; no build/API production file was changed.
- 2026-07-20T21:57:44Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=1807838 – Evidence correction: the first pre-production ABI build failure reported transaction_error because the new test omitted ShovelerDB's required BEGIN/COMMIT around DML; that harness failure is not counted as SQL-literal RED evidence. The test was corrected to use the existing transaction protocol. Qualifying pre-production RED remains the compiled native V02/V05/V06 and I01-I05 tokenizer/parser failures recorded earlier.
- 2026-07-20T21:57:46Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=1807838 – GREEN: Zig 0.16.0; zig fmt --check src/sql/tokenizer.zig src/sql/parser.zig tests/integration/abi_acceptance.zig exit 0; zig test src/sql/tokenizer.zig 9/9; zig test src/sql/parser.zig 37/37; zig build test --summary all 41/41 steps and 190/190 tests; git diff --check exit 0. ABI covers V02/V04-V09 exact bytes, one mutation per insert, I05/I06 parse_error + null result + zero mutation + unchanged 7-row set, checkpoint-close-reopen exact rows. Double-quote/backtick and public ABI surface unchanged.
- 2026-07-20T22:05:21Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=1807838 – Implementation handoff for commit 75f96d08135491e177b1be0badcfb61028708b2c. Accepted baseline fc7539a3874293540a4de6d228b3ea670a8ca2e8. Red evidence captured with the final tests against baseline scanning and clone semantics: zig test src/sql/tokenizer.zig exited 1 with semantic failures for trailing backslash V05, hostile doubled-apostrophe V06, doubled-pair EOF I04, and raw-backslash boundary I05 while double-quote/backtick compatibility stayed green; zig test src/sql/parser.zig exited 1 with O double-apostrophe Reilly remaining encoded and I01/I04 returning expressions instead of diagnostics. Final green: tokenizer 9/9, parser 37/37, zig build test --summary all 190/190, zig fmt --check on all three owned files exit 0, git diff --check exit 0. ABI regression round-trips O apostrophe Reilly, interior/trailing backslashes, hostile SQL-looking text, comment markers/semicolon, Unicode, and newline byte-exactly; I05/I06 return public parse_error with null results and unchanged 7-row cardinality; checkpoint, close, and reopen preserve all 7 rows. Double-quoted strings, backtick identifiers, public ABI, storage format, dependencies, and build files are unchanged. Commit contains exactly src/sql/tokenizer.zig, src/sql/parser.zig, and tests/integration/abi_acceptance.zig. Ruff diff-scoped check not applicable: no Python files. Independent review required; implementer did not self-review. Charter checklist selector was absent, so checked-in charter and AGENTS review standards were applied.
- 2026-07-20T22:06:54Z – codex:gpt-5:implementer-ivan:implementer – shell_pid=1807838 – Ready for independent review: implementation commit 75f96d0; tokenizer 9/9, parser 37/37, full suite 190/190; ABI hostile/boundary/reopen coverage green; exactly three owned files; worktree clean.
