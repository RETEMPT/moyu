# FlowMind（墨语）项目全景记忆与技术备忘录 (Project Memory)

> **对应 CodeGenie 记忆库**：[`e:/apps/.codegenie/MEMORY.md`](file:///e:/apps/.codegenie/MEMORY.md)  
> **文档维护状态**：最新同步于 2026-09-21  
> **面向对象**：架构师、DevEco CodeGenie、全栈开发团队

---

## 一、 项目全景与核心定位

* **项目全称**：FlowMind (墨语) —— 纯血鸿蒙 Local-First 端侧 AI 双链知识库与多端研读系统
* **开发环境**：HarmonyOS NEXT (API 11/12+), DevEco Studio, ArkTS, C++ (NAPI 原生加速)
* **核心业务形态**：
  1. **Markdown 沉浸式双链阅读与写作**：支持纯文本随笔、目录大纲、反向链接直达、LaTeX 数学公式。
  2. **原生试卷与 PDF 多页 A4 矢量批注工作台**：对标考研刷题、公考复习场景，支持多页 A4 原盘排版、矢量手写墨水、二次贝塞尔平滑与缩略图快速导航。
  3. **AI 伴读与边读边写分屏**：华为 MatePad 风格右侧可伸缩抽屉面板，支持小艺/端侧 AI 伴读与自由草稿白板。
* **数据主权与存储模型**：
  * 坚持 **Local-First** 纯本地优先架构；
  * 双轨持久化：`Preferences` 维护全量 JSON 状态快照（实现首屏秒开与秒切），沙箱 `filesDir/notes/` 落盘物理 `.md` / `.json` 文件；
  * 删除操作必须显式调用 `fileIo.unlink` 清除物理文件，确保零数据残留。

---

## 二、 工程目录与架构分层规范

应用严格遵守 **单向向下依赖** 准则：`pages/` → `views/` → `services/` → `common/`。严禁底层反向引用上层组件。

```text
e:/apps/
├── .codegenie/
│   ├── MEMORY.md                          # CodeGenie 专属工作记忆（FACT 与 TASK 结构化存储）
│   ├── agent.md                           # CodeGenie 项目指导与架构分层规范
│   └── README.md                          # 设计与实施文档索引
├── entry/src/main/ets/
│   ├── common/                            # 公共基础设施（零业务逻辑、零上层依赖）
│   │   ├── constants/DesignTokens.ets     # UI/UX Pro Max 规范 Token、Obsidian 极简中性调色板
│   │   ├── seed/SeedContent.ets           # 初始示例数据工厂
│   │   ├── theme/                         # ThemeMode、ThemeManager、ThemeHelper
│   │   ├── types/                         # NoteItem、CanvasStroke、PdfAnnotationTypes、TodoItem
│   │   └── utils/                         # TimeFormat、CalendarUtil、ForEachKeys
│   ├── services/                          # 纯逻辑与系统能力桥接服务（无 UI 状态）
│   │   ├── NoteStorageService.ets         # Preferences 快照 + 沙箱 .md 读写 + 导入导出
│   │   ├── TodoStorageService.ets         # 待办任务与随堂备忘持久化
│   │   ├── NoteSearchService.ets          # 全文检索与双链图谱
│   │   ├── MarkdownParserService.ets      # 纯内存标题/标签/双链解析
│   │   └── WorkspaceBuilder.ets           # 纯函数 buildSpaces()：计算侧栏文件夹树
│   ├── views/                             # 纯 UI 组件库（通过 @Prop 与回调通信）
│   │   ├── layout/                        # AppShell（三栏外壳）、Sidebar（文件资源管理器）、GlobalTopBar
│   │   │   └── sheets/                    # 侧栏弹层族（ProjectMenuSheet、NewProjectSheet 等）
│   │   ├── workspace/                     # HomeWorkspace、TodoWorkspace、TrashWorkspace 等
│   │   └── reader/                        # 研读工作台
│   │       ├── huawei/                    # HuaweiDocWorkspace 全屏阅读器、HuaweiAiSplitPanel 伴读分屏
│   │       └── pdf/                       # PdfAnnotatorView 多页协调器、PdfPageCanvas A4 矢量墨水层
│   └── pages/
│       └── Index.ets                      # 顶层唯一 @Entry 状态持有者与路由装配器
```

---

## 三、 Obsidian × Notion 极简商务设计规范

1. **绝对剔除 Emoji 玩具化图标**：
   * 严禁在界面工具栏、底栏、顶栏及弹窗中使用彩色 Emoji。
   * 全线采用 Obsidian 风格的高精度单色几何拓扑字符与排版符号：
     * `←`（返回）、`▤`（大纲）、`✎`（批注/画笔）、`⊡`（双链）、`✦`（AI伴读）、`▦`（画板/全景）、`⛶`（全屏）、`⋯`（更多）
     * `▰`（荧光笔）、`⌫`（橡皮擦）、`✥`（漫游手势）、`↶`（撤销笔迹）、`—`（单页）、`‹` / `›`（翻页）、`☰`（目录/侧栏）、`▯`（双页）
     * `⭳`（导出）、`↗`（全屏/弹窗）、`⇄`（切换）、`⧉`（分屏）、`⎙`（打印）、`⌕`（检索）、`⎚`（清空）
2. **中性灰阶与高对比度层次**：
   * 严格依托 [`DesignTokens.ets`](file:///e:/apps/entry/src/main/ets/common/constants/DesignTokens.ets)；
   * 背景色采用深邃中性黑 `#121212` 与纯白 `#FFFFFF`，表面卡片采用 `#1E1E1E` / `#F5F5F7`；
   * 边框采用超细微半透明描边（`1vp rgba(255,255,255,0.08)` / `rgba(0,0,0,0.06)`）；
   * 按钮与触控区域严格保证 44vp 最小触控热区。

---

## 四、 笔控与触控分离引擎（Touch & Pen Separation）

1. **阅读模式与批注模式互锁**：
   * **阅读模式（Reading Mode）**：关闭手写图层手势响应，全屏触控归属页面滚动、翻页与双指缩放。
   * **批注模式（Annotation Mode）**：激活手写图层，拦截笔触输入并实时绘制墨水。
2. **硬件级 SourceTool 分流与防误触（Palm Rejection）**：
   * 识别手写笔硬件输入（`Pencil`）与手指触摸（`Finger`）；
   * 笔尖接触屏幕产生高精度 `CanvasStroke` 坐标点，采用 **二次贝塞尔曲线（Quadratic Bézier）** 进行插值平滑，彻底消除折线感；
   * 手掌或多指触碰时，手写图层主动过滤，仅允许双指捏合缩放（Pinch-to-Zoom）与抓手漫游（Hand Pan），提供媲美原生纸质试卷的书写体验。

---

## 五、 HarmonyOS GPU 光栅化渲染避坑三铁律（彻底根除折光与撕裂）

在排查全屏阅读器 [`HuaweiDocWorkspace.ets`](file:///e:/apps/entry/src/main/ets/views/reader/huawei/HuaweiDocWorkspace.ets) 中打开「更多」面板、快速跳转与退出弹窗时从屏幕左上角 `(0, 0)` 放射状拉扯到居中卡片的深色/反色三角形折光拉丝时，确立了以下三大不可逾越的渲染铁律：

| 避坑铁律 | 物理与 GPU 底层根因 | 架构重构方案 |
|---|---|---|
| **1. 容器几何混淆禁令**<br>（严禁 Stack 居中蒙层卡片） | `Stack({ alignContent: Center })` 内部同级并列全屏蒙层（100% 宽高）与居中卡片（440vp）时，GPU Tessellator 在裁剪计算（scissor rect）中混淆了两个同级视口边界，导致把蒙层退化渲染为从 `(0, 0)` 到卡片边缘的三角形拉伸。 | **单层居中 Column 蒙层**：使用单层全屏 `Column().width('100%').height('100%').justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)` 作为遮罩背景，卡片作为唯一居中子元素，在卡片上绑定 `.onClick((e) => e?.stopPropagation())` 阻断冒泡。 |
| **2. 阻尼物理反弹禁令**<br>（透明度过渡严禁欠阻尼弹簧） | 在 `TransitionEffect.OPACITY` 上使用欠阻尼弹簧（`curves.springMotion(0.28, 0.72)`）时，物理振荡会导致 $\alpha > 1.0$。在 GPU 预乘透明度混合方程 $C_{out} = C_{src} + C_{dst} \times (1 - \alpha_{src})$ 下产生 $(1 - \alpha) < 0$ 的负值，导致底色被反向相减，产生刺眼的蓝紫色放射反光。 | **单调有界缓动曲线**：所有透明度过渡必须采用严格单调无超调的 `Curve.EaseInOut`，时长控制在 `180ms ~ 250ms`，确保 $\alpha \in [0.0, 1.0]$。 |
| **3. 异步排版防抖禁令**<br>（动态弹层内禁用虚拟化 Grid） | `Grid({ columnsTemplate })` 属于重型虚拟化组件，在弹窗进场动画期间存在异步排版和 Scissor 计算延迟，容易引发视口跳变与撕裂。 | **静态双层 Row 均分**：弹层功能列表替换为静态 `Column({ space: 10 })` + 双 `Row({ space: 10 })`，子项使用 `.layoutWeight(1)` 均分宽度，零排版抖动。 |

---

## 六、 阅读器非破坏性退出与防丢失闭环

1. **退出拦截机制**：
   * 当用户在阅读器中点击左上角返回或触发返回手势时，拦截直接退出路由；
   * 弹出居中极简 [`exitConfirmationDialog`](file:///e:/apps/entry/src/main/ets/views/reader/huawei/HuaweiDocWorkspace.ets) 确认对话框。
2. **确定性三态闭环**：
   * **「保存并退出」**：立即抓取当前文档最新的手写批注数据（`pageAnnotations`），调用 `NoteStorageService` 完整持久化写入沙箱文件与 Preferences 快照，然后安全退出阅读器。
   * **「放弃修改」**：丢弃未持久化的临时笔迹与修改，直接返回工作台。
   * **「取消」**：关闭模态弹窗，保持在当前阅读与批注位置不变。
