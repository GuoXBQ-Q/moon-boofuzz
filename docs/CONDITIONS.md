# Conditional blocks

Use `block.when(Equal("request.flag", b"1"))`, `NotEqual`, or `OneOf`.
Set membership snapshots its value array. References must identify fields in
the compiled request, using a complete path; missing or block references fail
compilation. Nested blocks inherit ancestor visibility.

Conditions read the current candidate bytes before rendering. Mutations in a
hidden subtree are suppressed; control-field mutations can enable that subtree.
Cursor ordinals retain positions in the underlying field candidate sequence,
so hidden cases create gaps. Resume using `position()` rather than emitted count.
Enumeration limits count only emitted cases. Empty OneOf means always hidden.

Source: equality/inequality/dependency-set behavior in
`boofuzz/blocks/block.py`, baseline
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
Ordering comparisons and Group Cartesian multiplication are unsupported.
