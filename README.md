# FlowMind（墨语）

FlowMind（墨语）是一款面向高校学生的 HarmonyOS 本地课程研读与复习应用。将讲义、截图和 Markdown 笔记整理到课程中，核对来源，再通过题卡自测与反馈安排复习；同时提供 PDF 笔迹、待办和双链图谱。

> 默认离线，无需帐号、API Key 或团队云服务。需要生成式问答时可在设置中授权自配 API；云服务、云 AI 和云备份标记未开放，本地文件备份可用。

---

## 项目状态

- **操作系统**：HarmonyOS NEXT；当前工程兼容 SDK `6.1.1(24)`，目标 SDK `26.0.0`
- **UI 框架**：ArkUI 声明式开发
- **编程语言**：ArkTS
- **支持设备**：Tablet 平板、Phone 手机（自适应布局）
- **数据策略**：Local-First 本地优先，笔记与工作区数据留存在端侧沙箱
- **当前产物**：`entry/build/default/outputs/default/entry-default-unsigned.hap`
- **GitHub 发行**：[v1.0.3](https://github.com/RETEMPT/moyu/releases/tag/v1.0.3)，源码与未签名开发包，详见 [发行说明](docs/RELEASE_1.0.3.md)
- **本轮整改**：离线助手与可选 API、独立设置页、统一封面/居中菜单、只读阅读与工具标签、白板平移、PDF 持久导入、农历及节假日。227 项工作流与 11 项发布规则检查、干净 release APP 构建通过；正式签名与真机验收待补齐。详见 [整改方案](docs/REVIEW_FIXES_2026-10-08.md)
- **上架准备材料**：[提交资料与验收](release/README.md)，提供同源隐私页面、审核路径和严格发布检查
- **开源仓库**：[RETEMPT/moyu](https://github.com/RETEMPT/moyu)

---

## 主要功能

### 知识库与笔记
- Markdown 笔记编辑和沉浸式阅读；
- 应用内笔记封面：四款离线风格、相册图片、更换／移除，阅读页与资料列表同步；
- `[[双链]]` 解析、反向链接直达与全文检索；
- 项目、资料库、回收站与移动归类；
- 目录大纲、上下文抽屉与快速全局搜索；
- 首次启动为空，主动选择模板创建日记、会议记录等；工作区资产看板统计实际资料。

### 阅读与批注
- 图片 OCR 校对与本地整理，支持预览编辑、原文保留和待办确认；
- 实际 PDF 文件导入、PDFKit 原页读取与真实页数，不支持的 Word 格式提示转换；
- PDF 多页阅读与 A4 物理页面排版；
- 选择 PDF 页范围提取文字，每批最多 30 页；扫描 OCR 可选，逐页校对后进入搜索与 AI 检索，来源可回到真实页码；
- 笔与触控分流、压力与历史触点采样、增量曲线绘制、双指缩放、撤销/重做；接入笔身双击与轻捏，硬件表现需真机验收；
- 华为 MatePad 风格边读边写分屏与自由草稿白板；
- 纯文字随笔与 Markdown 双模阅读；
- 文档导入、导出与统一操作面板；
- 本地助手伴读分屏，可查询当前资料的原文与任务。

### 课程自测与资料备份
- 首页按现有分类汇总课程资料、到期题卡和关联待办，进入自测与复习；
- 离线创建问题、答案和原文；先回忆再看答案，用“不会／模糊／掌握”安排下次日期，保留总复习次数与遗忘记录；
- 授权自配模型后可生成 1～6 道题卡预览，引用须匹配实际原文，再由用户核对并保存；
- 学习资料备份包含笔记、原 PDF、封面、笔迹、已校对页面和题卡；恢复创建副本，支持中断重试，重连唯一内部双链；
- 备份为明文、单个附件上限 16 MB、总文件上限 32 MB，可按课程分批；不含待办、日期备忘、回收站、对话与模型密钥；
- 设置按工作空间、连接、安全与帮助分组，支持关键词检索和独立详情页；“备份与传递”管理数据，“使用指引”可手动导入测试 PDF。云服务与云备份未开放。

### 工作区与多端自适应
- [整体体验方案](docs/UX_PLAN_2026-10-09.md)：页面分区、原生详情导航、可搜索的设置与离线整理流程；
- [阅读与批注链路检查](docs/READER_CHAIN_REVIEW_2026-10-09.md)：AI 输入区菜单、PDF 原件恢复、返回只读、白板与稿纸及真机复测步骤；
- 墨紫、黑白、浅蓝、蓝白四套主题，配色与系统/浅色/深色独立选择；
- 首页统计和视觉书架；
- 待办日历显示农历、传统节日和已核对的 2026 年法定休息/调班；其他年份不猜测调休；
- 力导向关系图谱工作区；
- 资料库与待处理内容；
- 墨客默认离线：中文原文检索、要点摘录、任务候选与资料概览，附原文行号/PDF 页码，不自动写入；
- 多行提问、横向引用标签、快捷场景先填入再发送；应用内“使用指引”覆盖新建、笔控、助手与备份；
- 设置可选择本地或自配 API；保留 L1/L2/L3 研读、AI 排版、题卡建议与按需展开的高级参数；
- 自配服务由用户确认发送授权，密钥使用系统密钥库保存；超时或停止会关闭请求，写操作逐次确认并等待保存；
- 默认本地模式不请求模型服务；云 AI 不可激活，只有用户配置并授权的 API 才能发送资料；
- 浅色、深色与跟随系统主题模式。
- 紫墨应用图标、60 个 SVG 工具资源与统一纸张文档封面；首页和编辑器图标配短标签、提示及无障碍名称，菜单居中显示。
- 文档默认只读；下滑收缩工具栏，空白点击展开，输入或批注期间不收缩；未修改或已保存时直接退出。
- 本地和模型回答共用标题、列表、表格、引用、代码/公式块排版；保留公式原文，未接入完整 LaTeX 排版引擎。
- ArkUI 原生文档菜单、Share Kit 文字/原 PDF 分享、Ctrl+F 搜索；手写笔记可从首页直接新建。
- 可持久化的“减少动态效果”，主要页面与弹层统一使用短时缓动。

本次 AI 布局与接入边界见 [AI 界面说明](docs/AI_INTERFACE.md)。本轮设计依据、能力边界和验证记录见 [设计调研与实现](docs/DESIGN_REVIEW.md) 与 [完整功能验收清单](docs/WORKFLOW_REVIEW.md)。参赛重点见 [校园价值评估与试用方案](docs/CONTEST_VALUE_REVIEW.md)，上架目标见 [发布准备](docs/APP_MARKET_RELEASE.md)。学生效率、留存与收入数据尚未测得。

---

## 技术栈概览

| 层次 | 技术与规范 | 说明 |
| :--- | :--- | :--- |
| **开发语言** | ArkTS | 静态类型检查与分层服务 |
| **UI 框架** | ArkUI 声明式范式 | 响应式断点、组件化解耦 |
| **文本处理** | MarkdownParserService | 标题、标签、双链解析与分块 |
| **手写图形** | ArkUI Canvas 2D | 输入工具区分与二次贝塞尔矢量笔迹；实际防误触需设备验证 |
| **图谱仿真** | 自研力导向物理引擎 | 库仑斥力 + 弹性张力 + 动能阻尼衰减 |
| **数据持久化** | Preferences + 应用沙箱文件 | 快照与正文分步骤保存，等待完成并处理失败；不宣称跨文件原子事务 |
| **构建系统** | DevEco Studio、Hvigor | 声明式构建流水线、HAP 打包 |
| **设备调试** | hdc 命令行工具 | 模拟器与真机自动化部署 |

更详细的技术栈全景、AI Agent 调度中枢与底层架构解析，请参阅专门文档：[**`TECH_STACK.md`**](./TECH_STACK.md)。

---

## 目录结构

```text
├── AppScope/                  应用级配置和全端图标资源
├── design/                    图标 SVG 母版与设计资产
├── tools/                     图标与资源生成工具
├── build-profile.json5        SDK、产品和构建模式配置
├── hvigorfile.ts              Hvigor 工程入口
├── build_hap.bat              一键编译打包批处理脚本
├── deploy_hap.bat             一键编译并部署到设备脚本
├── entry/
│   ├── build-profile.json5    模块编译配置
│   └── src/main/
│       ├── ets/
│       │   ├── common/        常量、主题、Token、类型与空白模板
│       │   ├── services/      存储、搜索、文档与 AI 智能体服务
│       │   ├── views/         工作台、阅读器、布局外壳与模态弹层
│       │   ├── entryability/  EntryAbility
│       │   └── pages/         Index 顶层状态管理与路由装配
│       └── resources/         字符串、颜色、图标与页面配置
├── PROJECT_MEMORY.md          项目全景记忆、GPU 渲染避坑铁律与交互稳定性约定
├── TECH_STACK.md              技术栈全景与核心架构白皮书
└── CONTRIBUTING.md            开源贡献指南与规范
```

---

## 开发与构建

### 1. 使用 DevEco Studio
1. 用 DevEco Studio 打开工程根目录；
2. 等待 SDK、依赖和索引同步完成；
3. 选择 `default` product 和 `debug` build mode；
4. 菜单栏选择 **Build** → **Build Hap(s)/APP(s)** → **Build Hap(s)**。

### 2. 使用命令行一键构建与部署
工程自带基于 DevEco Studio 环境的批处理脚本：

```powershell
# 仅执行编译打包
.\build_hap.bat

# 指定 DevEco 环境，或设置 DEVECO_STUDIO_HOME
.\build_hap.bat -StudioDir "<DevEco Studio 安装目录>"

# 发布模式 APP 打包（需要另外配置有效发布签名）
.\build_hap.bat -BuildMode release -AppPackage

# 一键编译并安装拉起到在线设备/模拟器
.\deploy_hap.bat

# 多设备时指定目标；已构建时可跳过编译
.\deploy_hap.bat -Target 127.0.0.1:5555 -SkipBuild
```

构建脚本校验环境并恢复进程内环境变量，不更改签名。APP 产物位于 `build/outputs/default/`；unsigned 包不是市场发布包。

部署脚本只选择 `Connected` 设备，确认连接后再安装；传输中断最多重试三次，并检查实际安装结果和应用前台状态，不仅依赖 hdc 退出码。可通过 `-StudioDir` 指定其他 DevEco 安装目录；存在不早于 unsigned 包的 signed 包时优先使用 signed 包。

若 DevEco 提示 `FileTransfer Failed`，先确认模拟器已完成启动、`hdc list targets -v` 中目标为 `Connected`。构建成功不代表连接稳定；可以运行上述 `-SkipBuild` 命令重新部署，保留应用数据。真机需要满足设备签名要求，脚本不会自动卸载应用或修改签名配置。

构建产物位于：
```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

---

## 调试与 hdc 指令

确保设备或模拟器已连接并在终端中可见：

```powershell
# 查看在线设备/模拟器
hdc list targets

# 手动安装 HAP 包
hdc -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-unsigned.hap

# 启动应用 EntryAbility
hdc -t 127.0.0.1:5555 shell aa start -a EntryAbility -b com.retempt.flowmind -m entry
```

若 `hdc` 出现卡顿或未响应，可执行以下命令恢复服务：

```powershell
hdc kill
hdc start
hdc list targets
```

---

## 交互稳定性约定

项目针对页面切换和弹层合成做了深度优化：

- **单层居中遮罩规范**：全屏半透明遮罩与居中卡片采用单层垂直居中布局，阻断冒泡，避免多层视口在 GPU Tessellator 阶段产生折光与拉丝撕裂；
- **单调有界缓动曲线**：透明度过渡采用严格单调无超调的 `Curve.EaseInOut`（180ms ~ 250ms），确保 $\alpha \in [0.0, 1.0]$，杜绝欠阻尼物理弹簧造成的颜色反向混合；
- **静态布局均分防抖**：动态弹窗功能列表采用静态双层 `Row` + `.layoutWeight(1)` 均分，避免虚拟化容器进场时的异步排版抖动；
- **触控与笔控分离**：通过 `SourceTool` 识别手写笔输入与手掌手指，仅在合法双指手势时放行缩放与漫游；
- **退出确认与失败处理**：阅读器提供保存并退出、放弃修改、取消；保存等待完成，失败保持阅读器，异常断电仍需专项恢复验证。

更详细的工程经验与渲染铁律，请参阅 [**`PROJECT_MEMORY.md`**](./PROJECT_MEMORY.md)。

---

## 相关文档

| 文档 | 说明 |
| :--- | :--- |
| [使用指引](docs/USER_GUIDE.md) | 新建、星闪手写笔、离线助手与备份 |
| [审核整改方案](docs/REVIEW_FIXES_2026-10-08.md) | 四项审核反馈、实现、验证范围与真机复测 |
| [**`PROJECT_MEMORY.md`**](./PROJECT_MEMORY.md) | 项目全景记忆、GPU 渲染避坑三大铁律与稳定性约定 |
| [**`TECH_STACK.md`**](./TECH_STACK.md) | 技术栈全景、AI 智能体调度中枢与知识图谱架构白皮书 |
| [**`CONTRIBUTING.md`**](./CONTRIBUTING.md) | 开源贡献指南、代码规范与 Pull Request 流程 |
| [**工作流验收与后续改进**](./docs/WORKFLOW_REVIEW.md) | 本次改进、自动回归结果、全功能设备验收清单与已知限制 |
| [**校园价值评估**](./docs/CONTEST_VALUE_REVIEW.md) | 按评审权重组织价值证据、学生试用与商业路径 |
| [**应用市场发布准备**](./docs/APP_MARKET_RELEASE.md) | 发布范围、签名、真机与审核材料的放行条件 |
| [**多设备互通与功能取舍**](./docs/MULTIDEVICE_PLAN.md) | 附近传递候选实现、下一步同步设计、校园价值与统一发行策略 |
| [**分层架构与数据保存**](./docs/ARCHITECTURE.md) | 用例、系统适配与存储边界，渐进迁移规则与未解决项 |
| [**隐私与数据说明**](./docs/PRIVACY.md) | 数据流与备份范围；正式发布身份尚待核对 |
| [**`SECURITY.md`**](./SECURITY.md) | 安全策略与漏洞提报通道 |
| [**`LICENSE`**](./LICENSE) | 开源许可证 |

---

## 许可证

本项目遵循 [MIT 许可证](./LICENSE)。
