# 墨语云模型工具

电脑端的 Python CLI 负责资料检索、请求预览、云模型调用、引文核验与结果导出。可选 MCP 服务向 Agent 提供同一套工作流。鸿蒙通过「复习 → 学习结果」打开便携 JSON，通过已核对的本机文字回跳和采纳。工作区与鸿蒙应用数据分开。

## 供应商配置

CLI 需要 Python 3.10+ 和标准库 SQLite。模型名称由使用者从供应商账号可用的、支持 JSON 输出的模型中选择。生成走非流式 Chat Completions。

| `--provider` | API Key 环境变量 | 默认 Base URL |
| --- | --- | --- |
| `deepseek` | `DEEPSEEK_API_KEY` | `https://api.deepseek.com` |
| `qwen-cn` | `DASHSCOPE_API_KEY` | `https://dashscope.aliyuncs.com/compatible-mode/v1` |
| `qwen-intl` | `DASHSCOPE_API_KEY` | `https://dashscope-intl.aliyuncs.com/compatible-mode/v1`（新加坡） |
| `openai` | `OPENAI_API_KEY` | `https://api.openai.com/v1` |
| `compatible` | `MOYU_AI_API_KEY` | 由操作者通过 `--base-url` 指定可信 HTTPS 云端点 |

百炼工作空间域名可通过 `--base-url` 选择，模型、端点和 Key 必须属于同一区域。OpenAI 使用 `max_completion_tokens`，其余预设使用 `max_tokens`。兼容端点须支持 `response_format: json_object` 和 `max_tokens`，Base URL 末尾由工具追加 `/chat/completions`。不同供应商使用各自的 Key。切换端点、供应商或模型时创建新任务并重新核对发送预览。

密钥从电脑进程环境读取。工作区记录供应商、端点、模型、发送内容、草稿及可用的 Token 用量。Key 仅随 HTTPS 请求头发送。选定文字及问题由对应云供应商处理，可能产生费用。请求使用系统证书校验并禁用重定向、环境代理和自动重试。空白 JSON、截断、拒绝和工具调用均视为生成失败。

[DeepSeek 接口](https://api-docs.deepseek.com/) · [百炼端点与区域](https://help.aliyun.com/en/model-studio/base-url) · [OpenAI Chat Completions](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)

## DevEco 模拟器联调

模拟器里的墨语负责原文阅读、范围选择、发送预览、引文回跳和本地笔记。电脑上的 Python 网关提供模型列表，转发已确认的文字和问题，调用选定模型并核验返回的引文。网关与 CLI、MCP 共用供应商适配和结果契约。

1. 在电脑上配置 `DEEPSEEK_API_KEY`，并确保运行网关的终端能读取该环境变量。在仓库根目录启动 Python 3.10+ 网关。

   ```powershell
   python -X utf8 -m cloud.ai.moyu_ai.simulator_gateway
   ```

   如果 Windows 的 `python` 指向 Microsoft Store 启动别名，可使用本机已安装的 Python 路径。有 Codex 附带的 Python 时，可用以下命令。

   ```powershell
   & (Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe') -X utf8 -m cloud.ai.moyu_ai.simulator_gateway
   ```

2. 保持网关终端打开。另开终端，从仓库根目录构建演示 HAP，按平时的签名和安装方式部署到 DevEco 模拟器。下列命令仅在本次 Debug HAP 构建中添加网络权限。切换回常规构建时重新清理再构建，避免沿用上一次的产物。

   ```powershell
   .\build_hap.bat -BuildMode debug -StudyDemo -Clean
   ```

3. 从侧栏或底栏进入「AI 墨客」，输入网关终端显示的配对码并选择模型。打开 PDF 或 Markdown／TXT 后，也可从阅读器顶栏或分屏选择中进入「AI 伴读」。两个入口共享当前配对。伴读支持问答、摘要和周报，发送前可核对原文范围。PDF 可先用「提取待校对页」。点回答的引用跳到原文后，可以用「返回原位置」回到刚才阅读的页或段落。

模拟器通过 `10.0.2.2:8765` 访问电脑的回环地址。网关只监听 `127.0.0.1:8765`，每次启动生成新配对码。模型密钥只在电脑进程环境中，网关不保留学习内容和会话。已确认的文字和目标会送给指定的云服务，可能产生 API 费用。默认列出两款 DeepSeek 模型，可重复指定 `--model` 来配置列表。切换供应商时重启网关并使用新的配对码。停止等待会关闭 App 的请求，网关已发出的请求可能继续完成。

阅读器内选择 DeepSeek 后，Agent 可以在一次工具调用轮次内检索已确认的片段，结果经过逐字引文核验。独立对话发送本次问题和最多六轮近期对话，合计最多 7000 个 UTF-16 单元。消息发送后立即显示，网关完成请求后显示完整回答。可停止等待、修改失败的问题或重试。新建对话后可从会话记录切回之前的对话，点「保存对话为笔记」可写入本机资料库。独立 MCP 工具提供笔记本检索、题卡与学习计划。

[DevEco 模拟器访问电脑网络](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides-V13/ide-emulator-access-network-V13/) · [DeepSeek JSON 输出](https://api-docs.deepseek.com/guides/json_mode/) · [DeepSeek 工具调用](https://api-docs.deepseek.com/guides/tool_calls/)

## 电脑端独立工具

在仓库根目录执行。先在操作系统中设置所选供应商的 Key，示例以 DeepSeek 为例。

```powershell
python -X utf8 -m cloud.ai.moyu_ai providers
python -X utf8 -m cloud.ai.moyu_ai notebook create "力学"
python -X utf8 -m cloud.ai.moyu_ai source add "力学" cloud/ai/examples/mechanics.md
$job = python -X utf8 -m cloud.ai.moyu_ai job prepare "力学" --source "mechanics.md" --operation quiz --goal "根据合外力和加速度生成自测题" --provider deepseek --model deepseek-flash | ConvertFrom-Json
$job.payload.profile
$job.payload.messages | ConvertTo-Json -Depth 20
```

课程资料支持 UTF-8 TXT／Markdown。PDF 页先在鸿蒙提取并校对，再通过「学习结果」导出 TXT。任务支持 `summary`、`qa`、`quiz`、`report`、`plan`。问答用目标中的原文关键词检索，未匹配时需要重新选段或改写问题。`--source` 可重复指定资料，`--limit` 控制保留片段数量。`--include-memory` 才会把本笔记本的学习记忆列入发送预览。

核对预览后发送，查看引用核验后的草稿。

```powershell
python -X utf8 -m cloud.ai.moyu_ai job run $job.id --approve $job.preview_digest
python -X utf8 -m cloud.ai.moyu_ai job verify $job.id
```

确认草稿后采纳并导出便携文件。导出路径需要尚不存在。

```powershell
python -X utf8 -m cloud.ai.moyu_ai job accept $job.id
python -X utf8 -m cloud.ai.moyu_ai job export $job.id ".\moyu-demo-result.json" --portable
python -X utf8 -m cloud.ai.moyu_ai preview-result ".\moyu-demo-result.json"
```

将 JSON 传回鸿蒙，在「复习 → 学习结果」中选择原资料并打开结果。`preview-result FILE --source ID FILE` 可在电脑端绑定原文，核对该文档全文摘要、切片和行号。来源状态为 `unmapped`、`verified`、`digest_mismatch` 或 `slice_mismatch`，后两种返回退出码 1。引文核验证明引用存在，答案中的推论仍需对照原文核对。鸿蒙端操作见[学习结果交换](../../docs/LEARNING_INTEGRATION.md)。

## Agent 工具（MCP stdio）

CLI 与 MCP 共用任务状态与资料库。为 MCP 安装可选 SDK，单独为每个需要访问的笔记本配置一个进程。

```powershell
python -m pip install -r cloud/ai/requirements-mcp.txt
```

在 MCP 客户端配置本机 **stdio** 命令。将工作目录设为仓库根目录。若客户端过滤子进程环境，只传递当前要用的供应商 Key 环境变量名。

```text
command: python
args: -X utf8 -m cloud.ai.moyu_ai.mcp_server --notebook 力学
```

CLI 和 MCP 默认使用 `cloud/ai/.data/`。如果使用 `--workspace`，两端指定同一目录。建议用演示笔记本接 Agent，检索与预览结果可能被 Agent 宿主处理。

| 工具 | 行为 |
| --- | --- |
| `list_sources` / `search_sources` | 列举已导入资料，返回匹配片段和行号 |
| `prepare_learning_job` | 用明确指定的资料和内置供应商配置创建发送预览 |
| `inspect_learning_job` | 查看当前笔记本内的发送预览、状态和草稿 |
| `run_authorized_job` | 消耗一份外部授权后调用云 API |
| `verify_learning_job` | 重新核对当前资料版本、结果字段和逐字引文 |

Agent 返回 `job_id`（任务对象的 `id`）后，用户在独立终端用 `job show` 查看完整预览，然后通过下面的命令授权一次：

```powershell
python -X utf8 -m cloud.ai.moyu_ai job authorize "<job_id>" --approve "<preview_digest>"
```

由 Agent 调用 `run_authorized_job`，用户用 CLI 采纳和导出。发送前检查任务预览摘要与资料版本。请求失败后生成新任务，已消费授权需要重新确认。通过 CLI 手动执行的 `job run` 可直接传入 `--approve`。[MCP Python SDK 迁移说明](https://github.com/modelcontextprotocol/python-sdk/blob/main/docs/migration.md)

## 数据与维护

- `moyu_ai/provider.py` 处理云 API 协议与鉴权。`tutor.py` 处理任务与引文。`mcp_server.py` 提供 Agent 接口。`simulator_gateway.py` 提供本机模拟器入口。`exchange.py` 定义和校验鸿蒙可导入的 v1 结果。
- 工作区是明文 SQLite。修改原始文件后，用同名资料重新导入以更新版本。移除资料或记忆之后，历史任务和导出文件仍需分别清理。
- 用 `workspace backup` 生成独立副本。备份会把待发送授权重置为待确认。旧 Ollama 草稿和已有导出仍可核对，旧待执行任务需要按新供应商重新准备。
- `node tools/verify-ai.mjs` 运行模拟 HTTP 与工作区测试。真实服务和 MCP 联调使用自己的账号、Key 和公开或授权的样本。
