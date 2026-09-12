# 验收与发布准备

## 可复现检查

从干净检出安装 MoonBit 与本机 C 工具链后，先执行 moon update 初始化工具脚本的依赖索引。

```text
moon run scripts/verify.mbtx
moon test --target native --deny-warn -p cmd/boofuzz
moon run --target native cmd/boofuzz -- generate examples/offline.json --limit 3
moon package --list
moon package
```

verify 包含 fmt/info、Wasm 和 Native check/build/test、格式检查，并保存 Native 库接口到 docs/*.native.mbti。GCC/Clang 下运行 scripts/asan.mbtx，覆盖网络与文件桥接。CI 使用 Windows/MSVC 和 Linux，并在 Linux 执行 ASan。

## 三个端到端场景

| 场景 | 验证内容 |
|---|---|
|离线解析器输入|生成空值、非 UTF-8 和普通字符串，真实解析函数接受/拒绝输入且不损坏原字节。|
|TCP 健壮性|向临时回环监听端口发送二进制请求，记录接收超时，report 定位失败，删除原定义后仍能按记录重放相同字节。|
|有状态协议|每个新 TCP 连接重新发送 HELLO、AUTH 和变异 DATA，检查逐例前置顺序、记录与汇总。|

这些场景在 cmd/boofuzz/scenarios_wbtest.mbt 中执行，使用临时文件、端口和有界等待。另有 UDP 空报文、来源过滤、截断错误及 CLI 集成测试。

## 发布清单

- 检查 git status，确认仅包含预期内容；验证初始化之后恰有 20 个功能提交。
- 确认最新提交已同步 GitHub，并打开 Actions 验证最终提交的双平台检查。
- 审查 moon package --list，确保源码、LICENSE、说明和样本齐全，构建缓存及本地日志未进入包。
- 本次准备源码包，不自动打标签或执行 moon publish；发布账户、包名权限和最终二进制许可核查由维护者确认。
- 正式发布后从 mooncakes 安装并复测；此前不宣称已经发布。
