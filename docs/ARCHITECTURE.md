# 分层架构与数据保存

更新：2026-10-07。当前采用渐进迁移，保留现有服务路径和 JSON 格式；不把一次目录改名当作完成全部架构重构。

```mermaid
flowchart TD
  Page["Index：导航、状态与装配"] --> View["views：布局、输入与状态显示"]
  Page --> Reader["ReaderCommitService：自动/退出保存用例"]
  View --> Import["StudyImportService：共用导入用例"]
  View --> Nearby["HarmonyNearbyService：系统互通适配"]
  Import --> Restore["StudyRestoreService：单资料提交与重试"]
  Import --> Backup["StudyBackupService：附件读取/物化"]
  Nearby --> Protocol["NearbyTransferPolicy：分片、期限与完整性"]
  Protocol --> Policy["StudyBackupPolicy / ReviewPolicy：业务校验"]
  Restore --> Ports["存储与发布端口，由 Index 提供"]
  Reader --> Ports
  Ports --> Storage["Note / Todo / Review / Chat Storage"]
  Storage --> Snapshot["SnapshotStore + SerialTaskQueue"]
  Storage --> Files["AtomicTextFile：正文替换"]
```

## 本轮下沉的职责

| 边界 | 负责 | 不负责 |
| --- | --- | --- |
| 视图 | 用户选择、数量预览、忙碌/失败状态、关闭 | 附件校验、整批恢复规则、密钥转移 |
| ReaderCommitService | 排队自动与退出提交、各编辑区只修改自己负责的字段，保留分类/封面/索引等最新数据，存储成功后发布 | ArkUI、设备发现、全文搜索 |
| StudyImportService | 文件/附近来源共用校验、稳定恢复 ID、题卡映射、进度与局部失败说明 | 图标、布局、系统文件选择器实现 |
| NearbyTransferPolicy | 不可变传递清单、分片/Unicode、摘要、期限与支持版本 | 系统权限和组网、直接修改本地资料 |
| HarmonyNearbyService | 用户授权、可信设备、加密临时 KV、单目标同步、结果/超时/资源清理 | 课程内容政策、自动覆盖正文、云服务 |
| SnapshotStore | 排队 put/flush，捕获 JSON，损坏/读失败阻止覆盖，失败恢复缓存 | 跨文件事务、凭证加密、云一致性 |
| AtomicTextFile | 临时文件完整写入、fsync、关闭后同目录 rename，失败保留目标 | 快照与正文的联合事务、外部 URI 导出 |

队列失败后可以继续处理后续任务。对话的读—修改—写也排成一个操作，防止并发保存两段会话只留下其中一段。正文写入队列由进程内各实例共享，避免使用同一临时路径的竞态。

快照保持原 Preferences 键和值格式，不需要升级时清库。合法空资料库保持空，不重新填示例。格式异常与读取失败会保留原数据并阻止继续覆盖；目前没有自动修复损坏快照的界面，恢复前先保留设备数据。原始可读正文可通过已有文件能力找回，但不能据此声称所有元数据可自动重建。

## 仍然存在的边界

- Index 仍持有新建、分类、收藏、回收站和部分 AI 操作，尚未完成所有用例拆分；下一步按实际操作迁移到统一工作区仓储，覆盖所有修改入口的并发控制。
- 正文与 Preferences 是分步骤持久化。写入临时文件可以保护旧正文，缓存回滚可以避免后续 flush 带入失败值，但二者并非联合事务；断电后的最终状态仍需真机核对。后续评估事务数据库加提交日志和恢复流程。
- 阅读器用例队列覆盖自动与退出保存；跨其他工作区操作的共同事务仍需统一仓储。不要据此宣称全应用并发无丢失。
- 备份恢复按每份资料提交；题卡失败保留有效资料，按稳定 ID 重试补齐。整批不是原子事务。附近传递只返回经校验的备份，确认导入后才调用同一恢复流程。
- 模型元数据留在私有 Preferences，密钥另由 HUKS/AES-GCM 保护；候选已关闭整包系统备份，实际迁移和系统密钥行为仍需真机验证。临时传递库的加密不等于所有应用数据均加密。

## 后续迁移规则

新增业务用例通过明确端口读取、持久化和发布状态，不直接引用 ArkUI 页面；纯策略放在领域服务，系统 API 只放适配服务；common 只保留类型、常量与无平台工具。继续沿用现有 `pages → views/services → common` 依赖方向，服务不能反向导入视图。

先迁移资料修改/删除用例并引入统一仓储，再增加逐实体同步版本和附件目录。每次迁移保持现有可观察行为，验证失败路径与旧数据读取；不同时重写导航、模型协议和存储格式。页面装配仅保留事件到用例、状态发布与导航，逐步减少 Index 的业务代码。

质量证据分开记录：纯规则/平台替身测试、ArkTS/资源/应用包构建、真实手机与 Pad 系统功能和性能。前两项通过不能替代最后一项。候选架构与范围见 [多设备计划](MULTIDEVICE_PLAN.md)。

## 发布与安全边界

`ModelConfigService` 串行管理模型元数据和激活状态，`HuksCredentialStore` 管理 AES-GCM 密文与设备系统密钥。密文先保存，再提交引用；旧格式迁移失败不把新密钥落为明文。配置损坏不默认覆盖，密钥无法读取时提供重新填写/移除入口。删除引用后的旧密文清理是尽力操作，跨存储不声称分布式事务。

`RemoteAiPolicy` 是聊天、连接测试和向量化入口共用的发送策略，授权绑定版本、端点与协议。`SseHttpClient` 为三协议复用 UTF-8 流式解码、HTTP 状态确认、单次终止与资源释放；OpenAI 的工具/思考增量仍由其专用解析器处理。服务测试覆盖策略和故障，真实 NetworkKit/HUKS 仍需设备测试。

发布资料在 `release/app-market.json` 与 `release/privacy-sections.json`，生成器将同一份说明写入应用、在线 HTML 与文档。`app-market-policy` 不依赖平台，负责包/证据规则；预检器装配 Git、APP 元数据与 SDK 签名检查。生产模块只使用 ArkTS 和系统能力，移除了无业务调用的原生模板。候选统一 phone/tablet，保留响应式大屏布局。

`AiModelCatalog` 是无平台、无网络的模型目录与新草稿工厂；`CloudModelCatalog` 只显示和回传预览选择，不能激活模型或发送资料。`ModelSettingsSheet` 装配目录、自配档案和授权流程，输出/工具/档案管理在高级区按需展开。`ChatSessionService.replaceMessages` 在同一队列内更新指定会话，捕获消息快照并保留标题/置顶，已删除会话不能被撤回消息操作复活。界面设计与模型来源见 [AI 界面说明](AI_INTERFACE.md)。
