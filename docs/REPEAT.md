# Repeat blocks

Add `Node::repeat("copies", "request.item", min=0, max=25, step=1)` after
the referenced block. Default output is empty; mutations append `min`,
`min + step`, ... copies through `max` inclusive. The original referenced
block still renders in its original position. Zero copies is a valid case.
Ranges must be nonnegative, ordered and have positive step. Targets must be
preceding, completed blocks; unknown, forward and ancestor references fail
compilation. Dynamic variable-controlled repetition is not exposed.

Source: `boofuzz/blocks/repeat.py` at
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
`repeat_test.mbt` covers default, sequence, order, invalid references and byte
limits. Repetition checks the byte bound before allocating the repeated data.
