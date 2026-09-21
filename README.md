# FlowMind（墨语）

FlowMind（墨语）是一款面向 HarmonyOS NEXT 平板的 Local-First 双链知识库与阅读工作台。它将 Markdown 笔记、PDF 批注、手写草稿、待办事项、全文检索和关系图谱放在同一个本地优先的工作流中。

> 离线可用、数据私密，让每篇笔记都连成思考的星系。

## 项目状态

- 平台：HarmonyOS NEXT
- UI：ArkUI 声明式开发
- 语言：ArkTS
- 支持设备类型：phone、tablet
- 数据策略：本地优先，笔记和工作区数据保存在应用沙箱
- 当前构建产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`
- 仓库：[RETEMPT/moyu](https://github.com/RETEMPT/moyu)

当前工程的 `signingConfigs` 为空，因此生成的是未签名 HAP。该产物可用于开发模拟器验证；正式发布前需要配置 HarmonyOS 应用签名。

## 主要功能

### 知识库与笔记

- Markdown 笔记编辑和阅读
- `[[双链]]` 解析、反向链接和全文搜索
- 项目、资料、回收站和移动归类
- 目录大纲、上下文抽屉和快速搜索
- 本地示例数据和工作区统计

### 阅读与批注

- PDF 多页阅读和 A4 页面布局
- 原生批注、矢量手写墨水和草稿
- 边读边写分屏
- 纯文字随笔与 Markdown 阅读模式
- 文档导入、导出和统一文档操作弹窗
- AI 伴读分屏界面

### 工作区

- 首页统计和视觉书架
- 待办清单与日历视图
- 图谱工作区
- 资料库和待处理内容
- 浅色、深色和跟随系统主题

## 技术栈

| 层次 | 技术 |
| --- | --- |
| 开发语言 | ArkTS |
| UI | ArkUI |
| 文本 | Markdown 解析、TextArea / RichEditor 相关能力 |
| 图形 | ArkUI Canvas |
| 本地存储 | Preferences 快照与应用沙箱文件 |
| 检索 | 本地全文检索与双链关系解析 |
| 构建 | DevEco Studio、Hvigor |
| 部署 | hdc、HarmonyOS 模拟器或开发设备 |

## 目录结构

```text
E:\apps\
├── AppScope/                  应用级配置和图标资源
├── design/                    图标 SVG 母版
├── tools/                     图标生成工具
├── build-profile.json5        SDK、产品和构建模式配置
├── hvigorfile.ts              Hvigor 工程入口
├── entry/
│   ├── build/                 构建输出
│   └── src/main/
│       ├── ets/
│       │   ├── common/        常量、主题、类型、工具和示例数据
│       │   ├── services/      存储、搜索、解析和工作区服务
│       │   ├── views/         布局、工作区、阅读器和弹层组件
│       │   ├── entryability/  EntryAbility
│       │   └── pages/         Index 顶层状态和页面装配
│       └── resources/         字符串、颜色、图标和页面配置
└── .codegenie/                CodeGenie 规范、部署脚本和项目文档
```

## 开发环境

建议使用：

- DevEco Studio 26.0.0 或兼容版本
- HarmonyOS SDK，目标 SDK `26.0.0`
- Compatible SDK `6.1.1(24)`
- Windows PowerShell 5.1 或更高版本
- 已创建并启动的 HarmonyOS 模拟器，或已连接的开发设备

首次打开项目后，请在 DevEco Studio 中同步依赖并等待索引完成。工程依赖定义位于：

- `oh-package.json5`
- `oh-package-lock.json5`

## 构建 HAP

### 使用 DevEco Studio

1. 用 DevEco Studio 打开 `E:\apps`。
2. 等待 SDK、依赖和索引准备完成。
3. 选择 `default` product 和 `debug` build mode。
4. 执行 **Build > Make Module 'entry'**，或直接运行部署脚本。

### 使用命令行

工程使用 DevEco Studio 自带的 Hvigor 和 JBR。普通 PowerShell 不一定自动拥有 `DEVECO_SDK_HOME` 与 `JAVA_HOME`，建议使用下面的部署脚本，它会自动注入环境变量。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File E:\apps\.codegenie\deploy.ps1
```

仅构建、不安装到设备：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File E:\apps\.codegenie\deploy.ps1 -SkipBuild
```

构建完成后，重点检查：

```text
E:\apps\entry\build\default\outputs\default\entry-default-unsigned.hap
```

## 安装和启动

部署脚本会依次执行：

1. 注入 DevEco SDK 和 JBR 环境变量；
2. 执行 `assembleHap`；
3. 启动或等待 HarmonyOS 模拟器；
4. 等待 hdc 设备上线；
5. 安装未签名 HAP；
6. 启动 `EntryAbility`。

也可以手动使用 hdc：

```powershell
hdc list targets
hdc -t 127.0.0.1:5555 install -r `
  E:\apps\entry\build\default\outputs\default\entry-default-unsigned.hap
hdc -t 127.0.0.1:5555 shell aa start `
  -a EntryAbility -b com.example.myapplication
```

不同模拟器的 target 地址可能不同，请以 `hdc list targets` 输出为准。

## hdc 部署卡住时

如果 `hdc file send`、安装或启动长时间没有响应，可以按以下顺序恢复：

```powershell
hdc kill
hdc start
hdc list targets
```

确认模拟器完成冷启动并重新出现在 `hdc list targets` 后，再执行安装。不要在设备尚未上线时重复发送 HAP。

如需启动模拟器、自动等待上线或抓取 faultlog，可使用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File E:\apps\.codegenie\deploy.ps1 -TailFaultLog
```

完整参数和工具路径说明见 [.codegenie/deploy.ps1](./.codegenie/deploy.ps1)。

## 交互稳定性约定

项目针对平板端页面切换和弹层合成做了专门处理：

- 页面切换避免旧页面和新页面同时进行全屏透明度、位移动画；
- 动态弹层避免全屏遮罩与居中卡片在高风险 `Stack` 结构中叠加；
- 透明度动画使用有界的缓动曲线，避免欠阻尼弹簧造成合成过冲；
- 动态弹层不使用虚拟化 `Grid` 作为主要容器；
- 关闭入口使用至少 44vp 的原生 `Button`；
- 弹层卡片使用命中行为隔离，避免点击穿透；
- 关闭、返回、遮罩取消和退出确认保持同一条状态链路。

修改阅读器或弹层时，请先阅读 [.codegenie/MEMORY.md](./.codegenie/MEMORY.md) 和 [.codegenie/agent.md](./.codegenie/agent.md)。

## 回归检查清单

部署到模拟器或设备后，建议至少验证：

- 更多面板打开、关闭和遮罩关闭；
- 文档操作弹窗的右上角关闭、取消和确认；
- 快速跳转弹窗关闭；
- AI 伴读分屏关闭；
- 顶栏返回和退出确认；
- 保存并退出、放弃修改、取消；
- 普通笔记、PDF、待办、回收站、图谱和资料库之间切换；
- 深色、浅色和跟随系统主题切换；
- 笔记编辑后重新打开，确认内容仍然存在；
- PDF 批注、手写和页面切换；
- 快速搜索、双链跳转和反向链接；
- 应用重启后的主题、笔记和待办恢复。

## 开发约定

- 新功能代码放在 `entry/src/main/ets` 下的现有分层中。
- `common/` 不反向依赖 `services/` 或 `views/`。
- `services/` 只负责业务逻辑和系统能力，不持有 UI 状态。
- `views/` 通过 `@Prop` 和回调接收数据，不直接修改顶层全局状态。
- 优先使用明确的 ArkTS 类型，避免 `any`、隐式类型转换和无依据的类型断言。
- 修改状态链路后，同时检查落盘、界面刷新、搜索索引和图谱更新。
- 修改弹层或全屏阅读器后，必须进行设备端点击回归。

更完整的架构、数据模型和编码约束见 [`.codegenie/agent.md`](./.codegenie/agent.md)。

## 相关文档

| 文档 | 说明 |
| --- | --- |
| [.codegenie/PROJECT_OVERVIEW.md](./.codegenie/PROJECT_OVERVIEW.md) | 最新项目概况、修复历史和验证状态 |
| [.codegenie/MEMORY.md](./.codegenie/MEMORY.md) | 渲染、状态、数据和部署经验 |
| [.codegenie/agent.md](./.codegenie/agent.md) | CodeGenie 项目级开发规范 |
| [.codegenie/deploy.ps1](./.codegenie/deploy.ps1) | 构建、部署、启动和 faultlog 脚本 |
| [.codegenie/harmonyos-capability-research.md](./.codegenie/harmonyos-capability-research.md) | HarmonyOS 能力调研 |
| [.codegenie/markdown-storage-maintenance.md](./.codegenie/markdown-storage-maintenance.md) | Markdown 存储和自动保存说明 |
| [.codegenie/markdown-search-backlinks.md](./.codegenie/markdown-search-backlinks.md) | 全文检索和双链图谱说明 |

## 许可证

项目许可证以仓库中的 [LICENSE](./LICENSE) 文件为准。
