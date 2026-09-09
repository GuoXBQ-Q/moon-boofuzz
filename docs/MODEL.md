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

Source: structural concepts from `boofuzz/blocks/request.py`, `block.py` and
`boofuzz/fuzzable_block.py`, pinned at
`518c13904fc32e7f2cc88c9dec934e509062953e` (GPL-2.0-only).
The immutable compiler and strict full-path API are MoonBit adaptations;
Python's mutable DSL and relative name resolution are not implemented.
`model_test.mbt` validates nested wire bytes, snapshots, paths and error cases.
