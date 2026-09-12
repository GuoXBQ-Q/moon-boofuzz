///|
fn parse_block(value : Json, depth : Int, root : Bool) -> @core.Block raise {
  guard depth <= 256 else { raise Invalid("definition nesting exceeds 256") }
  @records.require_keys(
    value,
    if root {
      ["name", "children", "condition", "alignment"]
    } else {
      ["type", "name", "children", "condition", "alignment"]
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
      "in" => {
        @records.require_keys(condition, ["field", "op", "values_hex"])
        OneOf(path, hexes(condition, "values_hex"))
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
      "type", "name", "target", "min", "max", "step",
    ])
    return @core.Node::repeat(
      name,
      @json.from_json(required(value, "target")),
      min=number(value, "min", 0),
      max=number(value, "max", 25),
      step=number(value, "step", 1),
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
  let field : @core.Field = match kind {
    "static" => {
      @records.require_keys(value, ["type", "name", "value_hex"])
      @core.Field::simple(@records.hex_decode(text(value, "value_hex", "")), [])
    }
    "simple" => {
      @records.require_keys(value, [
        "type", "name", "value_hex", "values_hex", "fuzzable",
      ])
      @core.Field::simple(
        @records.hex_decode(text(value, "value_hex", "")),
        hexes(value, "values_hex"),
        fuzzable=boolean(value, "fuzzable", true),
      )
    }
    "group" => {
      @records.require_keys(value, [
        "type", "name", "values_hex", "default_hex", "fuzzable",
      ])
      let values = hexes(value, "values_hex")
      let fuzzable = boolean(value, "fuzzable", true)
      match property(value, "default_hex") {
        None => @core.Field::group(values, fuzzable~)
        Some(json) =>
          @core.Field::group(
            values,
            default_value=@records.hex_decode(@json.from_json(json)),
            fuzzable~,
          )
      }
    }
    "integer" => {
      @records.require_keys(value, [
        "type", "name", "value", "width", "endian", "fuzzable",
      ])
      @core.Field::integer(
        decimal_u64(text(value, "value", "0")),
        width=number(value, "width", 8),
        endian=endian(value),
        fuzzable=boolean(value, "fuzzable", true),
      )
    }
    "bytes" => {
      @records.require_keys(value, [
        "type", "name", "value_hex", "size", "max_len", "padding_hex", "fuzzable",
      ])
      let bytes = @records.hex_decode(text(value, "value_hex", ""))
      let padding = @records.hex_decode(text(value, "padding_hex", "00"))
      let fuzzable = boolean(value, "fuzzable", true)
      let size : Int? = property(value, "size").map(item => {
        @json.from_json(item)
      })
      let max_len : Int? = property(value, "max_len").map(item => {
        @json.from_json(item)
      })
      match (size, max_len) {
        (Some(size), Some(max_len)) =>
          @core.Field::binary(bytes, size~, max_len~, padding~, fuzzable~)
        (Some(size), None) =>
          @core.Field::binary(bytes, size~, padding~, fuzzable~)
        (None, Some(max_len)) =>
          @core.Field::binary(bytes, max_len~, padding~, fuzzable~)
        (None, None) => @core.Field::binary(bytes, padding~, fuzzable~)
      }
    }
    "text" | "delimiter" => {
      @records.require_keys(value, ["type", "name", "value", "fuzzable"])
      let normal = text(value, "value", if kind == "text" { "" } else { " " })
      let fuzzable = boolean(value, "fuzzable", true)
      if kind == "text" {
        @core.Field::text(normal, fuzzable~)
      } else {
        @core.Field::delimiter(normal, fuzzable~)
      }
    }
    _ => raise Invalid("unsupported field type: " + kind)
  }
  Leaf(name, field)
}
