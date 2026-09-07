# 2026 年 9 月报名自查

依据：维护者提供的 9 月赛事章程文本（2026-09-07 读取）。这里摘录操作要求，不替代官方规则；章程中的图片报名入口未包含在纯文本中。

- 方向：新生态项目建设。
- 申报截止：9 月 24 日 24 点；开发及验收也安排在 9 月 24 日前后，不能把它理解成报名后还有完整开发月份。
- 仓库：https://github.com/GuoXBQ-Q/moon-boofuzz 。本地配置此地址并不代表远程已创建或公开。
- 本期要求公开 GitHub，不要求 Gitlink。
- 申报书：本人撰写，一页 Markdown，至少 3 个完整的预期使用场景。
- 仓库需不少于 10 个有效 commits；不能使用空提交、重复提交或机械拆分凑数。骨架初始化本身不满足此项。

## 提交报名之前

- [ ] 在 GitHub 创建公开空仓库并推送，确认默认分支包含最新文件。
- [ ] 通过后续真实功能、测试与文档开发形成不少于 10 个有效提交。
- [ ] 人工完成一页申报书；docs/PROPOSAL-WORKSHEET.md 只是填写提纲。
- [ ] 补充自身实际痛点、三个场景和可兑现的功能边界。
- [ ] 再次核查 Mooncakes 选题重复情况，并记录差异。
- [ ] 确认远程 Actions 实际成功；本地通过不等于远程 CI 已通过。
- [ ] 通过官方问卷报名并加入赛事通知群。

## 选题初查记录

2026-09-07 执行 `moon search fuzz --limit 10`：返回 6 项，主要为 fuzzy_match / fuzzyscore / fuzzy_search、图像颜色提取与 Bitap 字符串匹配，未发现直接对应的协议模糊测试框架。这是关键词初筛，不是完整的无竞品证明。后续请扩展 boofuzz、fuzzer、protocol 等检索并阅读相关包文档。

## 验收之前

- [ ] 实现申报书承诺的主要功能及三个可复现场景。
- [ ] MoonBit 为主要实现语言；README、源代码、测试、可运行示例齐全。
- [ ] CI 覆盖 check/build/test 并通过。
- [ ] 发布到 mooncakes.io 并验证安装。
- [ ] 来源、许可证、合理开发历史清晰。

## 首次同步

仓库已在本地初始化；请先检查 `git status`。完成首次提交后，在 GitHub 创建同名公开空仓库，再执行：

```sh
git branch -M main
git remote add origin https://github.com/GuoXBQ-Q/moon-boofuzz.git
git push -u origin main
```

若还没有首次提交，先执行 `git add .` 和 `git commit -m "Initialize MoonBit protocol mutation skeleton"`。若 origin 已存在，先检查 `git remote -v`，不要重复添加。
