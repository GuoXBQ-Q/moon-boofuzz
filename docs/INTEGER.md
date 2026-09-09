# Binary integers

`Field::integer(value : UInt64, width=8, endian=Little, fuzzable=true)` supports
8/16/32/64 bit unsigned values. `Big` emits network byte order. Defaults outside
the chosen width and unsupported widths raise `ModelError::Invalid`.

Example: `Field::integer(0x1234UL, width=16, endian=Big).default_value()` emits
`12 34`. Candidates are generated around 0, 2^width divided by 32/16/8/4/3/2,
and 2^width, sorted and deduplicated exactly like upstream. The 64-bit upper
boundary uses quotient/remainder arithmetic, so it never overflows UInt64.
ASCII/signed decimal formatting, full_range and max_num are not exposed.

Source: `boofuzz/primitives/bit_field.py` at
`518c13904fc32e7f2cc88c9dec934e509062953e`, GPL-2.0-only.
Reproduce all eight endian/width fixtures with `scripts/fixtures.mbtx`, using
`fixtures/integer.json` and output `integer_fixture_test.mbt` (absolute paths).
Tests compare every byte of every candidate, in order, and the complete count.
