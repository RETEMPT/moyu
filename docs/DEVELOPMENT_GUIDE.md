# 墨语开发指南

更新于 2026-11-21。源码基线为 1.2.1（1020100），面向 HarmonyOS 手机和平板。接手前阅读[产品范围](../PRODUCT_SCOPE.md)、[代码规范](CODE_STANDARDS.md)和[架构](ARCHITECTURE.md)。

## 环境与可复现构建

工程使用ArkTS／ArkUI、Hvigor、HarmonyOS RDB。`oh-package.json5`为modelVersion 26.0.0，目标SDK 26.0.0，兼容6.1.1（API 24）；这些是当前工程配置，不自动升级。

使用匹配 SDK 的 DevEco Studio，在本机配置 `DEVECO_STUDIO_HOME`，由工程依赖锁定文件恢复依赖。平台无关回归使用 Node 22 系列或兼容运行时；SQLite 测试还需要含 sqlite3 的 Python，按测试夹具支持配置 `PYTHON`。当前测试复用 DevEco 的 TypeScript；无 IDE 的 CI 使用 workflow 中锁定的测试编译器，不能将其当作 ArkTS SDK。

```powershell
# 无设备操作：构建 release APP 和 HAP
.\build_hap.bat -BuildMode release -AppPackage -Clean

# 源码、策略、数据仓储和公开文档回归
node tools/verify-project.mjs --typescript "<DevEco 中的 typescript.js 绝对路径>"

# 只有本轮成功构建后，再检查当前 SDK 生成的事件接线
node tools/verify-project.mjs --compiled --typescript "<同一 SDK 的 typescript.js 绝对路径>"
```

命令中的路径是需替换的占位符。默认检测可用时可省略 `--typescript`。构建产物为 `build/outputs/default/apps-default-unsigned.app` 与 `entry/build/default/outputs/default/entry-default-unsigned.hap`；`unsigned`表示没有发布签名，不能当作可直接安装的正式包。

成功构建后，`python tools/package-github-release.py` 核对 APP 的包名、版本、正式模式、设备范围、权限及资源，并生成仅含 APP、匹配 HAP 与包内校验文件的 ZIP。版本直接读取 `AppScope/app.json5`，旧版本产物拒绝打包；外部 `SHA256SUMS.txt` 用于校验 ZIP。产物与审计报告在被忽略的本地目录，不随源码提交。

构建与设备运行是独立步骤，不把自动编译当作真实设备交互验证。

StudyDemo 由 `deploy_hap.bat -StudyDemo` 构建并安装。脚本会在安装前验证所选 HAP 的网络权限。联调需启动同一源码版本的电脑网关，配对步骤见[模拟器使用说明](../cloud/ai/README.md)。

## 工程地图

| 目录／文件 | 责任 |
| --- | --- |
| `AppScope/`、`entry/src/main/module.json5` | 应用身份、版本、设备、权限和入口 |
| `entry/src/main/ets/pages/Index.ets` | 导航、全局工作空间状态、端口与用例装配 |
| `entry/src/main/ets/views/` | ArkUI 展示、输入、工具栏、阅读工作台 |
| `entry/src/main/ets/services/` | 存储、导入、保存、识别、规则、分享与系统适配 |
| `entry/src/main/ets/common/` | 共享类型、主题、常量、无上层依赖工具 |
| `entry/src/main/resources/` | 字符串、图标、离线 PDF 引擎及其许可证 |
| `tools/` | 自动回归、构建、生成物与公开文档检查 |
| `release/` | 工程发布配置与生成物；操作性材料另在本地维护 |
| `docs/` | 产品、商业、创新、架构、开发与用户说明，入口为README |
| `cloud/ai/` | 电脑端 CLI、云模型适配、MCP 工具、独立 SQLite 与测试 |
| `archive/` | 历史暂停功能，禁止编译、导入和计入当前能力 |
| 后续云服务 | 托管AI网关、任务与用量账本目前只有设计，没有服务端实现 |
| `tmp/`、`release/reports/`、`release/evidence/` | 本地生成结果和真实证据，不公开提交 |

## 关键用例如何走通

**导入**。系统选择器返回用户授权的 URI。PDF 按文件描述符顺序读取，边复制边计算 SHA-256，校验字节数并同步后将临时文件改名为本机原件。读取页数成功后保存正文和资料索引，打开阅读器时再渲染页面。PDF Kit 不可用、无法解析或读取超时时，使用离线 PDF.js。最多选 20 份，逐份处理，单份失败时清理该次创建的文件。普通导入、重新关联和旧 URI 迁移共用 PDF 复制流程。 [华为文件选择指南](https://developer.huawei.com/consumer/en/doc/HarmonyOS-Guides/select-user-file/)

**编辑／批注**：工作台发出有类型的提交 → `ReaderCommitService` 读取最新资料 → `ReaderCommitPolicy` 按区域合并自身字段 → 正文／元数据保存 → 成功发布。退出等候在途保存；失败保留脏状态。正文文件与 RDB 不是联合事务，跨文件断电恢复仍需补齐。

**资料与项目回收**：`WorkspaceLifecycle` 生成计划 → 同一 RDB 事务保存资料、项目及两类回收记录 → 发布新状态。彻底删除先写 pending deletion 记录，再幂等清理文件；失败下次重试，不删除仍有引用的附件。

**OCR 与整理**。选择单份文件后按格式提取文字。扫描页和图片使用系统 OCR，结果在本机整理为 Markdown，供编辑、预览及保存。格式支持和提取边界见[排版规则](LOCAL_TEXT_LAYOUT.md)。

**备份与分享**。资料库批量选择和备份页共享资料包生成逻辑。系统分享接收通过 `EntryAbility.onCreate` 或 `onNewWant` 处理 `sendData`，仅打开单份 `.flowmind.json` 文件。临时授权有效期间分块读取并关闭文件，TaskPool 校验成功后将资料包交给接收预览。文件选择器使用同一个读取与校验流程。用户确认后，恢复服务逐份创建本机副本。资料包上限为 32 MB，单附件上限为 16 MB，范围包括选中的资料和题卡。设备发现由系统分享面板提供。[华为接收分享指南](https://developer.huawei.com/consumer/en/doc/harmonyos-guides/share-interface-description/)

## 数据与迁移

数据库 schema=2：资料／项目／回收站使用事务快照分片；待办、日期备忘、题卡与草稿使用同库领域表。旧 Preferences 经校验只读迁移并保留，不静默回退到旧副本。缺分片、目录损坏或未来 schema 拒绝写入，不能清空库来让新版本启动。

正文由 `AtomicTextFile` 临时写入、同步、关闭后替换；保存输入在异步前捕获。扩展资料字段时同步修改类型、快照复制、合并策略、持久化校验、备份白名单与恢复迁移。原件、批注和稿纸拥有不同字段；不能用整对象覆盖消除并发问题。

## 修改与验证顺序

1. 先看现有差异、调用方和失败路径，明确本轮负责的字段和系统资源。
2. 修改最小用例；业务规则留在纯策略，平台 API 留在服务适配。
3. 数据一致性、取消、迁移或新提交门槛需要对应行为回归；简单文案和可逆样式不增加镜像测试。
4. 运行相应专项，再运行统一检查；应用源码变化后执行 release 构建及编译事件检查。只改文档或发布脚本时，不复用旧编译产物宣称本轮 SDK 构建成功。
5. 记录真实命令、运行日期、结果、包摘要、未验收项；截图和设备反馈绑定同一候选。

`tmp/verification-latest/results.json`是最近一次本机回归结果，不能长期把历史通过数当作当前状态。默认入口检查公开文档链接与发布边界，CI克隆不依赖私有材料。`--local-docs`只供持有完整本地记录的维护环境使用，不是公开贡献者的必需步骤。

## 常见故障

| 现象 | 处理 |
| --- | --- |
| TypeScript unavailable | 设置 DevEco 路径或显式 `--typescript`，不安装任意版本替代当前 SDK |
| SQLite 测试无法启动 | 按 `tools/fixtures/rdb-fixture.mjs` 检查 Python 路径及 sqlite3，不能跳过后记为通过 |
| 编译事件检查缺产物 | 先对同一源码完成 release 构建，再执行 `--compiled` |
| 回归通过、设备行为仍失败 | 区分纯策略、平台适配、SDK事件接线和真实设备，按实际失败路径复现 |
| 文档检查提到历史功能 | 当前用户文案仍受本地范围约束；规划文档允许讨论未来云 AI，不能解除应用源码边界 |
| PDF 慢、笔迹迟到或保存失败 | 保留原件与日志，定位后台任务／主线程绘制／任务代次／提交队列；先复现再修改，禁止清数据掩盖问题 |

## 关联质量与云服务设计

电脑端 CLI 需要 Python 3.10+ 与 sqlite3，MCP 扩展另有可选依赖。专项检查 `node tools/verify-ai.mjs` 已加入统一入口，CI 显式准备 Python。测试使用临时数据库和模拟模型。CI 失败时可下载 `verification-logs` 查看各项报告。工作区数据及运行方式见[云模型工具说明](../cloud/ai/README.md)。

本地学习增强位于 `services/study/LearningProgressPolicy.ets` 和 `views/study/StudySheet.ets`，使用显式时钟与已提交资料／题卡，不新增库表。代码修改后仍需 release 编译、工作流与编译后接线检查；后者仅验证 SDK 生成事件，不替代实际手机和平板的字号、键盘、布局和触控验收。云业务暂不开放，不预埋自动启用开关。

离线学习结果由复习页打开。修改 `LearningResultPolicy` 或 Python `exchange.py` 时，同步共享样本并运行两端回归。使用已配置的 DevEco 环境执行 `hvigorw assembleHap --no-daemon --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug` 可验证测试目标的 ArkTS 编译。结果交换和设备验收见[接入契约](LEARNING_INTEGRATION.md)。

保存与迁移修改应记录版本、真实测试和未覆盖边界，不复用旧结果。托管云AI按[技术方案](CLOUD_AI_DESIGN.md)组织网关、任务、引用验证和用量账本，面向的学习场景见[服务方向](CLOUD_AI_BUSINESS.md)。新增网络与云处理时同步产品范围、权限、隐私与凭据管理，让实现、用户说明和数据边界保持一致。
