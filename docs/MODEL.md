# Named protocol model

Build `Block::new("request", [Leaf("opcode", field), Nested(child_block)])`,
then call `CompiledRequest::compile(root)`. Construction snapshots child arrays;
compilation validates all names and returns a read-only execution model.
Qualified references include the request name, for example `request.body.data`.
`render_path` rejects unknown paths. Same leaf names in different blocks are valid.
Names cannot be empty or contain dots/slashes; nesting is limited to 256 levels.

`render()` concatenates nested contents in insertion order. Its default maximum
is 1 MiB of wire bytes, adjustable using `max_bytes`. Excess raises
`ModelError::Limit`, including when UTF-8 expands into more bytes than characters.
`CompiledRequest::from_request("name", legacy_request)` preserves old defaults
and gives flat fields names `field0`, `field1`, etc. Old APIs remain available.

A block can link to a Group field with `block.with_group("request.op")`.
Upstream enumeration order is reproduced exactly: the block's plain child
mutations come first, then the child sequence replays once per Group
candidate with the group value and one child mutation combined. A block of
`n` base cases therefore yields `n*(1+g)` cases. Product cases carry both
fields: `field_path`/`mutation_index` identify the leaf mutation and `extra`
lists the group parts outer-first; case ids join all parts with `+`, so
names cannot contain `+`. `Node::mirror("echo", "request.target")` renders
whatever its target currently renders (including replacements) and produces
no mutations of its own; a mirror may not live inside its target's subtree.

Source: structural concepts from `boofuzz/blocks/request.py`, `block.py` and
`boofuzz/fuzzable_block.py`, pinned at
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
The immutable compiler and strict full-path API are MoonBit adaptations;
Python's mutable DSL and relative name resolution are not implemented.
`model_test.mbt` validates nested wire bytes, snapshots, paths and error cases.
