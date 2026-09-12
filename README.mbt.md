# Tested API example

以下示例由 `moon test` 执行。根包测试使用 `@moon_boofuzz` 别名；在自己的项目中，将包导入为所用别名即可。当前尚未发布到 mooncakes，直接运行本仓库示例不需要额外安装该包。

## 命名请求与惰性变异

`CompiledRequest` 用于新协议模型。正常渲染和变异枚举分别调用 `render()` 与 `cases()`；用 `next()` 逐个获取载荷，避免先建立完整用例数组。

```mbt check
///|
test "named request quick start" {
  let request = @moon_boofuzz.CompiledRequest::compile(
    @moon_boofuzz.Block::new("packet", [
      Leaf("prefix", @moon_boofuzz.Field::simple(b"PING ", [])),
      Leaf("value", @moon_boofuzz.Field::simple(b"ok", [b"", b"\x00\xff"])),
    ]),
  )
  assert_eq(request.render(), b"PING ok")
  let cases = request.cases(limit=1)
  assert_eq(cases.next().map(case => case.payload), Some(b"PING "))
  assert_eq(cases.next(), None)
  assert_eq(cases.state(), Limited)
  let resumed = request.cases(start=cases.position())
  assert_eq(resumed.next().map(case => case.payload), Some(b"PING \x00\xff"))
}
```

字段路径包含请求名，例如 `packet.value`。会话图、网络执行及回调的使用分别见 `docs/SESSION.md`、`docs/RUNNER.md` 和 `docs/MONITORS.md`。

## Simple and Group

`Field::simple(default, candidates)` preserves every explicit candidate.
`Field::group(values, default_value=...)` selects the first value by default,
then removes only the first matching default from mutation candidates.
Both snapshot input arrays; `fuzzable=false` yields zero cases. Indices are
zero based and out-of-range access returns `None`. Use these fields as named
Leaf nodes in CompiledRequest; the legacy flat Request remains available.

```mbt check
///|
test "group field" {
  let field = @moon_boofuzz.Field::group([b"GET", b"POST", b"GET"])
  assert_eq(field.default_value(), b"GET")
  assert_eq(field.num_mutations(), 2)
  assert_eq(field.mutation(0), Some(b"POST"))
  assert_eq(field.mutation(1), Some(b"GET"))
}
```

```mbt check
///|
test "minimal byte request" {
  let request = @moon_boofuzz.Request::new([
    @moon_boofuzz.Static(b"PING "),
    @moon_boofuzz.Choice(b"ok", [b"", b"long"]),
  ])
  assert_eq(request.render(), b"PING ok")
  assert_eq(request.mutations(), [b"PING ", b"PING long"])
}
```
