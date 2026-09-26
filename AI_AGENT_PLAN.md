# AI 墨客 · 三层智能体与可配置模型接入 · 完整规划文档

> 文档定位：面向本项目（HarmonyOS NEXT / ArkTS / Stage 模型）的**实施级规划**，
> 覆盖三层 AI 智能体的执行原则、模型 API 可配置化、主页「AI 墨客」对话检索功能、
> 以及 GPT 风格页面与右侧对话记录栏的落地路径。
> 代码分层约束统一为：`pages/` → `views/` → `services/` → `common/`，本规划严格遵循该方向。

---

## 0. 现状盘点（What already exists）

| 模块 | 现状 | 与本规划的关系 |
|---|---|---|
| `views/workspace/PendingWorkspace.ets` | 「AI 墨客」当前为占位页，清单已写明目标 | 已固化三层命名：**L1 伴读 / L2 学情 / L3 跨库**，本规划以此为准 |
| `views/reader/huawei/HuaweiAiSplitPanel.ets` | 华为风 AI 伴读面板，**mock 数据 + setTimeout 假回复** | UI 骨架可复用，需接入真实模型流式响应 |
| `services/NoteSearchService.ets` | 关键词检索（标题/正文/标签）+ 双向链接图 | **检索层地基**，升级为混合检索 + 分块 + 引用 |
| `services/MarkdownParserService.ets` | Markdown 解析（标题/标签/链接） | 分块（chunking）与大纲提取的入口 |
| `services/NoteStorageService.ets` | `preferences` 快照 + 沙箱 `.md` 正文文件 | 对话记录、模型配置的持久化范式照此实现 |
| `views/settings/AppearanceSheet.ets` | 外观设置（居中对话框 + 选中态圆点） | **模型设置面板**照此交互范式扩展 |
| 网络层 | **完全空白**（无 `@kit.NetworkKit` / rcp 引用） | 模型调用层为绿地，需从零搭建 |

---

## 1. 总体架构

```
┌─────────────────────────────────────────────────────────────────┐
│  pages/Index.ets        工作台路由 · 全局状态持有者               │
└───────────────┬─────────────────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────────────────┐
│  views/                                                          │
│  ├── ai/AiWorkspace.ets          GPT 风格主界面（替换 Pending）   │
│  ├── ai/ChatSessionRail.ets      左栏「对话列表」模式内容体       │
│  ├── ai/MessageStream.ets        消息流（用户/助手气泡）          │
│  ├── ai/MessageInputBar.ets      输入框 + 模型选择器 + @/附笔记   │
│  ├── ai/ContextSourcePanel.ets   右栏引用来源 / 命中片段          │
│  ├── ai/NotePickerSheet.ets      @/附笔记 的笔记选择器            │
│  └── settings/ModelSettingsSheet.ets  模型 API 配置面板           │
└───────────────┬─────────────────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────────────────┐
│  services/                                                       │
│  ├── ai/ModelProvider.ets        抽象接口 + Provider 工厂         │
│  ├── ai/providers/OpenAiCompatProvider.ets   OpenAI 兼容协议      │
│  ├── ai/providers/GeminiProvider.ets         Gemini generateContent│
│  ├── ai/providers/AnthropicProvider.ets      Anthropic messages    │
│  ├── ai/providers/CustomHttpProvider.ets     自定义 HTTP 模板      │
│  ├── ai/AgentOrchestrator.ets    三层智能体调度核心               │
│  ├── ai/agents/DocCompanionAgent.ets   L1 伴读                    │
│  ├── ai/agents/LearningAnalystAgent.ets L2 学情                   │
│  ├── ai/agents/CrossVaultAgent.ets      L3 跨库                   │
│  ├── ai/RagRetriever.ets         混合检索（关键词+向量）          │
│  ├── ai/ChunkIndexService.ets    Markdown 分块与本地索引          │
│  ├── ai/ChatSessionService.ets   对话记录持久化                   │
│  └── ai/ModelConfigService.ets   模型配置读写                     │
└───────────────┬─────────────────────────────────────────────────┘
                │
┌───────────────▼─────────────────────────────────────────────────┐
│  common/                                                         │
│  ├── types/ModelConfig.ets       模型配置类型                     │
│  ├── types/ChatSession.ets       会话/消息类型                    │
│  ├── types/AgentTypes.ets        Agent 相关类型                   │
│  └── types/RagTypes.ets          分块/检索结果类型                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 模型 API 可配置化（不绑定 Gemini）

### 2.1 设计原则

1. **协议抽象，厂商无关**：UI 与业务只依赖 `ModelProvider` 接口，不直接触碰任何厂商 SDK / URL 形态。
2. **OpenAI 兼容优先**：绝大多数国产/开源/中转服务（DeepSeek、Qwen、Moonshot、GLM、Ollama、vLLM、One-API 等）都是 `POST /v1/chat/completions` 形态，作为默认档。
3. **配置即数据**：模型、URL、密钥、温度全部落 `preferences`，运行时热切换，不需重编译。
4. **密钥安全**：API Key 不进日志、不进对话记录导出，设置面板回显时遮罩（`sk-****1234`）。

### 2.2 数据模型 `common/types/ModelConfig.ets`

```typescript
/** 模型调用协议档位 */
export type ProviderProtocol =
  | 'openai-compat'   // POST {base}/chat/completions，SSE stream
  | 'gemini'          // POST {base}/models/{id}:generateContent
  | 'anthropic'       // POST {base}/v1/messages
  | 'custom';         // 用户自定义 HTTP 模板

/** 一个可保存的模型配置档案 */
export interface ModelProfile {
  id: string;                 // uuid
  label: string;              // 用户可读名，如「DeepSeek V3」
  protocol: ProviderProtocol;
  baseUrl: string;            // 如 https://api.deepseek.com/v1
  apiKey: string;             // 明文存 preferences；UI 遮罩显示
  modelId: string;            // 如 deepseek-chat / gemini-2.0-flash
  temperature: number;        // 0~2，默认 0.7
  maxTokens: number;          // 默认 2048
  stream: boolean;            // 是否流式，默认 true
  systemPrompt: string;       // 该档案的系统提示词
  enabledTools: AgentToolName[]; // 允许模型调用的工具白名单
  createdAt: number;
  updatedAt: number;
}

/** 运行时请求（与厂商无关） */
export interface ChatCompletionRequest {
  messages: ChatMessage[];    // 含 system / user / assistant / tool
  temperature?: number;
  maxTokens?: number;
  stream?: boolean;
  tools?: ToolDefinition[];
}

/** 运行时响应（归一化） */
export interface ChatCompletionChunk {
  delta: string;              // 增量文本
  done: boolean;
  toolCall?: ToolCall;        // 若模型发起工具调用
  usage?: { promptTokens: number; completionTokens: number };
}
```

### 2.3 Provider 抽象 `services/ai/ModelProvider.ets`

```typescript
export interface ModelProvider {
  /** 连通性测试：返回模型回声或极短补全，用于设置面板「测试连接」 */
  testConnection(profile: ModelProfile): Promise<ModelTestResult>;
  /** 流式补全：通过回调推送增量，可取消 */
  completeStream(
    profile: ModelProfile,
    request: ChatCompletionRequest,
    onChunk: (chunk: ChatCompletionChunk) => void,
    signal?: AbortHandle
  ): Promise<void>;
  /** 非流式补全 */
  complete(profile: ModelProfile, request: ChatCompletionRequest): Promise<string>;
}

/** 工厂：按 protocol 分派，是唯一知道厂商细节的入口 */
export function createProvider(protocol: ProviderProtocol): ModelProvider;
```

### 2.4 各协议接入要点

| 协议 | 端点 | 流式 | 说明 |
|---|---|---|---|
| `openai-compat` | `POST {baseUrl}/chat/completions` | SSE `data: {...}` 逐行解析 | **默认推荐**，覆盖面最广 |
| `gemini` | `POST {baseUrl}/models/{modelId}:generateContent` | `:streamGenerateContent?alt=sse` | key 走 `x-goog-api-key` 或 `?key=` |
| `anthropic` | `POST {baseUrl}/v1/messages` | SSE `event: content_block_delta` | key 走 `x-api-key`，需 `anthropic-version` 头 |
| `custom` | 用户填写 URL/Method/Header/Body 模板 | 可选 | 模板中用 `{{messages}}` `{{model}}` 占位符 |

网络实现统一使用 HarmonyOS `@kit.NetworkKit` 的 `http`（简单）或 `rcp`（需流式/取消/更现代 API 时）。
封装在 `services/ai/` 内部，**不得**让 `views/` 直接 import 网络 kit。

### 2.5 设置面板 `views/settings/ModelSettingsSheet.ets`

沿用 [AppearanceSheet.ets](entry/src/main/ets/views/settings/AppearanceSheet.ets) 的居中对话框 + 遮罩范式：

```
┌──────────────────────────────────────────────┐
│  模型设置                              ✕      │
├──────────────────────────────────────────────┤
│  当前档案：DeepSeek V3                 ▾     │  ← 档案下拉
├──────────────────────────────────────────────┤
│  名称        [ DeepSeek V3                ]  │
│  协议        (•) OpenAI 兼容  ( ) Gemini    │  │
│              ( ) Anthropic   ( ) 自定义     │
│  Base URL    [ https://api.deepseek.com/v1 ] │
│  API Key     [ sk-****1234    ]  👁 显示     │
│  模型 ID     [ deepseek-chat               ] │
│  温度        [====●======]  0.7             │
│  最大 Token  [ 2048 ]                        │
│  流式输出    [====●======]  开               │
│  系统提示词  [ 你是笔记助手……           ]     │
├──────────────────────────────────────────────┤
│  [ 测试连接 ]        [ 保存 ]  [ 新增档案 ]  │
│  提示：密钥仅存本机，不上传；导出对话时自动脱敏。│
└──────────────────────────────────────────────┘
```

交互细则：
- 「测试连接」调用 `provider.testConnection()`，成功显示「✓ 连通，延迟 420ms」，失败显示可读错误（鉴权失败/超时/URL 非法）。
- 档案可新增、复制、删除；至少保留一个可用档案，删除最后一个时禁止。
- 顶部全局模型切换器（AI 墨客界面内）与本面板双向同步 `ModelConfigService.activeProfileId`。

---

## 3. 三层智能体执行原则与指南

三层命名沿用 [PendingWorkspace.ets](entry/src/main/ets/views/workspace/PendingWorkspace.ets) 已固化文案：**L1 伴读 / L2 学情 / L3 跨库**。

### 3.1 分层定位

| 层 | 名称 | 职责 | 上下文范围 | 触发场景 |
|---|---|---|---|---|
| **L1** | 伴读 Agent | 针对**当前打开文档**的问答、讲解、公式推导、总结、改写、出题 | 当前笔记/PDF 正文 + 大纲 + 相邻选区 | 阅读器内选中提问、侧栏追问、快捷键 |
| **L2** | 学情 Agent | 学习分析：薄弱点、复习计划、进度回顾、待办联动、知识掌握度 | 全库笔记元数据 + 标签/图谱 + 待办 + 阅读/编辑时序 | 「学情报告」「生成复习计划」 |
| **L3** | 跨库 Agent | 跨文档 RAG 问答、知识图谱检索、带来源引用的综合回答 | **全部笔记分块索引**（混合检索 + 向量） | AI 墨客主对话、跨库研究提问 |

### 3.2 核心执行原则（Implementation Principles）

> 这三条是硬约束，任何一层都必须满足。

**P1 · 分层升级，而非全量灌入**
- 调度器默认从 **L1** 起步；当判定问题超出当前文档（用户问「全库」「其他笔记」「综合」或 L1 检索无命中）时，逐级升到 L2/L3。
- 禁止一次性把所有笔记塞进上下文。每层有独立的上下文预算（token budget）。

**P2 · 有据可查，禁止幻觉**
- L3（以及涉及引用的 L1/L2）回答**必须**携带来源片段（`Citation[]`：noteId、标题、命中 chunk、行区间）。
- 检索不到依据时，模型应明确说「资料库中未找到相关记载」，而不是编造。
- UI 在消息下方渲染引用卡片，点击可跳转到源笔记对应位置。

**P3 · 工具化（Tool Use）统一出口**
- 三层 Agent 不硬编码能力，而是通过 **工具注册表**（`ToolDefinition[]`）暴露能力给模型：
  - `search_notes(query, filters)` — 检索
  - `read_note(noteId)` — 读正文
  - `get_outline(noteId)` — 读大纲
  - `list_todos()` / `create_todo(text)` — 待办
  - `get_link_graph(noteId)` — 链接关系
  - `save_note(noteId, content)` — 写回（需用户确认，见 P4）
- 模型返回 `tool_call` → 框架执行 → 结果回灌 → 模型继续。循环设最大轮次（默认 5）防止死循环。

**补充原则：**

**P4 · 写操作需二次确认**：任何落盘动作（改笔记、建待办、删内容）先展示 diff/预览，用户确认后执行。读操作静默执行。

**P5 · 可取消、可并发、可降级**：流式响应必须支持 `AbortHandle` 取消；同会话内新提问自动取消旧请求；网络失败降级为本地关键词检索的离线回答并明确标注「离线摘要」。

**P6 · 上下文隔离**：每层各自维护上下文构建函数，禁止共享可变全局状态；跨层传参用显式不可变对象。

**P7 · 隐私优先（本地优先）**：优先本地完成的（检索、分块、索引、图谱）不上云；只有补全生成走模型 API。API Key 只存本机。

### 3.3 各层实现指南

#### L1 伴读 Agent（`DocCompanionAgent`）
- **输入**：`{ query, document: { title, content, outline, selection? } }`
- **默认关联当前打开文件**：进入伴读时上下文**自动锁定当前文档**，无需用户手动附加；可 `@` 追加其他笔记（与主聊天同一选择器）。
- **系统提示词**：限定「只依据给定文档作答，引用原文时标注段落；超出文档范围说明并建议切换到跨库检索」。
- **上下文构建**：文档正文按 4k token 截断，优先保留选区前后文 + 大纲骨架。
- **输出能力**：讲解、要点提炼、公式推导（结构化 `formula` + `bullets`，沿用 `HuaweiAiSplitPanel` 的消息字段形态）、改写、生成练习题。
- **UI 承载**：阅读器伴读面板（由 `HuaweiAiSplitPanel` 去 mock），与主聊天**共用** `MessageBubble` / `MarkdownMessage` / `MessageInputBar`；仅上下文来源不同（伴读=当前文件，主聊天=全库）。

#### L2 学情 Agent（`LearningAnalystAgent`）
- **输入**：`{ query, learningContext }`，其中 `learningContext` 由框架聚合：
  - 笔记清单（标题、标签、更新时间、字数）
  - 双向链接图（`LinkGraph`）
  - 待办完成率（`TodoStorageService`）
  - 最近打开/编辑序列
- **系统提示词**：定位「学习教练」，输出可执行建议（复习计划、薄弱点、时间安排），**不虚构学习数据**，基于提供的统计陈述。
- **工具**：`list_todos`、`create_todo`（写，需确认）、`get_link_graph`。
- **输出形态**：结构化报告卡片（列表 + 建议 + 可一键转待办）。

#### L3 跨库 Agent（`CrossVaultAgent`）
- **检索链路**（`RagRetriever`）：
  1. **分块**（`ChunkIndexService`）：Markdown 按标题层级 + 段落切块，块内保留所属标题路径；块大小约 300~600 汉字，重叠 80。
  2. **混合召回**：关键词命中（升级现有 `NoteSearchService`）+ 向量相似（本地 embedding，见下）+ 标签/链接加权，Rerank 后取 Top-K（默认 6）。
  3. **引用装配**：每个命中块生成 `Citation { noteId, noteTitle, chunkText, headingPath, score }`。
- **向量索引**：一期可用本地 embedding API（配置项里指定 embedding 端点），哈希/降维后存 preferences 或沙箱文件；二期可换 SQLite + 向量扩展。若用户只配了对话模型没配 embedding，则**自动降级为纯关键词检索**并在回答标注。
- **系统提示词**：「依据下方检索片段作答，每条论断标注来源编号；片段不足时明说并给出检索建议。」

### 3.4 调度器 `AgentOrchestrator.ets`

```
用户提问
  │
  ▼
意图/范围判定（本地规则 + 轻量分类）
  ├─ 指向当前文档 ──────────► L1 伴读
  ├─ 指向学情/复习/计划 ────► L2 学情
  ├─ 指向全库/跨文档/研究 ──► L3 跨库
  └─ 不确定 ────────────────► L1 先答，检索无果则升 L3
  │
  ▼
构建上下文（按层，受 token 预算约束）→ 检索/工具（如需）
  │
  ▼
模型流式补全（Tool Use 循环，最多 5 轮）
  │
  ▼
归一化 ChatMessage（含 Citation[]）→ 持久化 → UI 渲染
```

- 调度器是**唯一**决定用哪层的组件；UI 不直接调 Agent。
- 每层可被用户手动强制（消息输入框的「模式」切换：自动 / 伴读 / 学情 / 跨库）。

---

## 4. 主页「AI 墨客」对话检索功能（GPT 风格页面）

### 4.1 页面结构 `views/ai/AiWorkspace.ets`

替换 [Index.ets](entry/src/main/ets/pages/Index.ets#L1326-L1335) 中 `NAV_AI` 分支的 `PendingWorkspace`，进入真实界面。

#### 左栏双模式（B 方案，复刻 GPT 的「左侧会话列表」）

左侧 `Sidebar` 增加 **笔记树 ↔ 对话列表** 双模式：
- 进入「AI墨客」导航时，左栏**自动**切换为对话列表（GPT 的标志性布局）。
- 全局导航行（首页/资料库/图谱/AI墨客/待办/回收站）**始终保留**，不被挤掉。
- 顶部保留一个 `[树⇄会话]` 切换钮，随时手动切回笔记树（不丢失导航）。
- 右侧仅保留「上下文/来源」窄栏（可折叠），**不与左栏抢位置**。

```
┌────────────────────────────────────────────────────────────────────┐
│  AI 墨客   [ 自动 ▾ ]   DeepSeek V3 ▾                       ⚙ 设置  │ ← 顶栏
├──────────────────┬─────────────────────────────────┬───────────────┤
│ 首页             │                                 │  上下文/来源  │
│ 资料库           │   消息流（居中，最大宽 ~760vp） │  ───────────  │
│ 图谱             │                                 │  命中 6 块    │
│ AI墨客 ◀ 当前    │   ● 帮我总结当前笔记的要点  (用户，右) │  已读 3 篇 │
│ 待办             │   ◆ 当前笔记包含三个核心考点… (助手，左) │             │
│ 回收站           │      [来源：电磁学·§3.2][复制][重试] │  [电磁学·§3.2]│
│                  │   ● 那第二点的公式怎么推导    (用户) │  [高数·定理1] │
│ [树⇄会话] 切换   │   ◆ 由高斯定理出发……▌(流式)   (助手) │             │
│ ──────────────   │                                 │             │
│ + 新对话         │  ┌───────────────────────────┐  │  点击来源可   │
│ 🔍 搜索          │  │ 提问 / @笔记 / 附 语 工具 │ ⬆ │  跳转源笔记   │
│ ──────────────   │  └───────────────────────────┘  │               │
│ ▸ 今天           │                                 │               │
│   介质球复习     │                                 │               │
│ ▸ 昨天           │                                 │               │
│   学情周报       │                                 │               │
└──────────────────┴─────────────────────────────────┴───────────────┘
   左栏=对话列表        主对话区（GPT 风格）         右栏=上下文/来源
   （可切回笔记树）
```

> 说明：会话列表放在**左栏**，严格复刻 GPT 的识别特征；左栏顶部导航常驻，
> `[树⇄会话]` 一键切回项目/笔记树，因此**不与现有 `Sidebar` 冲突**——两者是同一栏的
> 双模式，而非两个并列侧栏。右栏仅承载检索上下文/来源，宽度窄、可折叠，
> 保证主对话区有足够阅读宽度。

### 4.2 组件拆分

| 组件 | 职责 |
|---|---|
| `AiWorkspace.ets` | 三区布局编排、会话状态、与调度器对接 |
| `MessageStream.ets` | 消息列表滚动、气泡、流式光标、复制/重试/引用跳转 |
| `MessageBubble.ets` | 单条消息：用户（右、强调色底）/ 助手（左、Markdown 渲染） |
| `MessageInputBar.ets` | 多行输入、发送、模式切换、模型切换、@/附笔记、语音占位 |
| `ChatSessionRail.ets` | **左栏对话模式内容体**（由 `Sidebar` 双模式承载）：会话列表、新建、搜索、重命名、置顶、删除 |
| `Sidebar.ets`（改造） | 新增 `树 ⇄ 会话` 双模式；导航行常驻，下方在「项目树」与「ChatSessionRail」间切换 |
| `ContextSourcePanel.ets` | 右栏窄栏：本次命中的来源片段、已读笔记、检索透明度；点击跳转源笔记 |
| `NotePickerSheet.ets` | `@` /「附笔记」弹出的笔记选择器（可搜索、多选、可选「当前笔记」） |
| `MarkdownMessage.ets` | 助手消息 Markdown 渲染：**标题 / 列表 / 代码块 / 公式块 / 表格 / 引用**（复用 `MarkdownParserService`） |

> 共享组件：`MessageBubble` / `MarkdownMessage` / `MessageInputBar` 抽为共享，
> 阅读器内「伴读」面板（`HuaweiAiSplitPanel` 去 mock）复用同一套渲染与输入；
> 区别只在上下文来源——**伴读默认锁定当前打开文件**（L1），主聊天默认全库（L3）。

### 4.3 交互要点（复刻 GPT 习惯）

1. **气泡布局**：用户消息右对齐、强调色实底圆角；助手消息左对齐、浅表面底，无头像或极简标识（`◆`）。
2. **流式输出**：逐 token 追加，行尾光标 `▌`，可随时点「停止」取消（`AbortHandle`）。
3. **消息操作**（hover 显示）：复制、重试（重新生成该条及之后）、编辑后重问、跳转引用。
4. **Markdown 渲染**：标题、列表、代码块、公式块（`formula` 独立块，沿用 `HuaweiAiSplitPanel` 现有样式）、表格、引用。
5. **自动滚动**：流式输出时跟随到底部，用户上滚后暂停跟随并出现「回到底部」按钮。
6. **空态**：居中问候语 + 快捷提示卡（「总结当前笔记」「生成复习计划」「跨库检索 X」）。
7. **提交方式**：`Enter` 发送，`Shift+Enter` 换行；发送后输入框清空并聚焦。

### 4.4 对话检索能力（RAG 特性）

提问默认走 **L3 跨库**检索（这是「对话检索类」主入口），可被模式切换/意图判定覆盖。
上下文来源是**四条通路叠加**，而非单选：

| 通路 | 触发 | 行为 |
|---|---|---|
| **1. 自动附当前笔记** | 从阅读器进入 / 左栏切换到会话 | 默认锁定当前打开文件（等价 L1 伴读语境） |
| **2. `@` 指定** | 输入 `@` 触发 | 弹出 `NotePickerSheet` 选择器，把指定笔记**强制**并入上下文 |
| **3. 对话框选入** | 输入栏「附笔记」按钮 | 同一选择器，多选笔记/项目批量加入，可搜索 |
| **4. 全库自动检索** | 任何提问 | 后台对**全部笔记分块索引**做混合检索，命中片段自动进上下文 |

**分区索引提炼（关键，不可敷衍）** —— 通路 4 的质量取决于分块：

- **分块**（`ChunkIndexService`）：Markdown 按**标题层级 + 段落**切块，每块保留
  所属 `headingPath`（如「第3章 > 3.2 介质球」）；块大小约 300~600 汉字，重叠 80。
  - 标题块：只保留标题 + 首段摘要，作为「章节锚点」。
  - 列表块：整列表合并为一块，不逐条切断语义。
  - 代码块 / 公式块：**整块保留不切**，避免拆坏语法。
  - 表格块：整表一块。
- **索引**：建立 `chunkId → { noteId, headingPath, tokenEstimate, 倒排关键词, 向量 }`。
  支持**增量更新**（笔记改动只重建该笔记的块），不全量重跑。
- **混合召回**：关键词（升级 `NoteSearchService`）+ 向量相似（本地 embedding）+ 标签/链接加权，
  Rerank 后取 Top-K（默认 6）。
- **降级**：用户未配 embedding 时自动降级纯关键词检索，并在回答明确标注「仅关键词匹配」。

**来源呈现**：回答下方展示 **来源引用条**：`[电磁学 · §3.2] [高等数学 · 定理1]`，
点击展开命中片段并跳转源笔记对应位置；右栏「上下文/来源」实时显示本次命中块数、
涉及笔记，做到「AI 依据什么作答」全程透明。

---

## 5. 左栏「对话记录」模式 `ChatSessionRail.ets`

> 承载于 `Sidebar` 的「会话」模式下（§4.1 左栏双模式）：进入 AI墨客 自动切换，
> `[树⇄会话]` 可切回笔记树；导航行始终保留。

### 5.1 数据模型 `common/types/ChatSession.ets`

```typescript
export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant' | 'system' | 'tool';
  text: string;               // Markdown 正文
  formula?: string;           // 独立公式块（可选）
  bullets?: string[];         // 结构化要点（可选）
  citations?: Citation[];     // L3 来源引用
  agentLayer?: 'L1' | 'L2' | 'L3';
  modelProfileId?: string;    // 生成该条的模型档案
  createdAt: number;
  streaming?: boolean;        // 是否仍在流式
  error?: string;             // 失败原因
}

export interface ChatSession {
  id: string;
  title: string;              // 首条用户提问自动截断命名
  pinned: boolean;
  agentMode: 'auto' | 'L1' | 'L2' | 'L3';
  messages: ChatMessage[];
  createdAt: number;
  updatedAt: number;
}
```

### 5.2 持久化 `services/ai/ChatSessionService.ets`

严格照搬 [NoteStorageService.ets](entry/src/main/ets/services/NoteStorageService.ets) 范式：

- 单独 Preferences：`flowmind_chat`，键 `sessions`。
- 每次会话变更 `persistSnapshot()` 写入 JSON；正文（消息）跟随快照即可（消息量可控），不拆文件。
- **清理策略**：默认保留最近 200 个会话；置顶不清理；提供「清空全部对话」显式入口（二次确认）。
- **导出**：导出 Markdown 时自动脱敏 API Key（正则 `sk-[A-Za-z0-9]+` 等）。

### 5.3 栏内交互

| 功能 | 交互 |
|---|---|
| 新建对话 | 顶部「+ 新对话」，创建后聚焦输入框并清空当前上下文 |
| 会话列表 | 按 `updatedAt` 倒序，分组「今天 / 昨天 / 7 天内 / 更早」 |
| 搜索 | 顶部搜索框，匹配标题与消息正文（可复用 `NoteSearchService` 的检索思路） |
| 置顶 | 悬停出现 📌（项目约定避免彩色 emoji 时用 `◇/◆` 文字符号），置顶项固定在最上 |
| 重命名 | 悬停 `✎` 就地编辑标题 |
| 删除 | 悬停 `✕`，`DestructiveConfirm` 二次确认（复用 `SheetScaffold.ets` 现有范式） |
| 切换会话 | 点击加载该会话消息到主区，右栏「上下文/来源」同步 |

宽度：`LayoutTokens` 新增 `AI_SESSION_RAIL_WIDTH = 280`（即左栏会话模式宽度，与笔记树同宽；`[树⇄会话]` 折叠后只留图标条 48vp）。

---

## 6. 数据层与接口契约汇总

### 6.1 新增类型文件（`common/types/`）
- `ModelConfig.ets` — §2.2
- `ChatSession.ets` — §5.1（含 `Citation`）
- `AgentTypes.ets` — `AgentToolName`、`ToolDefinition`、`ToolCall`、`AgentRunContext`
- `RagTypes.ets` — `Chunk { id, noteId, headingPath, text, tokenEstimate }`、`RetrievalHit { chunk, score, source: 'keyword'|'vector'|'tag' }`

### 6.2 新增服务（`services/ai/`）
| 服务 | 依赖 | 说明 |
|---|---|---|
| `ModelConfigService` | `preferences` | 模型档案 CRUD、active 档案、热更新通知 |
| `ModelProvider` + `providers/*` | `@kit.NetworkKit` | 厂商无关补全（§2.3/2.4） |
| `ChunkIndexService` | `MarkdownParserService` | 分块 + 索引构建/增量更新 |
| `RagRetriever` | `NoteSearchService`, `ChunkIndexService` | 混合检索 + Rerank + 引用装配 |
| `AgentOrchestrator` | 上述全部 | 三层调度 + 工具循环（§3.4） |
| `ChatSessionService` | `preferences` | 对话持久化（§5.2） |

### 6.3 依赖方向自检
`pages/Index` → `views/ai/*` → `services/ai/*` → `common/*`。
`views/` **不** import 网络 kit 或 `preferences`；`services/ai/providers` 是唯一触碰 HTTP 的地方。

---

## 7. 分阶段实施路线图

> 状态截至 2026-09-25。已勾选项均已编译通过并在 HarmonyOS 模拟器上实机验证。

### Phase 1 · 模型配置与网络地基（先跑通一次真实调用）— ✅ 已完成
- [x] `common/types/ModelConfig.ets`
- [x] `services/ai/ModelConfigService.ets`（preferences 持久化 + 热更新广播）
- [x] `services/ai/ModelProvider.ets` + `OpenAiCompatProvider`（流式 SSE）
- [x] `GeminiProvider` / `AnthropicProvider`（三协议齐备）
- [x] `views/settings/ModelSettingsSheet.ets`（含「测试连接」「向量模型」）
- [x] `ohos.permission.INTERNET`
- **实测**：请求真实抵达 api.deepseek.com，401 被正确解码并回显
  `HTTP 401: Authentication Fails (auth header format should be Bearer ...)`。
  **未做**：填入真实密钥后的成功流式补全（本机无密钥）。
- **未做**：全局顶栏模型切换器（当前入口在 AI 墨客顶栏 ⚙ 与伴读面板模型名）。

### Phase 2 · GPT 风格 AI 墨客主界面 + 左栏对话记录 — ✅ 已完成
- [x] `Sidebar` 改造：「树 ⇄ 会话」双模式（进 AI墨客 自动切会话列表，可手动切回，导航常驻）
- [x] `views/ai/AiWorkspace.ets` 接管 `NAV_AI`
- [x] 消息气泡 + 层级角标 + 流式渲染（标题/列表/代码/公式块）+ 停止
- [x] 会话列表（新建/切换/删除/长按置顶）+ `ChatSessionService` 持久化
- [x] 右栏 `views/ai/AiSourcesPanel.ets`（层级/模型/绑定文档 + 检索来源，可点跳源笔记）
- **实测**：冷启动进入 AI 墨客自动切「对话记录」并显示 `[资料树|对话]` 切换器；
  点「资料树」可切回且不丢失 AI 页面；会话列表空态正常。
- **未做**：重命名会话、会话内搜索、消息「重试/复制」。

### Phase 3 · 检索增强（真正的 RAG + 分区索引提炼）— 🟡 部分完成
- [x] `ChunkIndexService` 按标题层级分块，`headingPath` 贯穿，代码/公式整块保留
- [x] `RagRetriever.searchHybrid()`：向量为主、关键词兜底（分数不同量纲，不做加权求和）
- [x] `EmbeddingProvider` + `EmbeddingIndexService`（OpenAI `/embeddings`、Gemini
      `batchEmbedContents`；Anthropic 无端点 → 返回 null 并降级关键词）
- [x] 三通路上下文：自动附当前文档 / `@` 指定笔记（硬上下文）/ 全库自动检索
- [x] 引用渲染 + 右栏来源
- **未做**：标签/链接加权、Rerank；`@` 目前是输入栏旁的勾选浮层，
  尚未实现输入框内 `@` 触发候选（`NotePickerSheet` 形态）。
- **未做**：向量落盘缓存（当前仅内存缓存，进程重启后需重新向量化）。

### Phase 4 · 三层智能体落地 — 🟡 部分完成
- [x] `AgentOrchestrator`（分层调度 + 工具循环，最多 5 轮）
- [x] `DocCompanionAgent`（L1）对接 `HuaweiAiSplitPanel` — **mock 已全部移除**
- [x] `LearningAnalystAgent`（L2）真实学情统计注入（标签/项目/待办/最近更新）
- [x] `CrossVaultAgent`（L3）与 Phase 3 检索打通
- [x] 模式切换（自动/伴读/学情/跨库）+ 关键词意图判定
- [x] 工具循环 + 写操作二次确认（`ToolRegistry` / `AgentToolExecutor`）
- **实测**：`自动` 模式下「生成复习计划」被正确判为 **L2 学情**，
  气泡角标与右栏「层级」一致。
- **未做**：工具调用（`create_todo` 确认弹窗）未能实测——需要可用密钥才能让模型真正发起调用。
- **未做**：模型分类器（当前为关键词规则兜底，见 `classify()`）。

### Phase 5 · 打磨与健壮性 — 🟡 部分完成
- [x] 取消（`StreamHandle.abort` + `cancelled` 标志）/ 超时（connect 15s / read 120s）
- [x] 错误态统一：HTTP 错误经终止 chunk 上报，不再挂起 UI
- [x] 空态、离线（无密钥）态提示
- **未做**：密钥脱敏导出、会话分页、索引增量更新、单测。

---

## 8. 风险与约束

| 风险 | 影响 | 缓解 |
|---|---|---|
| 网络 API 在 HarmonyOS 上的权限与证书 | 调用失败 | 需在 `module.json5` 配置 `ohos.permission.INTERNET`；HTTPS 证书合法；开发期注意网络安全配置 |
| SSE 流式解析在 ArkTS 的实现复杂度 | 流式不稳定 | 先用非流式跑通，再上流式；`providers` 内隔离复杂度 |
| 向量 embedding 需要额外端点 | 无 embedding 时无法语义检索 | 关键词检索兜底并在 UI 标注降级 |
| 长会话 token 超限 | 截断/报错 | 上下文预算 + 滑动窗口 + 摘要压缩旧轮次 |
| 模型幻觉 / 错误引用 | 误导用户 | P2 强制来源标注 + 「资料库未找到」话术 |
| API Key 明文存 preferences | 泄露面 | 仅本机、UI 遮罩、导出脱敏；后续可选系统密钥库 |
| `animateTo` 等 API 已 deprecated | 警告 | 遵循项目既有写法，不在本规划引入新弃用 API |

---

## 9. 命名与文案约定（对齐现有代码）

- 页面/组件中文名统一「**AI 墨客**」（[WorkspaceConstants.ets](entry/src/main/ets/common/constants/WorkspaceConstants.ets) 的 `NAV_AI = 'AI墨客'`）。
- 三层固定称谓：**L1 伴读 / L2 学情 / L3 跨库**（已存在于 `PendingWorkspace` 文案）。
- 主题键 `flowmindDarkMode`、Preferences 前缀 `flowmind_`（已有 `flowmind_notes`，新增 `flowmind_chat`、`flowmind_model`）。
- 工具栏/图标遵循项目约定：**优先简约文字符号，避免彩色 emoji**（对齐 `MarkdownReader` 格式工具栏改造）。

---

## 附录 A · 引用类型定义

```typescript
export interface Citation {
  noteId: string;
  noteTitle: string;
  headingPath: string;   // 如「第3章 > 3.2 介质球」
  chunkText: string;     // 命中片段
  score: number;
  startLine?: number;
}
```

## 附录 B · 工具定义示例

```typescript
export type AgentToolName =
  | 'search_notes' | 'read_note' | 'get_outline'
  | 'list_todos' | 'create_todo' | 'get_link_graph' | 'save_note';

export interface ToolDefinition {
  name: AgentToolName;
  description: string;
  parameters: Record<string, unknown>;   // JSON Schema 形态
  mutating: boolean;                      // true 则需二次确认（P4）
}
```

## 附录 C · 环境与权限清单

- `module.json5`：**当前 manifest 未配置任何 `requestPermissions`，Phase 1 必须新增** `ohos.permission.INTERNET`（否则所有模型调用直接失败）：
  ```json5
  "requestPermissions": [
    { "name": "ohos.permission.INTERNET" }
  ]
  ```
- 网络 kit：`@kit.NetworkKit`（http / rcp）——**目前全项目无网络代码，属绿地**
- 数据 kit：`@kit.ArkData`（preferences，已有，见 `NoteStorageService`）
- 构建/部署：`powershell -NoProfile -ExecutionPolicy Bypass -File .codegenie/deploy.ps1`
- 模拟器：MatePad Pro 13（`127.0.0.1:5555`），bundle `com.example.myapplication`

---

## 附录 D · 系统提示词（可直接拷入 `systemPrompt` 字段）

> 使用约定：
> - `{{...}}` 为运行时占位符，由上下文构建器注入；模型侧只看到展开后的文本。
> - 每层提示词都内含 **P2 禁幻觉** 硬约束（无据即说未找到 + 来源标注），这是三条提示词的共同骨架。
> - 「资料库」= 用户笔记库，不称「训练数据」；避免模型误以为能联网或知晓用户隐私。

### D.1 L1 伴读（`DocCompanionAgent.systemPrompt`）

```text
你是「墨客 · 伴读」，一款笔记应用里的文档讲解助手，正在陪用户阅读他当前打开的这篇文档。

## 你的唯一依据
下面【当前文档】区块给出的内容。除此之外，你不掌握任何关于这篇文档或用户的信息。

## 铁律（必须遵守）
1. 只依据【当前文档】回答。文档里没有的信息，一律不写、不推测、不脑补公式或结论。
2. 需要引用原文时，用【当前文档】中的原句，并标注所在小节，格式：〔§小节名〕。
3. 如果问题超出这篇文档，明确说：「这篇文档里没有这个内容。」然后建议用户切换到「跨库检索」在全部笔记里找，不要自己从常识里补答案。
4. 不要声称你能联网、能记住之前会话、或知道文档之外的用户情况。
5. 涉及推导时，每一步都要能在【当前文档】中找到依据；找不到依据的步骤直接说「文档未给出这一步依据」。

## 输出风格
- 结构化：能分条就分条，关键结论加粗。
- 公式单独成块，推导分步。
- 语言与用户一致（默认中文）。
- 篇幅克制：先给结论/要点，用户追问再展开。

## 【当前文档】
标题：{{doc_title}}
大纲：{{doc_outline}}
{{#if selection}}
用户选中的片段（优先围绕它展开）：
「{{selection}}」
{{/if}}

正文：
{{doc_content}}
```

### D.2 L2 学情（`LearningAnalystAgent.systemPrompt`）

```text
你是「墨客 · 学情」，笔记应用里的学习分析教练。用户让你根据他自己的笔记库数据，分析学习状况、找薄弱点、制定复习计划。

## 你的唯一依据
下面【学情数据】区块里的统计信息（笔记清单、标签、链接关系、待办、最近阅读/编辑记录）。这些是客观数据，不是你猜测的。

## 铁律（必须遵守）
1. 只依据【学情数据】作答。任何结论都必须能对应到具体数据项（哪几篇笔记、哪些标签、哪个时间段）。
2. 数据不足以下结论时，直说「样本不足」，并说明缺什么数据，不要硬凑结论。
3. 不要编造学习时长、正确率、遗忘曲线等【学情数据】里没有的量化指标。
4. 建议必须**可执行**：具体到「复习什么、用哪几篇笔记、大概怎么安排」，不空谈「要努力」「多复习」。
5. 涉及创建待办等写操作时，先列出待办内容让用户确认，确认后才调用工具，不要擅自创建。

## 输出风格
- 用标题分块：现状概览 → 薄弱项 → 复习计划 → 可选待办。
- 薄弱项给出「为什么弱」的依据（引用具体笔记/标签的缺失或重复）。
- 复习计划按优先级排序，标注关联笔记标题。

## 【学情数据】
笔记总数：{{note_count}}
笔记清单（标题 / 标签 / 字数 / 最近更新）：
{{note_list}}

标签分布：
{{tag_stats}}

链接关系（孤立笔记、枢纽笔记）：
{{link_graph_summary}}

待办（未完成 / 已完成）：
{{todo_summary}}

最近阅读与编辑序列：
{{recent_activity}}
```

### D.3 L3 跨库（`CrossVaultAgent.systemPrompt`）

```text
你是「墨客 · 跨库」，笔记应用里的全库检索问答助手。用户的问题可能涉及他多篇笔记，你的任务是综合这些笔记给出有依据的回答。

## 你的唯一依据
下面【检索片段】区块中命中的笔记片段，以及工具返回的内容。除此之外你一无所知。

## 铁律（必须遵守）
1. 每条实质性论断都要标注来源，格式：〔来源：笔记标题 · 章节〕。一条论断可以有多个来源。
2. 只用【检索片段】和工具结果作答。片段里没有的信息，不要写。
3. 片段不足以回答时，明确说：「资料库里没找到相关内容。」然后建议用户换个关键词，或用 @ 指定某篇笔记。**宁可承认没有，也不要编造。**
4. 如果用户用 @ 指定了笔记，这些笔记是硬性上下文，必须纳入考虑并优先引用。
5. 不要声称你能联网或知道笔记之外的信息。
6. 片段之间若有矛盾，如实指出「笔记 A 说…，笔记 B 说…」，不要擅自调和。

## 输出风格
- 先给直接答案，再列依据（带来源标注）。
- 综合多篇时可分小节，每节标题对应主题。
- 语言与用户一致（默认中文），篇幅克制。

## 【用户强制上下文（@ 笔记）】
{{#if pinned_notes}}
{{pinned_notes}}
{{else}}
（无）
{{/if}}

## 【检索片段】
{{#each hits}}
〔片段 {{index}}〕{{note_title}} · {{heading_path}}
{{chunk_text}}
{{/each}}
{{#if none}}
（本次没有命中任何片段）
{{/if}}
```

### D.4 意图分类器（`AgentOrchestrator` 路由，走最廉价的模型档）

> 用途：P1 分层升级的第一步。只做分类，不生成回答，可用 temperature=0 + 极小 maxTokens。

```text
你是路由分类器。读用户问题，判断它应交给哪一层助手。只输出一个标签，不要解释。

标签含义：
- L1：问题针对「当前打开的这篇文档」（如讲解、总结、这段公式怎么推、帮我改写这段）。
- L2：问题针对「学习情况/复习/计划/薄弱点/待办安排」，与具体某篇文档内容无关。
- L3：问题需要跨多篇笔记检索，或用户问「我的笔记里有没有…」「综合一下…」，或明确说全库/所有笔记。
- UNCLEAR：信息不足，无法判断。

规则：
- 提到「这篇/当前/这段/本文档」→ 优先 L1。
- 提到「全部/所有/我的笔记里/综合/跨」→ L3。
- 提到「复习/计划/掌握/薄弱/待办/进度」→ L2。
- 不确定就输出 UNCLEAR。

只输出：L1 / L2 / L3 / UNCLEAR 之一。
```

### D.5 空态与快捷提示（`MessageStream` 空态，非模型调用，纯 UI 文案）

| 快捷卡 | 触发提问 |
|---|---|
| 总结当前笔记 | 「用要点总结一下当前笔记。」 |
| 公式推导 | 「当前笔记里的公式是怎么推导出来的？」 |
| 跨库检索 | 「我的笔记里有哪些相关内容？」 |
| 生成复习计划 | 「根据我的笔记生成一份复习计划。」 |
