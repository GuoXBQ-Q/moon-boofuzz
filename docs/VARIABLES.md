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

## 边回调（challenge-response）

`SessionGraph::connect(from, to, callback=fn(ctx) { ... })` 在边上挂回调。
回调在**发送该节点数据之前**执行（上游 `_callback_current_node` 先于
transmit，session.py:754-794），收到 `StepContext`：

- `variables`：当前用例的会话变量表（可写入，后续渲染立即可见）；
- `received`：本用例此前各步收到的响应字节；
- `request`：目标请求名。

返回 `Some(bytes)` 且非空时**整体替代**该节点发送数据（空/None 回退为
渲染值，对应 Python falsy 语义）；节点的渲染发生在回调之后，因此动态
字段能看到回调写入的变量。JSON 定义无法表达回调，仅 MoonBit API 可用。
`SessionPath::transitions` 按请求携带各边回调；目标载荷在发送时用
`render_case(parts, vars)` 重新渲染（等价上游 render-at-send）。

作用域差异（有意保留）：本移植整条用例共享一张变量表，早边回调的
写入对后续所有步骤可见；上游为每条边新建 `ProtocolSession`，写入仅
对同一节点可见，后续节点引用未写变量会 KeyError。纯 JSON 定义不含
边回调，该差异只影响 MoonBit 会话。

## 边界

回调本身不可抛错（返回 Bytes?）；JSON 定义无法注入回调。

Source: `boofuzz/protocol_session*.py`、`fuzzable.py`、
`blocks/repeat.py`、`sessions/session.py`（ProtocolSession 构造与传递）。
动态字段的编译期验证与位置稳定的候选模型是 MoonBit 适配。
`session_variables_test.mbt` 覆盖三条路径（外部渲染、变量解析、缺失报错）。
