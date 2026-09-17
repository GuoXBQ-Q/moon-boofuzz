# 补充原语与通用变异追加

四个上游原语与通用的 `fuzz_values` 机制在核心包补齐，随机序列由内置的
MT19937（`mt19937.mbt`）驱动，与 CPython `random.Random` 逐位一致。

## fuzz_values（通用追加变异）

所有字段构造器（`simple`/`group`/`integer`/`binary`/`text`/`delimiter`/
`random_data`/`float`/`from_lines`）接受 `fuzz_values=[...]`，追加在内置
候选之后且变异下标连续递增。`fuzzable=false` 的字段不产生任何用例
（上游 `get_num_mutations` 对禁用字段仍计入 `fuzz_values`，本移植保持
`num_mutations` 等于实际可枚举用例数的既有声明，见 UPSTREAM.md）。

## RandomData

`Field::random_data(default_value=b"", min_length=0, max_length=1,
max_mutations=25, step=None, ...)` 复现上游 `Random(0)` 确定性序列：非
step 模式每条候选先抽长度再逐字节抽取；step 模式长度固定为
`min_length + i*step` 且不消耗随机流。候选按需物化并由构造器快照，位置
访问天然稳定；上游 `mutations()` 以 `get_num_mutations()` 为上界的计数
怪癖（会把 `fuzz_values` 一并计入随机条数）未复现，随机条数恒为
`max_mutations`，用户追加值排在其后。候选总字节超过 20 MB 拒绝。

## Float

`Field::float(default_value=0.0, s_format=".1f", f_min=0.0, f_max=100.0,
max_mutations=1000, seed=None, encode_as_ieee_754=false, endian=Big, ...)`
复现上游序列：首条变异是按 `s_format` 格式化的默认值，其后为
`uniform(f_min, f_max)`，相邻去重时随机数照常消耗。格式化仅支持
CPython 的 `"%.Nf"` 子集（`"f"` 为默认 6 位、`".f"` 为 0 位、`".Nf"` 为
N 位，N 上限 1,000,000），对 double 的精确二进制值做一次十进制舍入
（half-to-even），与 CPython `"%f"` 输出逐字节一致（如 `"%.1f" % 0.05`
为 `"0.1"`）；带点的数字之外的形式（宽度/标志/`e`/`g` 等）显式拒绝。
默认值按上游 `str(default_value)` 渲染（如 `2.5`），不经 `s_format`。
编码支持 UTF-8 文本与 IEEE 754 binary32
（含大小端）。上游 `seed=None` 依赖进程级全局随机数；本移植固定使用
种子 0 以保证候选身份稳定，需要变化时显式传 `seed`；`seed` 取非负
整数（上游允许负数与 str/bytes 种子）。上游
`num_mutations` 恒报 `max_mutations` 而去重后实际产出更少；本移植的
`num_mutations` 等于实际产出的候选数。

## FromFile 等价

核心包无文件 IO，`Field::from_lines(default_value=b"", lines=[...],
max_len=0, ...)` 由调用方读入行（JSON 用 `lines` 数组提供 UTF-8 文本）。
空行剔除与上游一致；`max_len > 0` 时上游经 `set` 去重会丢失顺序，本
移植保留首次出现顺序。

Source: `boofuzz/primitives/random_data.py`、`float.py`、`from_file.py`
与 `boofuzz/fuzzable.py`（fuzz_values 追加与下标连续语义），基线
`518c13904fc32e7f2cc88c9dec934e509062953e`（GPL-2.0-only）。
MT19937 与 CPython `random` 模块语义（int 种子 init_by_array、
`_randbelow_with_getrandbits`、`random()` 53 位精度）为新增的等价实现，
由 `mt19937_wbtest.mbt` 以 CPython 3.12 探针值逐位断言；
`primitives_fixture_test.mbt` 记录了 oracle 差分序列
（RandomData 逐字节、Float 文本与 IEEE754 逐字节、Size/Checksum 边界）。
重新生成差分样本用 `moon run scripts/oracle.mbtx ABSOLUTE_UPSTREAM EXPRESSION`。
