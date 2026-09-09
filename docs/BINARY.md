# Binary byte mutations

`Field::binary(default, size=..., max_len=..., padding=b"\x00")` implements
the fixed library, default repetition, magic values and every 1/2/4 byte
replacement from upstream `boofuzz/primitives/bytes.py`, revision
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).

Default bytes remain verbatim, even when longer than size/max_len. Mutation
values are truncated to size/max_len, or padded to size. Size takes precedence
over max_len. Duplicate mutations are retained. Each indexed candidate is
generated on demand, rather than materializing the complete payload set.

Padding must be exactly one byte; multi-byte/empty patterns are rejected
because upstream can produce values larger or smaller than its declared size.
Negative lengths are rejected. `fuzzable=false` disables enumeration.
Inputs above 20,000,000 bytes are rejected to keep count arithmetic bounded;
execution limits on compiled requests will impose a smaller default bound.

`fixtures/binary.json` covers empty, zero, non-UTF8, fixed length and zero size;
regenerate `binary_fixture_test.mbt` with `scripts/fixtures.mbtx`.
