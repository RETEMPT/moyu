# FlowMind（墨语）

FlowMind（墨语）是一款面向高校学生的 HarmonyOS 本地课程研读与复习应用。将讲义、截图和 Markdown 笔记整理到课程中，核对来源，再通过题卡自测与反馈安排复习；同时提供 PDF 笔迹、待办和双链图谱。

> 本地功能离线可用；AI 为可选的用户自配服务，启用后会向所选服务发送相应资料。团队当前不运营云盘或 AI 服务。

---

## 项目状态

- **操作系统**：HarmonyOS NEXT；当前工程兼容 SDK `6.1.1(24)`，目标 SDK `26.0.0`
- **UI 框架**：ArkUI 声明式开发
- **编程语言**：ArkTS
- **支持设备**：Tablet 平板、Phone 手机（自适应布局）
- **数据策略**：Local-First 本地优先，笔记与工作区数据留存在端侧沙箱
- **当前产物**：`entry/build/default/outputs/default/entry-default-unsigned.hap`
- **发布状态**：开发评审中；release APP 打包通过，但未配置发布签名、未完成全量真机验收、未提交市场
- **开源仓库**：[RETEMPT/moyu](https://github.com/RETEMPT/moyu)

---

## 主要功能

### 知识库与笔记
- Markdown 笔记编辑和沉浸式阅读；
- 应用内笔记封面：四款离线风格、相册图片、更换／移除，阅读页与资料列表同步；
- `[[双链]]` 解析、反向链接直达与全文检索；
- 项目、资料库、回收站与移动归类；
- 目录大纲、上下文抽屉与快速全局搜索；
- 本地示例数据与工作区资产看板。

### 阅读与批注
- 图片 OCR 校对、本地整理与 AI Markdown 排版，支持预览编辑、原文保留和待办确认；
- 实际 PDF 文件导入、PDFKit 原页读取与真实页数，不支持的 Word 格式提示转换；
- PDF 多页阅读与 A4 物理页面排版；
- 选择 PDF 页范围提取文字，每批最多 30 页；扫描 OCR 可选，逐页校对后进入搜索与 AI 检索，来源可回到真实页码；
- 原生批注、矢量手写墨水与二次贝塞尔光滑插值；
- 华为 MatePad 风格边读边写分屏与自由草稿白板；
- 纯文字随笔与 Markdown 双模阅读；
- 文档导入、导出与统一操作面板；
- AI 伴读分屏界面。

### 课程自测与资料备份
- 首页按现有分类汇总课程资料、到期题卡和关联待办，进入自测与复习；
- 离线创建问题、答案和原文；先回忆再看答案，用“不会／模糊／掌握”安排下次日期，保留总复习次数与遗忘记录；
- 可选 AI 生成 1～6 道题卡预览，引用须匹配实际原文，再由用户核对答案并确认保存；
- 学习资料备份包含笔记、原 PDF、封面、笔迹、已校对页面和题卡；恢复创建副本，支持中断重试，重连唯一内部双链；
- 备份为明文、单个附件上限 16 MB、总文件上限 32 MB，可按课程分批；不含待办、日期备忘、回收站、对话与模型密钥；
- “外观与数据”提供备份及隐私说明；手动备份可自行存到系统选择器支持的位置，未实现自动云同步。

### 工作区与多端自适应
- 首页统计和视觉书架；
- 待办清单与日历视图；
- 力导向关系图谱工作区；
- 资料库与待处理内容；
- AI 墨客分级工作区（自动 / L1 伴读 / L2 学情 / L3 跨库）；
- 多模型档案、连接测试、输出参数、附加提示词和工具权限；未保存输入在档案切换时保留；
- 11 种笔记与待办工具、六类研读快捷场景，写操作逐次确认并等待保存结果；
- 默认本地关键词检索，可主动开启语义检索；远程调用的数据范围在配置页说明；
- 浅色、深色与跟随系统主题模式。
- 可持久化的“减少动态效果”，主要页面与弹层统一使用短时缓动。

本轮设计依据、能力边界和验证记录见 [设计调研与实现](docs/DESIGN_REVIEW.md) 与 [完整功能验收清单](docs/WORKFLOW_REVIEW.md)。参赛重点见 [校园价值评估与试用方案](docs/CONTEST_VALUE_REVIEW.md)，上架目标见 [发布准备](docs/APP_MARKET_RELEASE.md)。学生效率、留存与收入数据尚未测得。

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
│       │   ├── common/        常量、主题、Token、类型与示例数据
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
| [**`PROJECT_MEMORY.md`**](./PROJECT_MEMORY.md) | 项目全景记忆、GPU 渲染避坑三大铁律与稳定性约定 |
| [**`TECH_STACK.md`**](./TECH_STACK.md) | 技术栈全景、AI 智能体调度中枢与知识图谱架构白皮书 |
| [**`CONTRIBUTING.md`**](./CONTRIBUTING.md) | 开源贡献指南、代码规范与 Pull Request 流程 |
| [**工作流验收与后续改进**](./docs/WORKFLOW_REVIEW.md) | 本次改进、自动回归结果、全功能设备验收清单与已知限制 |
| [**校园价值评估**](./docs/CONTEST_VALUE_REVIEW.md) | 按评审权重组织价值证据、学生试用与商业路径 |
| [**应用市场发布准备**](./docs/APP_MARKET_RELEASE.md) | 发布范围、签名、真机与审核材料的放行条件 |
| [**隐私与数据说明**](./docs/PRIVACY.md) | 数据流与备份范围；正式发布身份尚待核对 |
| [**`SECURITY.md`**](./SECURITY.md) | 安全策略与漏洞提报通道 |
| [**`LICENSE`**](./LICENSE) | 开源许可证 |

---

## 许可证

本项目遵循 [MIT 许可证](./LICENSE)。
