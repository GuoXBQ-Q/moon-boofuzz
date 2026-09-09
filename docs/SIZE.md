# Computed sizes

`Node::size("len", "request.body", length=4, endian=Little, offset=0,
inclusive=false, mutations=[])` encodes a block's current wire length.
Length is 1/2/4/8 bytes; explicit mutations are unsigned integer values that
replace the computed length. No automatic size mutations or math callbacks
are implied. The target must be a full block path.

Self-containing sizes are supported: measuring a parent counts the size field's
fixed width. As upstream does, inclusive=true adds that width again, even if
the target already contains the size field. Measuring never needs to render
a recursive size field. Ordinary cross-block size cycles, unknown references,
negative results and encoding overflow are errors. Offset arithmetic uses
Int64, and payload length changes are observed on every case.

Source: `boofuzz/blocks/size.py`, baseline
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
The dependency compiler and strict overflow errors are MoonBit adaptations.
`fixtures/size.json` regenerates `size_fixture_test.mbt`; request-level samples
compare the complete default and mutation payloads, including parent sizing,
Repeat and conditional switching. Upstream reference strings omit the request
prefix, while this API requires it explicitly.
