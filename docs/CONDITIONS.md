# Conditional blocks

Use `block.when(Equal("request.flag", b"1"))`, `NotEqual`, `OneOf`,
`NotOneOf`, or the ordering variants `Greater`, `GreaterEqual`, `Less`,
`LessEqual`. Set membership snapshots its value array. References must identify fields in
the compiled request, using a complete path; missing or block references fail
compilation. Nested blocks inherit ancestor visibility.

Conditions read the current candidate bytes before rendering. As upstream,
every candidate still emits a test case; a hidden block simply contributes
empty bytes, so ordinals have no gaps. Ordering comparisons keep upstream's
operand order: the threshold sits left of the field value, so `Greater`
renders when the field value is lexicographically less than the configured
bytes. Empty OneOf or NotOneOf means always hidden or always visible.

Source: equality/inequality/dependency-set behavior in
`boofuzz/blocks/block.py`, baseline
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
Ordering comparisons now follow upstream's reversed operand order exactly;
`num_mutations` on disabled fields still reports zero. Group Cartesian
multiplication is documented in MODEL.md.
