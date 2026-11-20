# 学习结果交换与离线演示

1.2.0 的「复习 → 学习结果」接入了电脑端工具的便携结果。电脑端按用户选择调用云模型 API，鸿蒙端通过 TXT／JSON 交换、核对引文与采纳题卡。使用云模型生成时，电脑需要联网和供应商 Key。

需要直接在阅读器中演示时，使用 [DevEco 模拟器联调](../cloud/ai/README.md#deveco-模拟器联调)。显式开启的 Debug HAP 会显示「学习助手」，可对当前资料做问答、选页摘要和周报，复用同一套 v1 结果与引文校验。手机在「资料原文」与「学习助手」间切换，平板并排查看。收起助手后，当前资料的结果在阅读会话中保留。发送前预览具体片段和页码或行号，返回结果支持分节阅读、定位原文和保存为带出处的本地笔记。DOCX、PPTX 导入后的文字版走 Markdown 原文行号链路。

## 能力与边界

| 层次 | 已实现 | 接入前仍需完成 |
| --- | --- | --- |
| 独立原型 | 五类任务、预览确认、引用校验、人工采纳、结果文件导出、工作区备份 | 真实模型效果与运行环境验证 |
| 交换契约 | `moyu.learning-result` v1、128 KiB 上限、结果与出处 | 后续版本显式迁移；旧客户端拒绝未知版本 |
| 原生文件接入 | 有界读取、版本／字段／引用校验、五类结果预览、匹配时回到原文、同一资料内逐张采纳 | 手机／平板回跳和持久化实测，跨资料题卡的引用模型 |
| 本地基础能力 | 资料研读、手动创建题卡与自测复习 | 后续改动按设备验证 |
| 1.1.1 本地复习增强 | 阅读与自测概况、弱项筛选、到期弱项优先、题卡编辑 | 手机与平板的实际使用验证 |
| 在线业务 | 保留技术设计 | 服务鉴权、凭据、隐私、费用、限额、取消与设备验证 |

格式通过不证明答案正确，也不证明文件来自可信服务。两端协议校验与真实模型质量是两项独立证据。

## 离线命令

在仓库根目录运行：

```powershell
python -X utf8 -m cloud.ai.moyu_ai capabilities
python -X utf8 -m cloud.ai.moyu_ai job export "已采纳任务ID" "tmp/result.json" --portable
python -X utf8 -m cloud.ai.moyu_ai validate-result "tmp/result.json"
```

`capabilities` 返回本实现声明的版本、任务类型、文件上限与关闭状态，不探测服务可用性。`validate-result` 只读指定文件并输出摘要；这两个命令不创建或打开工作区，不调用模型。

导出前仍检查任务已采纳、所选资料和记忆未过期，目标文件已存在时拒绝覆盖。`--portable` 仅允许 JSON；不带此选项的 `.json` 仍为完整任务快照，不能交给结果校验器。备份数据库、学习结果和主应用资料备份是三种不同格式，不自动互相转换。

## v1 字段

JSON 使用 UTF-8，无 BOM。所有对象执行字段白名单检查，不接受额外工具、路径、凭据或本地笔记身份字段。生产者必须输出唯一对象键；读取器使用标准 JSON 解析语义，不将原始 JSON 字节用作签名或确认摘要。

| 字段 | 内容与约束 |
| --- | --- |
| `format`／`version` | 固定 `moyu.learning-result`／数值 `1` |
| `job_id` | 1–80 个字母、数字、下划线或连字符；原型任务标识，不是本地笔记 ID 或可信来源证明 |
| `operation` | `summary`、`qa`、`quiz`、`report`、`plan` |
| `title` | 1–200 UTF-16 单元 |
| `sources` | 1–12 个片段；唯一 `id`、资料名 `name`、片段 `text`、资料 `revision`、全文 `digest`、`line_start`／`line_end` |
| `sections` | 1–8 节，每节 `heading`、`body`、`citations` |
| `cards` | `quiz` 为 1–8 张，其他任务为空；每张 `question`、`answer`、`citations` |
| `warnings` | 0–16 条提示，每条不超过 1000 UTF-16 单元 |

来源 ID 上限 100，名称 480，片段 2400，段落标题／问题 300，正文／答案 4000，均按 UTF-16 单元计数；有效补充平面字符如部分 emoji 占两个单元。整数范围为 1–2147483647，布尔值不能代替数字。无效 Unicode、空白文本、反向行号、重复来源、越界引用、类型与任务不符均拒绝；整体含空白的文件字节数不得超过 128 KiB。超限时明确失败，不截断问题或出处。

`citations` 为 1–6 个 `{source_id, quote}`，引文为片段中连续的 4–480 UTF-16 单元。行号指向导入文本片段，不能当作 PDF 页码。全文摘要仅验证 64 位小写 SHA-256 十六进制格式：交换文件没有全文，客户端无法仅凭片段复算全文摘要；该字段不是签名，也不证明资料真实或当前有效。

交换结果不携带系统提示词、请求配置、端点、API key、记忆表、完整消息或用量账单。但是片段、资料名和生成结果本身仍含学习内容；生成正文也可能转述用户此前主动携带的学习记忆。文件为明文，字段缩减不等于匿名化。

## 原生端适配

`LearningResultFile` 负责有界读取和 UTF-8 校验，`LearningResultPolicy` 负责协议验证与出处定位。预览与所选资料暂存在进程内，从原文返回复习页后可继续查看，直到清除、替换或退出应用。

- `parse(raw)` 校验 JSON、字节上限、所有字段与引用，返回结果对象；文字仍需按普通文本或现有安全 Markdown 规则展示，不执行链接、HTML 或代码。
- `cardDraft(raw, index, sourceId, selectedText)` 重新解析结果，要求指定来源片段与用户当前选中的本地文字逐字一致，并要求该题卡所有引用均来自该片段，才返回 `ReviewDraft`。
- 用户显式选中现存资料后，原生端用唯一的逐字片段定位 TXT／Markdown 行或本机已校对 PDF 页。交换文件的文件名、全文摘要和行号不赋予本地资料身份。PDF 页码来自本机文字索引。片段缺失或在同一资料中有多个可能位置时，界面保留引文，不提供跳转。
- 采纳时在写入队列内重新核对所选资料与全部引文。题卡绑定到一份本机资料。PDF 题卡的引用必须都在同一页。同一资料和同一草稿的重复采纳只保存一张卡。生成标记和原引文随题卡编辑、复习与备份保留。已采纳题卡回跳时也会重新核对引文。

多来源回答可以逐份选中本机资料核对。跨资料题卡仍可预览。摘要、问答、报告和计划可以通过电脑端导出 Markdown。

## 使用云模型 API 演示

1. 在鸿蒙设备导入示例 PDF 或 TXT／Markdown。PDF 从阅读器选择「PDF 文字与来源」，提取并校对一页。进入「复习 → 学习结果」，选中该资料，导出该页或文本资料到 TXT。
2. 把 TXT 传到装有 Python 3.10+ 的电脑。给所选供应商配置环境变量。下面用 DeepSeek 演示，也可以选择其他[已适配供应商](../cloud/ai/README.md)。

```powershell
python -X utf8 -m cloud.ai.moyu_ai notebook create "演示"
python -X utf8 -m cloud.ai.moyu_ai source add "演示" ".\导出的原文.txt" --name "演示资料"
$job = python -X utf8 -m cloud.ai.moyu_ai job prepare "演示" --source "演示资料" --operation quiz --goal "根据原文生成带出处的复习题" --provider deepseek --model deepseek-flash | ConvertFrom-Json
$job.payload.messages | ConvertTo-Json -Depth 20
```

核对实际发送内容，再运行。要演示带出处问答，把 `quiz` 换成 `qa`，并在目标里使用原文关键词。

```powershell
python -X utf8 -m cloud.ai.moyu_ai job run $job.id --approve $job.preview_digest
python -X utf8 -m cloud.ai.moyu_ai job show $job.id
```

核对后接受，再导出并传回鸿蒙设备。

```powershell
python -X utf8 -m cloud.ai.moyu_ai job accept $job.id
python -X utf8 -m cloud.ai.moyu_ai job export $job.id ".\moyu-demo-result.json" --portable
```

3. 在「学习结果」打开 JSON 并选择原资料。点击引文回到原 PDF 页／Markdown 行。返回「复习 → 学习结果」，采纳题卡，进入「开始复习」。现场可带一份预先真实生成并可回溯的 JSON 备用。切到备用文件时在演示里说明生成时间。

## 阅读链路验收

| 路径 | 真机检查 |
| --- | --- |
| PDF 文字层与扫描页 | 使用文本 PDF 和扫描 PDF，分别验证原文首屏、快速前后翻、单页／连续模式、双文档切换、OCR 校对与引用回到真实页。 |
| Markdown／TXT | 用长文档验证首屏、快速滚动、目录定位、从结果预览冷启动跳到后半段、编辑后回到阅读。 |
| PNG／JPG／WebP 与其他支持的图片 | 验证缩放、横竖切换、笔迹保存、退出重开和文件读取失败提示。 |
| 回退和保存 | 换错误资料、修改被引正文、移除已校对页或重复打开结果。观察旧引用是否停止跳转，重复采纳是否仍只有一张，失败后是否可重试。 |

观察首屏耗时、快速回翻是否再次停在加载态，以及内存是否在多轮翻页后稳定。手机和平板分别记录机型、系统版本、文件大小、页数与实测现象。

## 验证与后续接入

[共享契约样本](../tools/fixtures/learning-result.json)使用自编内容，Python 与 ArkTS 回归读取同一组成功／失败场景，覆盖五类任务、版本、非法字段、Unicode、行号、引用和结构。另测采纳条件、资料过期、防覆盖、字段最小化、独立校验无网络及本地片段匹配。样本摘要是测试占位值。

运行 `node tools/verify-ai.mjs` 与 `node tools/verify-workflows.mjs`。正式构建仅验证当前生产可达模块；准备层另通过 `entry@ohosTest` 测试目标编译。测试包编译成功不等于在设备执行，测试包不用于用户发布。

模拟器演示版的「助手」支持多轮对话，发送时经电脑网关提交问题和有限的近期对话。它可以将已完成的对话保存为本机 Markdown。基于资料的 DeepSeek Agent 仍从阅读器进入，可核对引用并跳到原文。验证时检查重新配对、停止等待后的迟到响应、跨页面保留对话和原文回跳。流式回复、跨资料证据持久化、交互引用笔记和音频概览继续在规划中。正式在线能力的接入条件见[云服务技术方案](CLOUD_AI_DESIGN.md)。

JSON 编码和跨语言处理参考 [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259)；上游学习工具的研究与复用边界见[参考记录](AI_REFERENCES.md)。
