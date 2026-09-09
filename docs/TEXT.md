# UTF-8 strings and delimiters

`Field::text("hello")` generates the bad-string corpus, 2/10/100 default
repetitions, long-string boundaries and fixed null-insertion cases from
`boofuzz/primitives/string.py` at revision
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
The null positions are extracted from upstream's seeded generator; runtime
generation needs no random number generator and no Python dependency.
Long strings use compact recipes and are allocated on indexed access.

The supported String subset is UTF-8 with dynamic size. Upstream's size and
max_len options are deliberately not exposed: its mutation truncation counts
characters, while its encoder padding counts bytes. Request rendering applies
an explicit wire-byte limit and reports excess instead of truncating UTF-8.
`default_value().length()` therefore measures wire bytes, not characters.

`Field::delimiter(":")` implements repetition, replacement and deletion.
The ASCII subset matches upstream; non-ASCII delimiters use UTF-8 explicitly
(upstream's helper uses Latin-1). `fuzzable=false` disables both field types.

`string_library.mbt` is extracted with `scripts/string-library.mbtx`.
`fixtures/text.json` generates `text_fixture_test.mbt` using
`scripts/fixtures.mbtx`. Fixtures preserve the complete bytes of every case;
repeated byte sequences are expressed compactly with `.repeat`, not hashes.
The fixture set compares empty, ASCII and multibyte String defaults, plus
space/colon/empty Delim defaults, including complete candidate counts/order.
