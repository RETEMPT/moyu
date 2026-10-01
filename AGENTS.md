# AGENTS.md · 墨语 FlowMind AI 协作说明

> 本文件写给在本仓库工作的 **AI 编程代理**（Codex / Cursor / Qoder 等）。
> 人类贡献者请优先看 [CONTRIBUTING.md](CONTRIBUTING.md)；产品级 AI 功能规划见 [AI_AGENT_PLAN.md](AI_AGENT_PLAN.md)。

## 1. 项目概览

- **墨语 FlowMind**：面向学习的「第二大脑」笔记应用，HarmonyOS NEXT / ArkTS / Stage 模型。
- Bundle：`com.retempt.flowmind`，入口 Ability：`EntryAbility`，模块：`entry`。
- 本地优先：笔记、对话、模型配置均落 `preferences` + 沙箱文件，仅补全生成走模型 API。

## 2. 构建与运行

```bat
:: 仅编译 HAP
.\build_hap.bat

:: 编译并一键安装、启动到在线设备/模拟器
.\deploy_hap.bat
```

- 脚本内已硬编码本机 DevEco Studio 路径与 SDK；换机需同步修改 `build_hap.bat` / `deploy_hap.bat` 顶部的 `STUDIO_DIR`。
- `deploy_hap.bat` 依赖 `hdc`，运行前需先启动模拟器或连接真机（`hdc list targets` 能看到设备）。
- 代理无法在此环境编译 ArkTS：**任何 .ets 改动都必须由人在 DevEco 里 Build 一次**再合并。

## 3. 架构分层铁律（单向向下依赖）

`pages/` → `views/` → `services/` → `common/`

- `pages/Index.ets`：顶层页面状态与路由装配，全局状态持有者。
- `views/`：ArkUI 声明式组件，通过 `@Prop` / `@Link` / 回调通信。
- `services/`：持久化、检索、双链图谱、文档导入、模型服务。
- `common/`：类型、主题 Token（`DesignTokens.ets`）、常量、示例数据工厂。
- **禁止**：`views/` 直接 import 网络 kit 或 `preferences`；`services/ai/providers/*` 是唯一触碰 HTTP 的地方。
- 改公共类型、主题 Token、`Index.ets` 或跨层 API 前，先在 Issue/PR 里对齐接口。

## 4. 编码约定

- **命名/文案**：页面与组件用中文名（如「AI 墨客」）；三层智能体固定称谓 **L1 伴读 / L2 学情 / L3 跨库**。
- **图标**：优先简约文字符号（`▤ ◍ ⚙ ✦ ◆ ◇`），**避免彩色 emoji** 当交互图标。
- **主题**：颜色一律走 `palette()`（跟随 `@StorageProp('flowmindDarkMode')`），不要写死色值。
- **持久化**：`preferences` 前缀统一 `flowmind_`（如 `flowmind_notes` / `flowmind_chat` / `flowmind_model`）。
- **触控热区**：可点击元素热区不小于 `LayoutTokens.MIN_TOUCH_TARGET`（44vp）；视觉尺寸不变时用 `.responseRegion()` 扩命中区。
- **提交信息**：Conventional Commits（`feat/fix/docs/perf` + 可选 scope），中文描述可；一次提交只解决一类问题。

## 5. 响应式断点（mediaquery，看的是**窗口宽度**不是设备类型）

| 宽度 | 形态 | AppShell 行为 |
|---|---|---|
| ≥ 1200vp | 三栏 | 侧栏 + 正文 + 上下文面板常驻 |
| 840–1199vp | 双栏 | 上下文转浮层 |
| < 840vp | 单栏 | 侧栏与上下文均浮层（抽屉） |
| < 600vp | 手机紧凑态 | 收窄留白、抽屉改百分比宽 |

两个全局标志（均由 `AppShell.ets` 通过 `AppStorage.setOrCreate` 广播）：

- **`flowmindIsPhone`** = `width < 600vp`（`BREAKPOINT_PHONE`）——**真·手机**。**底部 Tab 导航只在此标志为真时出现。**
- **`flowmindIsCompact`** = `isSingleColumn()` = `width < 840vp`——**任意窄窗口**（含平板分屏、桌面窄窗、折叠屏外屏）。阅读器顶栏收纳等按此触发。

> 选型原则：只在真手机才该出现的强交互（底部导航）用 `flowmindIsPhone`；
> 「窄了就收纳/横滑」这类纯空间自适应用 `flowmindIsCompact`。

## 6. 本批改进说明 · 手机端 UI 增强（feature/phone-adaptation）

以下为在最新 `main` 基础上补充的手机端交互改进（原 P0/P1 清单移植而来）。
**已被 main 覆盖而主动跳过的**：首页窄屏单栏重排（main 用 `isPhone + GridRow` 已实现且更优，统计卡还带点击跳转）、MarkdownReader 导入注释修复（main 已有）、新建笔记/项目/批注弹窗宽度约束（main 已用 `width('88%') + maxWidth` 实现）。

| # | 界面 / 点按路径 | 改进内容 | 主要文件 |
|---|---|---|---|
| 1 | **全局·真手机(<600vp)** | 新增**底部 Tab 主导航**替代抽屉；键盘弹出时自动隐藏，避免遮挡 | `views/layout/BottomNavBar.ets`(新增)、`AppShell.ets`、`pages/Index.ets`、`common/constants/DesignTokens.ets` |
| 2 | **阅读器·顶栏** | 窄屏(<840vp)**顶栏收纳**：分屏/沉浸入口移入「更多」面板，标题区只留退出/标题/模式切换 | `views/reader/huawei/HuaweiDocWorkspace.ets` |
| 3 | **阅读器·悬浮笔盘** | 笔盘套**横向 Scroll**，窄屏可左右滑动触达全部工具/颜色/笔宽，不再被裁切 | 同上 |
| 4 | **阅读器·底部控制台** | 翻页/页码滑块/视图切换/跳转条整条套**横向 Scroll**，窄屏可滑动 | 同上 |
| 5 | **阅读器·退出** | 退出确认改**底部抽屉**；「清空批注」加**二次确认** | 同上 |
| 6 | **全局·多处小按钮** | 关键按钮**触控热区扩到 44vp**（`responseRegion`，零视觉变化） | `GlobalTopBar.ets`、`context/ContextDrawer.ets`、`reader/ReaderWorkspace.ets`、`settings/AppearanceSheet.ets`、`settings/ModelSettingsSheet.ets`、`layout/sheets/CreateNoteSheet.ets`、`layout/sheets/NewProjectSheet.ets`、`workspace/PendingWorkspace.ets`、`workspace/TrashWorkspace.ets` |
| 7 | **待办白板卡片** | 页内卡片宽度加 `maxWidth` 约束，窄屏不溢出（其余弹层 main 已处理） | `workspace/PendingWorkspace.ets` |

**验证要点（务必在 DevEco + 模拟器实机过一遍）**：

1. 手机模拟器（<600vp）：底部 Tab 出现、可切换首页/资料库/图谱/AI墨客/待办/回收站；键盘弹出时 Tab 隐藏。
2. 平板分屏 / 桌面窄窗口（600–840vp）：**不应**出现底部 Tab（仍用抽屉），但阅读器顶栏应收纳、笔盘/控制台可横滑。
3. 阅读器：进入批注模式笔盘可左右滑；退出弹底部抽屉；清空批注有二次确认。
4. 回归：把窗口拉宽到平板/桌面三栏，底部 Tab 消失、侧栏与上下文面板恢复常驻，阅读器顶栏恢复完整入口。
