# 上游与来源记录

- 项目：boofuzz，Sulley 的后继项目。
- 地址：https://github.com/jtpereyda/boofuzz
- 研究分支：master。
- 固定基线：518c13904fc32e7f2cc88c9dec934e509062953e。
- 许可证：GPL-2.0-only（上游 LICENSE.txt 为 GPL v2 全文，pyproject.toml 声明 only）。
- 本仓库 LICENSE 从该基线 LICENSE.txt 原样复制。

| 本项目部分 | 参考范围 | 当前来源/兼容状态 |
| --- | --- | --- |
| Primitive | primitives 与协议定义文档的字段思想 | AI 辅助新实现；Static/Choice 不承诺完整上游行为 |
| Request | blocks/request.py 的请求建模思想 | AI 辅助新实现；仅平面字段与显式单字段变异 |
| 测试/示例 | 本项目构造的 PING、ASCII、零字节与 0xff 输入 | 未复制外部报文、数据集或上游 fixtures |
| 后续移植 | primitives、blocks、sessions、connections 的选定子集 | 尚未实施，实施时补充文件、版本和修改范围 |

保留未来复制或翻译文件中的原版权和许可证声明，并注明修改。添加第三方算法、fixture 或依赖前单独核查其许可证；不将上游历史或 AI 生成内容冒充个人既有成果。维护者需要理解并复核 AI 辅助实现和测试。
