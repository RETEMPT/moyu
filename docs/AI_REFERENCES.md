# AI 学习能力参考记录

本轮在既有[云AI设计](CLOUD_AI_DESIGN.md)基础上建设[独立学习原型](../cloud/ai/README.md)，不恢复历史客户端AI代码，不接入主软件。以下记录来自 2026-10-22 查阅的上游公开 README 与官方协议；上游功能和许可证应在实际复用时按固定版本重新核验，热度与榜单不作为工程依据。

| 项目与官方来源 | 研究思路 | 本轮落地 | 后续评估 |
| --- | --- | --- | --- |
| [HKUDS/DeepTutor](https://github.com/HKUDS/DeepTutor)（Apache-2.0） | 个性化学习、可管理记忆与围绕资料的辅导 | 用户自述知识点、学习状态、错题备注；可查看、修改、删除及选择发送 | 更细的学习事件与复习建议；主动提醒另行设计 |
| [shareAI-lab/learn-claude-code](https://github.com/shareAI-lab/learn-claude-code)（MIT） | 逐步构造智能体运行环境，理解工具、上下文与执行循环 | 明确的准备、发送、核验、采纳状态机，独立模型适配与有界输入输出 | 有限任务编排与更严格的模型能力协商 |
| [lfnovo/open-notebook](https://github.com/lfnovo/open-notebook)（MIT） | 课题资料组织、基于资料的对话、转换与模型选择 | 笔记本隔离、词面检索、摘要／问答／报告／题卡草稿、文件导出 | 语义检索、更多协议、可编辑音频脚本及语音合成 |
| [KnifeLemon/Filee](https://github.com/KnifeLemon/Filee)（MIT） | 本地格式处理、批量操作和保留原件 | 显式格式白名单、批量导入、逐项报告、导出防覆盖 | 独立转换适配器，按格式验证保真和可提取范围 |

这是对公开项目的思路研究与独立实现。电脑端支持 UTF-8 TXT／Markdown，云模型通过 Chat Completions 协议调用。

主程序在 1.1.1 中借鉴学习进度和复习闭环，在现有本地复习页增加按资料的学习概况、最近弱项筛选与到期优先、题卡内容编辑。它从已有阅读和自测记录派生，不引入上述项目代码或云业务；手机和平板实际交互仍待验证。

云模型适配参考 [DeepSeek JSON Output](https://api-docs.deepseek.com/guides/json_mode/)、[百炼 Chat Completions](https://help.aliyun.com/en/model-studio/compatibility-of-openai-with-dashscope) 与 [OpenAI Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)。Agent 工具通过 [MCP Python SDK](https://github.com/modelcontextprotocol/python-sdk/blob/main/docs/migration.md) 的 stdio 接口运行。

## 文档阅读与伴读

[DeepSeek Harness 文档阅读插件](https://github.com/reg4916/dsh-doc-reader)按页、幻灯片和工作表提取文字。[NotebookLM 文档与引文说明](https://blog.google/innovation-and-ai/products/notebooklm-goes-global-support-for-websites-slides-fact-check/)说明了从答案返回支撑段落的交互。墨语在本地为 DOCX／PPTX 生成可读文字版，并使用明确的页码或行号记录发送片段和引文出处。选择文件使用[鸿蒙文件选择器](https://developer.huawei.com/consumer/en/doc/HarmonyOS-Guides/select-user-file/)，Office 正文解压使用[鸿蒙 zlib](https://developer.huawei.com/consumer/en/doc/harmonyos-references/js-apis-zlib/)。

## 技术实现依据与取舍

后续交换格式参考 [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) 的 JSON 编码与跨语言处理约束，明确字节限制、UTF-16 字段长度和 Unicode 校验。已落地结果契约及两端共享样本见[接入准备](LEARNING_INTEGRATION.md)，并未引入在线服务。

以下为 2026-10-22 继续核对的官方技术资料，区分已经实现的能力与尚待评估的方向。

| 官方资料 | 工程判断 | 当前对应 |
| --- | --- | --- |
| [SQLite Online Backup API](https://sqlite.org/backup.html) | 活跃数据库需要一致快照，不能仅复制主文件并忽略日志 | 独立原型新增 `workspace backup`，通过备份 API 生成新目录，检查完整性与外键，拒绝覆盖 |
| [Python sqlite3.Connection.backup](https://docs.python.org/3/library/sqlite3.html#sqlite3.Connection.backup) | 标准库提供分页备份与进度回调，无需新增依赖 | 分页复制、复制阶段等待上限、失败清理；真实 SQLite 验证 WAL 内容、独立副本和 CLI 路径 |
| [Anki：反复遗忘的题卡](https://docs.ankiweb.net/manual/leeches) | 反复答错可能源于信息过多或理解不足，应支持改写与拆分知识点 | 现有本地题卡编辑保留复习安排；尚未引入累计错误阈值、自动停用或 Anki 调度算法 |

备份快照包含运行中任务时拒绝完成，避免把未结束请求误当成可恢复任务；它不构成跨进程任务锁。切换副本时停止旧工作区操作，并重新准备待发送任务。备份和恢复步骤、明文数据范围见[原型使用说明](../cloud/ai/README.md#工作区备份与恢复)。

后续优先评估检索质量基准、按章节选择资料与原文定位，再考虑新的模型协议或格式适配；功能数量不能代替引用正确性、数据可恢复性和实际学习效果验证。

后续若真正复用上游代码，需先固定提交、核对许可证与传递依赖、保留版权和 NOTICE，并单独记录改动与验证；当前思路研究不能作为未来复制代码的授权清单。现有应用依赖见[依赖说明](DEPENDENCIES.md)。
