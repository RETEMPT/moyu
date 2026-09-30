# FlowMind（墨语）

FlowMind（墨语）是一款面向 HarmonyOS NEXT 的 Local-First 双链知识库与多端研读系统。它将 Markdown 笔记、PDF 原盘批注、矢量手写草稿、待办日程、全文检索与关系图谱凝聚在同一个本地优先的高效工作流中。

> 离线可用、数据私密，让每篇笔记都连成思考的星系。

---

## 项目状态

- **操作系统**：HarmonyOS NEXT；当前工程兼容 SDK `6.1.1(24)`，目标 SDK `26.0.0`
- **UI 框架**：ArkUI 声明式开发
- **编程语言**：ArkTS
- **支持设备**：Tablet 平板、Phone 手机（自适应布局）
- **数据策略**：Local-First 本地优先，笔记与工作区数据留存在端侧沙箱
- **当前产物**：`entry/build/default/outputs/default/entry-default-unsigned.hap`
- **开源仓库**：[RETEMPT/moyu](https://github.com/RETEMPT/moyu)

---

## 主要功能

### 知识库与笔记
- Markdown 笔记编辑和沉浸式阅读；
- `[[双链]]` 解析、反向链接直达与全文检索；
- 项目、资料库、回收站与移动归类；
- 目录大纲、上下文抽屉与快速全局搜索；
- 本地示例数据与工作区资产看板。

### 阅读与批注
- 图片 OCR 校对、本地整理与 AI Markdown 排版，支持预览编辑、原文保留和待办确认；
- 实际 PDF 文件导入、PDFKit 原页读取与真实页数，不支持的 Word 格式提示转换；
- PDF 多页阅读与 A4 物理页面排版；
- 原生批注、矢量手写墨水与二次贝塞尔光滑插值；
- 华为 MatePad 风格边读边写分屏与自由草稿白板；
- 纯文字随笔与 Markdown 双模阅读；
- 文档导入、导出与统一操作面板；
- AI 伴读分屏界面。

### 工作区与多端自适应
- 首页统计和视觉书架；
- 待办清单与日历视图；
- 力导向关系图谱工作区；
- 资料库与待处理内容；
- AI 墨客分级工作区（自动 / L1 伴读 / L2 学情 / L3 跨库）；
- 浅色、深色与跟随系统主题模式。

---

## 技术栈概览

| 层次 | 技术与规范 | 说明 |
| :--- | :--- | :--- |
| **开发语言** | ArkTS | 严格静态类型安全、零 eval 隐患 |
| **UI 框架** | ArkUI 声明式范式 | 响应式断点、组件化解耦 |
| **文本处理** | MarkdownParserService | 标题、标签、双链解析与分块 |
| **手写图形** | ArkUI Canvas 2D | 硬件级防误触、二次贝塞尔曲线矢量落盘 |
| **图谱仿真** | 自研力导向物理引擎 | 库仑斥力 + 弹性张力 + 动能阻尼衰减 |
| **数据持久化** | Preferences + 应用沙箱文件 | 毫秒级首屏快照 + 物理 `.md` / `.json` 文件原子读写 |
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

# 一键编译并安装拉起到在线设备/模拟器
.\deploy_hap.bat
```

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
- **非破坏性退出拦截**：阅读器在退出时弹出三态确认弹层（保存并退出、放弃修改、取消），确保笔迹零丢失。

更详细的工程经验与渲染铁律，请参阅 [**`PROJECT_MEMORY.md`**](./PROJECT_MEMORY.md)。

---

## 相关文档

| 文档 | 说明 |
| :--- | :--- |
| [**`PROJECT_MEMORY.md`**](./PROJECT_MEMORY.md) | 项目全景记忆、GPU 渲染避坑三大铁律与稳定性约定 |
| [**`TECH_STACK.md`**](./TECH_STACK.md) | 技术栈全景、AI 智能体调度中枢与知识图谱架构白皮书 |
| [**`CONTRIBUTING.md`**](./CONTRIBUTING.md) | 开源贡献指南、代码规范与 Pull Request 流程 |
| [**工作流验收与后续改进**](./docs/WORKFLOW_REVIEW.md) | 本次改进、自动回归结果、全功能设备验收清单与已知限制 |
| [**`SECURITY.md`**](./SECURITY.md) | 安全策略与漏洞提报通道 |
| [**`LICENSE`**](./LICENSE) | 开源许可证 |

---

## 许可证

本项目遵循 [MIT 许可证](./LICENSE)。
