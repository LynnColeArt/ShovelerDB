# SQL Literal Semantics Contract

**Version**: 1
**Scope**: Single-quoted SQL string literals only
**Normative requirements**: FR-001 through FR-009

## Normative Rules

1. Byte `0x27` opens a single-quoted literal.
2. While the literal is open, `0x27 0x27` represents one decoded `0x27` and
   scanning continues.
3. While the literal is open, a `0x27` not immediately followed by another
   `0x27` closes the literal.
4. Byte `0x5c` (backslash) is ordinary data and never consumes or changes the
   meaning of the following byte.
5. All other bytes are ordinary data, including whitespace, newline, comment
   markers, semicolons, and UTF-8 continuation bytes.
6. End-of-input before rule 3 occurs is an unterminated literal and must produce
   a parse failure before execution.
7. Decoding removes only the outer delimiters and reduces only doubled single
   quotes. It performs no other escape processing or normalization.

## Exact Valid Cases

Hex columns are normative where punctuation spelling could be ambiguous.

| Case | SQL literal source | Source bytes (hex) | Expected decoded text | Decoded bytes (hex) |
| --- | --- | --- | --- | --- |
| V01 empty | `''` | `27 27` | empty | empty |
| V02 apostrophe | `'O''Reilly'` | `27 4f 27 27 52 65 69 6c 6c 79 27` | `O'Reilly` | `4f 27 52 65 69 6c 6c 79` |
| V03 one apostrophe | `''''` | `27 27 27 27` | `'` | `27` |
| V04 interior backslash | `'a\b'` | `27 61 5c 62 27` | `a\b` | `61 5c 62` |
| V05 trailing backslash | source defined by hex | `27 74 61 69 6c 5c 27` | `tail\` | `74 61 69 6c 5c` |
| V06 hostile data | source defined by hex | `27 5c 27 27 20 4f 52 20 31 3d 31 20 2d 2d 27` | `\' OR 1=1 --` | `5c 27 20 4f 52 20 31 3d 31 20 2d 2d` |
| V07 comments and semicolon | `'--x;/*y*/#z'` | `27 2d 2d 78 3b 2f 2a 79 2a 2f 23 7a 27` | `--x;/*y*/#z` | `2d 2d 78 3b 2f 2a 79 2a 2f 23 7a` |
| V08 newline | source defined by hex | `27 6c 69 6e 65 31 0a 6c 69 6e 65 32 27` | two lines | `6c 69 6e 65 31 0a 6c 69 6e 65 32` |
| V09 Unicode | `'naïve 猫'` | UTF-8 bytes wrapped by `27` | `naïve 猫` | exact interior UTF-8 bytes |
| V10 consecutive apostrophes | `'a''''b'` | `27 61 27 27 27 27 62 27` | `a''b` | `61 27 27 62` |

## Exact Invalid and Boundary Cases

| Case | Source bytes (hex) | Required tokenizer/parser outcome | Required execution outcome |
| --- | --- | --- | --- |
| I01 opening only | `27` | unterminated parse failure | no execution |
| I02 ordinary data then EOF | `27 61 62 63` | unterminated parse failure | no execution |
| I03 terminal backslash | `27 61 5c` | unterminated parse failure; backslash does not consume EOF | no execution |
| I04 doubled pair then EOF | `27 27 27` | unterminated parse failure even though final byte is `27` | no execution |
| I05 raw backslash boundary | `27 5c 27 20 4f 52 20 31 3d 31 20 2d 2d` | token closes after `27 5c 27`; suffix is outside the literal | surrounding intentionally incomplete mutation rejects and leaves row count unchanged |
| I06 semicolon suffix after unterminated literal | opening quote plus data with no close followed by mutation-looking bytes | complete parse failure | zero partial or subsequent mutation |

## Compatibility Cases

- Existing double-quoted string tests must retain their baseline result.
- Existing backtick-quoted identifier tests must retain their baseline result.
- The public ABI function signatures, status enums, ownership, and version stay
  unchanged.

## Layer Coverage

| Case group | Tokenizer | Parser | Public C ABI | Checkpoint/reopen |
| --- | --- | --- | --- | --- |
| V01-V10 | boundary subset | all exact decoded bytes | V02, V04-V09 proportionate subset | V02, V05, V06, V08, V09 |
| I01-I04 | all | all reject | representative reject | not applicable |
| I05-I06 | exact token boundary | complete statement rejects where intentionally incomplete | zero unintended rows/mutations | confirm unchanged durable row set |
| compatibility | double/backtick focused case | existing full suite | existing suite | existing suite |

## Red-First Evidence Rule

At least V02, V05, V06, I04, and I05 must demonstrably fail against baseline
`fc7539a3874293540a4de6d228b3ea670a8ca2e8` before production edits. The WP
activity log records the focused command, failing assertions, and baseline
commit. Tests that pass at baseline do not satisfy C-002.
