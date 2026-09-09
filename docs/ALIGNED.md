# Alignment

`block.aligned(4, pattern=b"AB")` appends a repeating padding pattern until
the next multiple of four bytes. An empty or already aligned block receives
an entire four-byte padding group. This intentionally preserves the pinned
upstream behavior, rather than conventional zero padding when already aligned.
Modulus must be positive and the pattern nonempty. Padding checks the compiled
request's wire-byte limit before allocation.

Source: `boofuzz/blocks/aligned.py` at
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
The fixture inputs cover empty, exact alignment, partial and multibyte patterns;
run `scripts/fixtures.mbtx` with `fixtures/aligned.json` to regenerate
`aligned_fixture_test.mbt`.
