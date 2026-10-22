# 墨语独立 AI 学习实验

这是基于现有云AI设计实现的 Python 命令行原型，面向课程资料研读。它在独立工作区中管理资料、学习记忆和生成草稿，**没有接入 HarmonyOS 主软件，不进入 APP／HAP 构建**。

只需要 Python 3.10+ 及标准库 sqlite3。资料管理与检索无需模型、账号或网络；生成任务需要用户已经部署的 Ollama 服务与模型。当前没有托管服务、Web 界面、支付、消息推送或模型下载器。

## 能做什么

| 能力 | 当前实现 |
| --- | --- |
| 课程资料库 | 按笔记本隔离，批量导入 UTF-8 TXT、MD、Markdown；同名资料重新导入更新版本 |
| 带出处检索 | 中文字／双字词与英文词检索，保留原文片段、资料身份、SHA-256、版本和行号 |
| 学习记忆 | 用户主动记录知识点、学习状态与错题备注，可以查看、修改、删除；发送记忆需要显式选择 |
| 学习任务 | 摘要、资料问答、自测题卡、研究报告草稿、复习计划 |
| 可核对草稿 | 严格 JSON、逐字引文及范围校验；人工编辑、采纳，再导出 Markdown／JSON |
| 运行控制 | 完整发送预览、摘要确认、任务状态、放弃、迟到结果拦截、失败不自动重试 |

检索为词面检索，不是向量检索或知识图谱。引用校验证明引文存在于本次资料，不能证明答案正确。模型必须遵循结构与引用约定，不符合时任务失败，不静默采纳。

## 从仓库根目录开始

所有命令在仓库根目录运行；Windows 建议带 `-X utf8`，避免中文终端编码问题。

```powershell
python -X utf8 -m cloud.ai.moyu_ai --help
python -X utf8 -m cloud.ai.moyu_ai notebook create "力学"
python -X utf8 -m cloud.ai.moyu_ai source add "力学" cloud/ai/examples/mechanics.md
python -X utf8 -m cloud.ai.moyu_ai source search "力学" "加速度"
python -X utf8 -m cloud.ai.moyu_ai source list "力学"

# 主动记录一次薄弱点；不会依据模型回答自动判断掌握程度
python -X utf8 -m cloud.ai.moyu_ai memory set "力学" "向心加速度" --status review --note "混淆了速率和速度，复习时先解释方向变化"
python -X utf8 -m cloud.ai.moyu_ai memory list "力学"
```

这些命令不发起模型调用。默认数据目录为 `cloud/ai/.data/`，已被 Git 忽略；也可在每条命令的子命令之前加 `--workspace "自己的独立目录"`。例如 `python -X utf8 -m cloud.ai.moyu_ai --workspace "E:/study-ai" notebook list`。工作区包含单用户明文 SQLite 数据库 `learning.sqlite3`，使用专用数据库标识与版本；遇到其他数据库或未来版本会拒绝覆盖。

批量导入直接列出路径，每批最多 20 个文件，每个文件独立事务。部分失败会报告成功与失败项，进程退出码为 1；不撤销已成功导入的资料。`--name "稳定名称"` 可在单文件导入时指定资料身份；相同笔记本内同名内容相同则不变，内容变化才递增版本。不同文件同名时应先指定不同名称，避免把两份资料当作修订。

导入得到独立文字快照，不监视原文件。原文件修改后，需要重新导入才会更新资料版本。资料名称与本地文件路径不发送给模型，模型只收到片段代号、文字、任务目标，以及主动选择的学习记忆。

## 预览、生成与采纳

先自行部署 Ollama 并准备可用模型，具体安装按 [Ollama 官方说明](https://docs.ollama.com/quickstart)。把下面的 `your-local-model` 替换为实际模型名；本程序不会拉取模型或自动启动服务。

```powershell
$preview = python -X utf8 -m cloud.ai.moyu_ai job prepare "力学" --operation quiz --goal "加速度与速度方向" --include-memory --model "your-local-model" | ConvertFrom-Json
$preview | ConvertTo-Json -Depth 20
```

`prepare` 只检索和保存预览，不联网。核对 `payload.profile` 的地址／模型、`payload.sources` 的资料与行号、`payload.memories` 及 `payload.messages` 中的完整发送内容。问答没有词面匹配时拒绝创建；其他任务没有匹配时使用前几个片段，并全部列入预览。结果只覆盖选中片段，较长资料可按章节和目标分次处理，不能把片段摘要当成全文结论。

核对后，在下一步主动执行：

```powershell
python -X utf8 -m cloud.ai.moyu_ai job run $preview.id --approve $preview.preview_digest
python -X utf8 -m cloud.ai.moyu_ai job show $preview.id
```

`--approve` 必须与完整预览摘要一致。任务、资料版本或本次携带的记忆发生变化时，发送／采纳会拒绝继续，需要重新准备。操作可选 `summary`、`qa`、`quiz`、`report`、`plan`。默认最多 6 个片段，`--limit` 可设 1–12；单片段最多 1200 字符，总模型消息不超过 20000 字符；可用 `--max-output-tokens` 设置 128–4096 的输出上限。字符上限不等于模型 token 窗口，须按所用模型适当减小。

成功后状态是 `review`，尚未采纳。检查每节正文、答案和逐字引用后执行：

```powershell
python -X utf8 -m cloud.ai.moyu_ai job accept $preview.id
python -X utf8 -m cloud.ai.moyu_ai job export $preview.id "tmp/力学复习.md"
```

请先确保导出目录存在。导出仅支持 `.md`／`.json`，文件已存在时拒绝覆盖；不会写回主应用，也不会修改资料或自动创建主软件题卡。JSON 导出包含完整任务和原文快照，Markdown 包含整理结果与引用，均为明文。Markdown 中模型文本按普通文字转义，不执行链接、HTML 或代码。

需要修改草稿时，把 `job show` 输出的 `result.draft` 单独保存为 UTF-8 JSON，修改后用 `job revise`：

```powershell
python -X utf8 -m cloud.ai.moyu_ai job revise $preview.id --file "tmp/edited-draft.json"
```

编辑稿只包含 `title`、`sections`、`cards`、`warnings`；段落包含 `heading`、`body`、`citations`，题卡包含 `question`、`answer`、`citations`，引用包含 `source_id`、`quote`。每节与每张题卡均须提供 1–6 个引用，`quote` 是所选片段中连续的 4–240 字符；`quiz` 须有 1–8 张题卡，其他任务 `cards=[]`。只有 `review` 状态允许修改，修改后仍需人工采纳。

## 版本化结果与接入准备

完整任务 JSON 用于个人留存；需要验证两端交换时，使用只含结果与出处的 v1 格式：

```powershell
python -X utf8 -m cloud.ai.moyu_ai capabilities
python -X utf8 -m cloud.ai.moyu_ai job export $preview.id "tmp/learning-result.json" --portable
python -X utf8 -m cloud.ai.moyu_ai validate-result "tmp/learning-result.json"
```

导出要求任务已采纳且资料／所选记忆未过期。该格式不包含提示词、完整消息、端点或记忆表；资料片段、名称和生成内容仍为明文，正文也可能转述学习记忆。已有文件拒绝覆盖，超过 128 KiB 或字段限制直接失败。`capabilities` 是静态能力声明，`validate-result` 是离线结构与引文校验；两者不打开工作区、不联网，也不证明结果真实正确。

主程序仅准备了独立的结果校验与题卡候选转换代码，尚无导入或保存入口。五类任务结构、跨语言字符限制、源码隔离和后续接入条件见[学习结果交换说明](../../docs/LEARNING_INTEGRATION.md)。

## 状态、清理与故障

正常状态为 `prepared → running → review → accepted`；失败进入 `failed`，放弃进入 `abandoned`。只允许一个进程认领同一任务；不同任务没有全局调度或日预算。

```powershell
python -X utf8 -m cloud.ai.moyu_ai job list "力学"
python -X utf8 -m cloud.ai.moyu_ai job abandon "任务ID"
python -X utf8 -m cloud.ai.moyu_ai job delete "任务ID"
python -X utf8 -m cloud.ai.moyu_ai memory forget "力学" "向心加速度"
python -X utf8 -m cloud.ai.moyu_ai source remove "力学" "mechanics.md"
```

可从另一终端放弃正在运行的任务，返回的迟到结果不会保存。放弃／中断不能保证撤回已发送的远端推理或费用。网络失败、HTTP 429、结构错误均不自动重试；需要新建任务并重新确认。进程强制结束可能留下 `running` 状态，先放弃再新建，不自动重放旧请求。

删除资料／记忆只删除当前资料库记录；历史任务保留本次发送快照，已导出文件也会保留。需要清理历史原文或记忆时逐项 `job delete` 并处理自己的导出和备份。运行中任务须先放弃才可删除。数据库删除不是介质安全擦除；工作区与其副本需要按私人资料管理。

## 工作区备份与恢复

资料、记忆与任务保存在同一个 SQLite 数据库。备份使用 SQLite Online Backup API，包含已提交到 WAL 的数据，再执行完整性与外键检查；无需手工复制数据库旁的日志文件。备份命令不调用模型。

```powershell
python -X utf8 -m cloud.ai.moyu_ai workspace backup "tmp/learning-backup-20261022"
python -X utf8 -m cloud.ai.moyu_ai --workspace "tmp/learning-backup-20261022" notebook list
```

目标必须是尚不存在的新目录，父目录须已存在；已有目录（包括空目录和当前工作区）一律拒绝覆盖。成功返回 `verified: true` 和各表记录数。备份复制阶段等待超过 10 秒会中断；失败会清理本次创建的数据库和目录。如果进程被强制终止，可能遗留不完整目录，不应当作成功备份，换一个新目录重试。

快照若包含 `running` 任务则拒绝备份；请等待任务结束，或确认后主动放弃。该检查针对快照时刻，不会锁住后续任务操作。备份是独立副本，原工作区后续增删不会同步到副本。

恢复时先停止旧工作区的任务，保留原件，用 `--workspace` 指向备份目录检查资料和任务，再继续使用该副本；不提供原地覆盖恢复。副本保留任务状态及预览摘要，切换后应重新准备待发送任务，避免在两份工作区重复执行同一任务。备份不包含原始文件、导出文件、模型、环境变量或应用数据；资料文字和历史任务快照均为明文，需要单独保管，也不会随原工作区删除而消失。

## 模型与数据边界

当前仅实现 [Ollama `/api/chat`](https://docs.ollama.com/api/chat) 非流式 JSON 协议，包含 `model`、`messages`、`format`、输出上限与实际 token 用量读取。用量缺失显示 `null`，不估算账单或宣称免费托管。

默认端点为回环 HTTP；也支持用户指定的 HTTPS Ollama 服务根地址。HTTP 只允许 `localhost`、`127.0.0.1`、`::1`，禁止 URL 凭据、查询参数、额外路径和重定向，使用系统证书校验。程序直接连接端点，不读取系统代理配置。可选认证从环境变量 `MOYU_AI_API_KEY` 读取，仅 HTTPS 发送，不写入工作区；不用时请清除该变量。内网／远程部署的权限、模型是否依赖云服务及数据保留由用户所选服务决定，不能仅凭使用 Ollama 就推断资料始终留在本机。

每次请求最多读取 128 KiB 服务响应，草稿最多 32 KiB，网络套接字超时 60 秒，无自动重试。当前没有服务端鉴权、多租户、费用预留、任务队列、完整上下文自适配或模型效果基准，不能直接作为公开托管服务。

资料中的命令仅是待分析文字，原型不具备 shell、自动读取链接、脚本执行或主应用写入工具。输出仍需人工审核；原文引用真实存在也可能被曲解或无法支持结论。

## 参考与后续方向

本轮参考四个项目的公开说明，取其产品和工程思路，由本仓库独立实现，没有复制源码、素材或引入这些项目的运行依赖。来源与许可证见[参考记录](../../docs/AI_REFERENCES.md)。

- DeepTutor：显式学习记忆和围绕资料的辅导；本原型采用可修改的用户自述记忆。
- learn-claude-code：清晰的运行环境与执行边界；本原型采用有界任务状态机与独立模型适配。
- Open Notebook：按课题组织资料与结果；本原型采用课程隔离、带出处草稿和开放文件导出。
- Filee：本地预处理并保留原件；本原型只接收明确支持的文本格式，不声称具有其转换引擎。

后续按独立轮次评估 PDF／Office 提取、语义检索、多模型协议与音频脚本，再根据维护与验证条件扩展；当前没有播客合成、聊天平台提醒、255 种格式转换或通用编程智能体。主软件集成属于后续单独决策。

## 自动验证

```powershell
python -X utf8 -m unittest discover -s cloud/ai/tests -v
node tools/verify-ai.mjs
```

测试使用临时资料、真实 SQLite 和模拟模型传输，不调用真实模型、不产生推理费用。覆盖版本过期、学习记忆隔离与发送选择、伪造引用、重复发送、取消、输出上限、故障回滚、编辑采纳、导出防覆盖、清理和端点约束。统一入口 `node tools/verify-project.mjs` 也会运行此专项；支持用 `PYTHON` 指向含 sqlite3 的 Python 3.10+。
