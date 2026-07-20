# Data Model: SQL Literal Escaping Hardening

This mission does not add a persistent business entity or storage schema. Its
relevant model is the transformation from SQL source bytes to an owned AST text
value and, through existing execution, to a persisted text value.

## Value: Quoted Token

| Field | Type | Meaning | Validation |
| --- | --- | --- | --- |
| `kind` | existing token enum | String versus identifier/symbol category | Single-quoted and double-quoted forms remain strings; backtick remains identifier |
| `lexeme` | borrowed byte slice | Exact SQL source bytes from opening quote through consumed boundary or EOF | Begins at the quote offset; no allocation or normalization |
| `offset` | byte offset | Opening delimiter position in the original SQL | Preserved for diagnostics |
| termination evidence | boolean or equivalent token state | Whether a non-doubled matching closing delimiter was consumed | Must be explicit; cannot be inferred only from the final byte |

### Invariants

- The lexeme borrows from the original SQL input and never outlives that input.
- For single quotes, backslash never advances the scanner by an extra byte.
- A doubled single quote is consumed as interior data, not termination.
- A non-doubled single quote ends the token and marks it terminated.
- Reaching EOF without that transition leaves termination false.
- Existing double-quote and backtick policy stays behaviorally unchanged.

## Value: Decoded String Literal

| Field | Type | Meaning | Validation |
| --- | --- | --- | --- |
| bytes | allocator-owned byte slice | AST literal value after single-quote decoding | Exact expected bytes; valid UTF-8 is preserved without normalization |
| owner | parser/AST allocator | Component responsible for release | Existing expression/statement deinit path releases once |

### Decode Function

For a terminated single-quoted token:

1. Exclude the first and closing quote bytes.
2. Read the interior from left to right.
3. On `''`, append one `'` and advance by two bytes.
4. Otherwise append the current byte unchanged and advance by one.
5. Return an owned slice whose length is no greater than the interior source
   length.

For double-quoted string tokens, retain the accepted baseline transformation;
do not apply the new single-quote policy implicitly.

### Invariants

- Decoding happens once before the AST value is exposed.
- Backslash, newline, NUL if otherwise accepted, comment markers, semicolons,
  and multi-byte UTF-8 sequences are copied byte-for-byte.
- No successful decoded value can originate from an unterminated single-quoted
  token.
- Allocation failure follows the existing parser out-of-memory path.

## State Transitions

```text
source offset at opening single quote
    -> scanning_open
       -> doubled_quote_seen -> scanning_open
       -> ordinary_byte_seen -> scanning_open
       -> non_doubled_quote_seen -> terminated_token
       -> end_of_input -> unterminated_token

terminated_token -> decode -> owned_ast_value -> execute -> existing text value
unterminated_token -> parse diagnostic -> no statement -> no mutation
```

The transition from `unterminated_token` to a statement or value is forbidden.

## Existing Persistence Relationship

The decoded AST value flows through existing executor/catalog/row-store code.
This mission changes neither stored representation nor checkpoint format:

```text
decoded AST bytes
    -> existing INSERT execution
    -> existing committed row text
    -> existing checkpoint snapshot
    -> existing reopen
    -> identical result text bytes
```

The durable ABI test verifies this relationship for representative hostile
values. It is validation of the decoder's consumer-visible effect, not a new
persistence entity.

## Diagnostic Relationship

An unterminated token maps to the existing parser diagnostic surface and then
to the existing public ABI parse status. No new diagnostic code is required.
The diagnostic must point at the opening token or end boundary consistently
enough for existing callers; exact message wording is not part of this mission.
