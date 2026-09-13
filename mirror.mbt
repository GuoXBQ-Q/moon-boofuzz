// SPDX-License-Identifier: GPL-2.0-only
// Port of boofuzz/primitives/mirror.py at 518c13904fc32e7f2cc88c9dec934e509062953e.
// The mirror renders whatever its target entry currently renders, including
// any replacement applied to the target; it produces no mutations of its own.

///|
pub fn Node::mirror(name : String, target : String) -> Node {
  Mirrored(name, target)
}

///|
/// Bind a field's default value to a session variable. Inside a test case
/// the variable must exist (upstream raises on a missing ProtocolSession
/// variable); outside, the field's own value renders. Mutations derive from
/// the fallback value, matching upstream's mutation seeding.
pub fn Node::dynamic(name : String, variable : String, field : Field) -> Node {
  Dynamic(name, variable, field)
}
