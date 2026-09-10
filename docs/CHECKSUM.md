# CRC32 fields

`Node::checksum("crc", "request.body", endian=Little, mutations=[])` emits
IEEE CRC32 with a four-byte result. Explicit UInt mutations replace the correct
checksum. Other algorithms are not exposed. `crc32(bytes)` is also available.
Payload mutation recomputes checksums on each render. If the target contains
the checksum, its own bytes are zero during calculation, as in upstream.

Size measurement counts checksum width without computing checksum bytes;
therefore a parent length plus a parent checksum is supported. Cross-checksum
cycles and unknown references are rejected at compilation, including hidden
branches. Limits apply to target rendering and final payloads.

Source: `boofuzz/blocks/checksum.py` at
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only), using its CRC32
semantics. The polynomial implementation is a new MoonBit implementation of
the standard algorithm, with empty and 123456789 vectors in tests.
`fixtures/checksum.json` regenerates `checksum_fixture_test.mbt`; it compares
full upstream payloads for target mutations and self-containing checksum plus
parent length, including multibyte payload growth.
