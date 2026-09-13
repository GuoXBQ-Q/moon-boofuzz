# 会话变量与动态字段

会话变量让字段的默认渲染值在执行期确定，对齐上游
`ProtocolSession` / `ProtocolSessionReference` 与 `Repeat(variable=...)`
（基线 `518c13904fc32e7f2cc88c9dec934e509062953e`，GPL-2.0-only）。

## 语义

- `Node::dynamic("token", "auth", field)` 把字段的默认值绑定到变量
  `auth`。**测试用例之外**（编译校验、离线 generate）渲染字段的
  fallback 值；**测试用例之内**（Runner 执行）渲染变量的值，变量缺失
  报类型化错误——精确对齐上游 `original_value(test_case_context)` 的
  None/Some 双路径（fuzzable.py:108-122，缺失即 KeyError）。
- 变异候选始终从 fallback 值播种（上游 `get_mutations` 不传 context）。
- 条件块的目标可以是动态字段，比较使用变量的当前值。
- `Node::repeat(..., variable="n")`：重复次数从变量解析（u32 小端
  字节）；用例之外回退为 0；静态候选（min..max 的次数变异）不受影响，
  且 variable **不**禁用 Repeat 自身的 fuzzing——上游 docstring 声称
  禁用但实现并未禁用（repeat.py:69-84），本移植保留实现行为。

## 接线

- MoonBit API：`path.cases(vars=Some(map))`、
  `Runner::new(..., vars=map)`。
- JSON `execution` 段：`"variables": {"auth": "68656c6c6f"}`（值为
  hex 字符串）；字段与 repeat 节点上的 `"variable"` 键。

## 边界

JSON 定义无法注入"写变量"的回调；运行期修改变量需要 MoonBit API
（边回调接入前的过渡方案是 execution.variables 静态注入）。

Source: `boofuzz/protocol_session*.py`、`fuzzable.py`、
`blocks/repeat.py`、`sessions/session.py`（ProtocolSession 构造与传递）。
动态字段的编译期验证与位置稳定的候选模型是 MoonBit 适配。
`session_variables_test.mbt` 覆盖三条路径（外部渲染、变量解析、缺失报错）。
