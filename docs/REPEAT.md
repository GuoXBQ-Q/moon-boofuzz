# Repeat blocks

Add `Node::repeat("copies", "request.item", min=0, max=25, step=1)` after
the referenced block. Default output is empty; mutations append `min`,
`min + step`, ... copies through `max` inclusive. The original referenced
block still renders in its original position. Zero copies is a valid case.
Ranges must be nonnegative, ordered and have positive step. Targets must be
preceding, completed blocks; unknown, forward and ancestor references fail
compilation. Variable-controlled repetition is exposed: pass
`variable="copies"` (JSON `"variable"`) to read the repeat count from the
session variable of the same name, falling back to 0 outside a mutating
case, exactly like upstream's `Repeat(variable=...)` (see VARIABLES.md).
Upstream's `fuzzable`, `fuzz_values` and explicit `default_value` on the
repeat node itself are not exposed; the count mutations above always
enumerate when the target block mutates.

Source: `boofuzz/blocks/repeat.py` at
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
`repeat_test.mbt` covers default, sequence, order, invalid references and byte
limits. Repetition checks the byte bound before allocating the repeated data.
