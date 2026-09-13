///|
fn parse_block(value : Json, depth : Int, root : Bool) -> @core.Block raise {
  guard depth <= 256 else { raise Invalid("definition nesting exceeds 256") }
  @records.require_keys(
    value,
    if root {
      ["name", "children", "condition", "alignment", "group"]
    } else {
      ["type", "name", "children", "condition", "alignment", "group"]
    },
  )
  let name : String = @json.from_json(required(value, "name"))
  let children : Array[Json] = @json.from_json(required(value, "children"))
  let mut block = @core.Block::new(
    name,
    children.map(child => parse_node(child, depth + 1)),
  )
  if property(value, "condition") is Some(condition) {
    let path : String = @json.from_json(required(condition, "field"))
    let op : String = @json.from_json(required(condition, "op"))
    let condition : @core.Condition = match op {
      "eq" | "ne" => {
        @records.require_keys(condition, ["field", "op", "value_hex"])
        let bytes = @records.hex_decode(text(condition, "value_hex", ""))
        if op == "eq" {
          Equal(path, bytes)
        } else {
          NotEqual(path, bytes)
        }
      }
      "in" | "not_in" => {
        @records.require_keys(condition, ["field", "op", "values_hex"])
        let values = hexes(condition, "values_hex")
        if op == "in" {
          OneOf(path, values)
        } else {
          NotOneOf(path, values)
        }
      }
      "gt" | "ge" | "lt" | "le" => {
        @records.require_keys(condition, ["field", "op", "value_hex"])
        let bytes = @records.hex_decode(text(condition, "value_hex", ""))
        // Upstream operand order: the threshold sits on the left of the
        // comparison against the field value (block.py:104-114), so "gt"
        // renders when the field value is lexicographically less.
        if op == "gt" {
          Greater(path, bytes)
        } else if op == "ge" {
          GreaterEqual(path, bytes)
        } else if op == "lt" {
          Less(path, bytes)
        } else {
          LessEqual(path, bytes)
        }
      }
      _ => raise Invalid("unsupported condition operator")
    }
    block = block.when(condition)
  }
  if property(value, "alignment") is Some(alignment) {
    @records.require_keys(alignment, ["modulus", "pattern_hex"])
    block = block.aligned(
      number(alignment, "modulus", 1),
      pattern=@records.hex_decode(text(alignment, "pattern_hex", "00")),
    )
  }
  if property(value, "group") is Some(group) {
    block = block.with_group(@json.from_json(group))
  }
  block
}

///|
fn parse_node(value : Json, depth : Int) -> @core.Node raise {
  guard depth <= 256 else { raise Invalid("definition nesting exceeds 256") }
  let kind : String = @json.from_json(required(value, "type"))
  let name : String = @json.from_json(required(value, "name"))
  if kind == "block" {
    return Nested(parse_block(value, depth, false))
  }
  if kind == "repeat" {
    @records.require_keys(value, [
      "type", "name", "target", "min", "max", "step", "variable",
    ])
    let variable : String? = property(value, "variable").map(item => {
      @json.from_json(item)
    })
    return @core.Node::repeat(
      name,
      @json.from_json(required(value, "target")),
      min=number(value, "min", 0),
      max=number(value, "max", 25),
      step=number(value, "step", 1),
      variable?,
    )
  }
  if kind == "size" {
    @records.require_keys(value, [
      "type", "name", "target", "length", "endian", "offset", "inclusive", "mutations",
    ])
    return @core.Node::size(
      name,
      @json.from_json(required(value, "target")),
      length=number(value, "length", 4),
      endian=endian(value),
      offset=number(value, "offset", 0),
      inclusive=boolean(value, "inclusive", false),
      mutations=unsigned_values(value),
    )
  }
  if kind == "crc32" {
    @records.require_keys(value, [
      "type", "name", "target", "endian", "mutations",
    ])
    let values = unsigned_values(value).map(number => {
      guard number <= 0xffffffffUL else {
        raise Invalid("CRC32 mutation overflow")
      }
      number.to_uint()
    })
    return @core.Node::checksum(
      name,
      @json.from_json(required(value, "target")),
      endian=endian(value),
      mutations=values,
    )
  }
  if kind == "mirror" {
    @records.require_keys(value, ["type", "name", "target"])
    return @core.Node::mirror(name, @json.from_json(required(value, "target")))
  }
  let field : @core.Field = match kind {
    "static" => {
      @records.require_keys(value, ["type", "name", "value_hex", "variable"])
      @core.Field::simple(@records.hex_decode(text(value, "value_hex", "")), [])
    }
    "simple" => {
      @records.require_keys(value, [
        "type", "name", "value_hex", "values_hex", "fuzzable", "fuzz_values", "variable",
      ])
      @core.Field::simple(
        @records.hex_decode(text(value, "value_hex", "")),
        hexes(value, "values_hex"),
        fuzzable=boolean(value, "fuzzable", true),
        fuzz_values=hexes(value, "fuzz_values"),
      )
    }
    "group" => {
      @records.require_keys(value, [
        "type", "name", "values_hex", "default_hex", "fuzzable", "fuzz_values", "variable",
      ])
      let values = hexes(value, "values_hex")
      let fuzzable = boolean(value, "fuzzable", true)
      let extra = hexes(value, "fuzz_values")
      match property(value, "default_hex") {
        None => @core.Field::group(values, fuzzable~, fuzz_values=extra)
        Some(json) =>
          @core.Field::group(
            values,
            default_value=@records.hex_decode(@json.from_json(json)),
            fuzzable~,
            fuzz_values=extra,
          )
      }
    }
    "integer" => {
      @records.require_keys(value, [
        "type", "name", "value", "width", "endian", "fuzzable", "fuzz_values", "variable",
      ])
      @core.Field::integer(
        decimal_u64(text(value, "value", "0")),
        width=number(value, "width", 8),
        endian=endian(value),
        fuzzable=boolean(value, "fuzzable", true),
        fuzz_values=hexes(value, "fuzz_values"),
      )
    }
    "bytes" => {
      @records.require_keys(value, [
        "type", "name", "value_hex", "size", "max_len", "padding_hex", "fuzzable",
        "fuzz_values", "variable",
      ])
      let bytes = @records.hex_decode(text(value, "value_hex", ""))
      let padding = @records.hex_decode(text(value, "padding_hex", "00"))
      let fuzzable = boolean(value, "fuzzable", true)
      let extra = hexes(value, "fuzz_values")
      let size : Int? = property(value, "size").map(item => {
        @json.from_json(item)
      })
      let max_len : Int? = property(value, "max_len").map(item => {
        @json.from_json(item)
      })
      let base = match (size, max_len) {
        (Some(size), Some(max_len)) =>
          @core.Field::binary(
            bytes,
            size~,
            max_len~,
            padding~,
            fuzzable~,
            fuzz_values=extra,
          )
        (Some(size), None) =>
          @core.Field::binary(
            bytes,
            size~,
            padding~,
            fuzzable~,
            fuzz_values=extra,
          )
        (None, Some(max_len)) =>
          @core.Field::binary(
            bytes,
            max_len~,
            padding~,
            fuzzable~,
            fuzz_values=extra,
          )
        (None, None) =>
          @core.Field::binary(bytes, padding~, fuzzable~, fuzz_values=extra)
      }
      base
    }
    "text" | "delimiter" => {
      @records.require_keys(value, [
        "type", "name", "value", "fuzzable", "fuzz_values", "variable",
      ])
      let normal = text(value, "value", if kind == "text" { "" } else { " " })
      let fuzzable = boolean(value, "fuzzable", true)
      let extra = hexes(value, "fuzz_values")
      if kind == "text" {
        @core.Field::text(normal, fuzzable~, fuzz_values=extra)
      } else {
        @core.Field::delimiter(normal, fuzzable~, fuzz_values=extra)
      }
    }
    "random" => {
      @records.require_keys(value, [
        "type", "name", "value_hex", "min_length", "max_length", "max_mutations",
        "step", "fuzzable", "fuzz_values", "variable",
      ])
      let step : Int? = property(value, "step").map(item => {
        @json.from_json(item)
      })
      @core.Field::random_data(
        default_value=@records.hex_decode(text(value, "value_hex", "")),
        min_length=number(value, "min_length", 0),
        max_length=number(value, "max_length", 1),
        max_mutations=number(value, "max_mutations", 25),
        step=step.unwrap_or(0),
        fuzzable=boolean(value, "fuzzable", true),
        fuzz_values=hexes(value, "fuzz_values"),
      )
    }
    "float" => {
      @records.require_keys(value, [
        "type", "name", "value", "format", "f_min", "f_max", "max_mutations", "seed",
        "ieee_754", "endian", "fuzzable", "fuzz_values", "variable",
      ])
      let seed : Int64? = property(value, "seed").map(item => {
        decimal_u64(@json.from_json(item)).reinterpret_as_int64()
      })
      @core.Field::float(
        default_value=@json.from_json(required(value, "value")),
        s_format=text(value, "format", ".1f"),
        f_min=@json.from_json(required(value, "f_min")),
        f_max=@json.from_json(required(value, "f_max")),
        max_mutations=number(value, "max_mutations", 1000),
        seed=seed.unwrap_or(0L),
        encode_as_ieee_754=boolean(value, "ieee_754", false),
        endian=endian(value),
        fuzzable=boolean(value, "fuzzable", true),
        fuzz_values=hexes(value, "fuzz_values"),
      )
    }
    "lines" => {
      @records.require_keys(value, [
        "type", "name", "lines", "max_len", "fuzzable", "fuzz_values", "variable",
      ])
      let raw_lines : Array[String] = @json.from_json(required(value, "lines"))
      @core.Field::from_lines(
        lines=raw_lines.map(line => @utf8.encode(line)),
        max_len=number(value, "max_len", 0),
        fuzzable=boolean(value, "fuzzable", true),
        fuzz_values=hexes(value, "fuzz_values"),
      )
    }
    _ => raise Invalid("unsupported field type: " + kind)
  }
  // A field bound to a session variable renders the variable's value inside
  // a test case and its own value otherwise (ProtocolSessionReference).
  match property(value, "variable") {
    Some(variable) =>
      @core.Node::dynamic(name, @json.from_json(variable), field)
    None => Leaf(name, field)
  }
}
