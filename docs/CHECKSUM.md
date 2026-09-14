# CRC32 fields

`Node::checksum("crc", "request.body", endian=Little, mutations=[],
algorithm=Crc32)` emits a checksum over the target. Supported algorithms:
`Crc32` (default), `Crc32c`, `Adler32`, `Md5` and `Sha1` — lengths 4/4/4/16/20
bytes. With no explicit mutations the field emits upstream's six fuzzable
byte boundaries at the algorithm's length (00*, 11*, ee*, ff*, ff*(n-1)+fe,
00*(n-1)+01); explicit `mutations` replace them (32-bit family only —
MD5/SHA-1 digests exceed 64 bits). MD5/SHA-1 render with upstream's
32-bit word swap on big-endian nodes (checksum.py:171-189). `crc32(bytes)` is also available.
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
