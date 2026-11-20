# 墨语（RETEMPT/moyu）全方位项目优化方案

> 评估对象：[RETEMPT/moyu](https://github.com/RETEMPT/moyu)（HarmonyOS 手机/平板本地资料库与研读笔记应用，`v1.1.1`，`main` 分支）
> 文档日期：2026-11-20

本方案基于对仓库结构、[.gitattributes](https://github.com/RETEMPT/moyu/blob/main/.gitattributes)、[offline-pdf 目录](https://github.com/RETEMPT/moyu/tree/main/entry/src/main/resources/rawfile/offline-pdf) 以及 [services/ink](https://github.com/RETEMPT/moyu/tree/main/entry/src/main/ets/services/ink)、[services/study](https://github.com/RETEMPT/moyu/tree/main/entry/src/main/ets/services/study)、[services/document](https://github.com/RETEMPT/moyu/tree/main/entry/src/main/ets/services/document) 核心源码的全面审查整理而成。每一条优化项均提供事实依据、可直接落地的实现代码或配置、验收标准与官方参考资料。

## 执行总览与优先级路线图

| 编号 | 优化维度 | 优化项 | 优先级 | 预计工作量 | 涉及核心位置 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1.1 | 核心代码 | 修复荧光笔实时渲染透明度跳变 | P0 | 0.5 天 | [InkRenderer.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/ink/InkRenderer.ets) |
| 1.2 | 核心代码 | 消除 `getHistoricalPoints()` 空 `catch` 静默吞错 | P0 | 0.2 天 | [InkInputService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/ink/InkInputService.ets) |
| 4.1 | 仓库门面 | 补全 GitHub About、Topics 与 Social Preview | P0 | 0.2 天 | GitHub 仓库设置 |
| 4.2 | 仓库门面 | 配置 `.gitattributes` 排除 PDF.js 并映射 `.ets` | P0 | 0.1 天 | [.gitattributes](https://github.com/RETEMPT/moyu/blob/main/.gitattributes) |
| 1.3 | 性能优化 | PDF 位图 LRU 缓存升级为像素字节预算控制 | P1 | 1 天 | [PdfDocumentService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/document/PdfDocumentService.ets) |
| 2.1 | 数据安全 | 为 Fail-Closed 校验补齐“只读导出/隔离恢复”兜底 | P1 | 1 天 | [ReviewStorageService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/study/ReviewStorageService.ets) 等 |
| 3.1 | 工程构建 | 补充 `.sh` 跨平台构建脚本并将大产物迁至 Releases | P1 | 0.5 天 | 根目录脚本、`release/` |
| 3.2 | 兼容性 | 核查 API 24 强依赖边界并输出真机适配清单 | P1 | 0.5 天 | `build-profile.json5`、`README.md` |
| 5.1 | 产品体验 | 收敛离线版中“即将上线”的 AI 占位入口 | P1 | 0.5 天 | `views/`、`services/smart/` |
| 1.4 | 架构演进 | `LocalPdfEngine` 从脚本轮询演进为 `WebMessagePort` | P2 | 2 天 | [LocalPdfEngine.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/document/LocalPdfEngine.ets) |
| 2.2 | 存储演进 | `.flowmind.json` 单体 Base64 备份升级为 ZIP 容器 | P2 | 2–3 天 | [StudyBackupService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/study/StudyBackupService.ets) |
| 5.2 | 开源生态 | 补齐 Issue 模板与单元测试覆盖率基线 | P2 | 0.5 天 | `.github/`、`entry/src/test/` |

## 一、核心代码缺陷修复与性能优化

### 1.1 修复荧光笔实时渲染透明度跳变（P0）

**现状与依据**
在 [InkRenderer.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/ink/InkRenderer.ets) 中，`stroke()` 对荧光笔采用整条连续路径配合 `globalAlpha = 0.35` 绘制以避免分段叠加变深；但实时增量绘制方法 `segment()` 将 `ctx.globalAlpha` 固定写死为 `1`。

**问题分析**
用户使用荧光笔落笔拖动时，屏幕实时呈现的是 `alpha = 1` 的不透明色块，会遮挡下方 PDF 或文档文字；抬笔触发整笔重绘后，笔迹突然跳变为 `0.35` 半透明，造成明显的视觉割裂感。

**具体实现方案**
不要直接把 `segment()` 的 `globalAlpha` 改成 `0.35`（那会导致相邻线段连接处反复叠加变深）。推荐做法是利用 [InkFrameComposer.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/ink/InkFrameComposer.ets) 现有的离屏画布机制，将“当前正在书写的荧光笔活动笔画”单独重绘在透明前景层或每次清空活动层后以 `0.35` 整笔绘制，抬笔后再合入持久层：

```ts
// InkRenderer.ets：为活动中的荧光笔提供整笔预览绘制，避免分段叠加与透明度跳变
export function renderActiveStroke(
  ctx: CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D,
  points: ReadonlyArray<InkSample>,
  style: InkStyle,
  width: number,
  height: number
): void {
  if (points.length === 0) {
    return;
  }
  ctx.clearRect(0, 0, width, height);
  ctx.save();
  // 荧光笔统一在活动层整笔设置 0.35 透明度，与抬笔后的 stroke() 保持一致
  ctx.globalAlpha = style.highlighter ? 0.35 : 1;
  drawContinuousBezierPath(ctx, points, style);
  ctx.restore();
}
```

**验收标准**
* 荧光笔落笔拖动过程与抬笔落盘后的颜色、透明度完全一致，无肉眼可见的亮度/透明度跳变。
* 同一荧光笔笔画来回折返或缓慢拖动时，接头处不出现深色圆点叠加。

**参考资料**
* [MDN — CanvasRenderingContext2D.globalAlpha](https://developer.mozilla.org/zh-CN/docs/Web/API/CanvasRenderingContext2D/globalAlpha)
* [MDN — OffscreenCanvas](https://developer.mozilla.org/en-US/docs/Web/API/OffscreenCanvas)

### 1.2 治理 `InkInputService.ets` 空 `catch` 静默吞异常（P0）

**现状与依据**
[InkInputService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/ink/InkInputService.ets) 的 `read(event, fingerEnabled)` 在 `TouchType.Move` 分支中调用 `event.getHistoricalPoints()` 以获取高采样率轨迹点，但使用空的 `catch` 块包裹以兼容不支持该接口的设备。

**问题分析**
高频 `Move` 事件下，空 `catch` 既会吞掉非预期的运行时异常（例如系统升级后的接口变更或非法对象访问），也可能在不支持历史点的设备上每次移动都触发异常捕获开销。

**具体实现方案**
采用“运行时能力探测 + 降级标记 + 单次日志记录”替代空 `catch`：

```ts
// InkInputService.ets：避免高频 Move 重复抛错并保留排障可观测性
private historicalPointsSupported: boolean | undefined = undefined;

private readHistoricalPoints(event: TouchEvent): Array<HistoricalPoint> {
  if (this.historicalPointsSupported === false) {
    return [];
  }
  if (typeof event.getHistoricalPoints !== 'function') {
    this.historicalPointsSupported = false;
    return [];
  }
  try {
    const pts = event.getHistoricalPoints();
    this.historicalPointsSupported = true;
    return Array.isArray(pts) ? pts : [];
  } catch (err) {
    this.historicalPointsSupported = false;
    console.warn(`[InkInputService] getHistoricalPoints unavailable, fallback to primary touch point: ${String(err)}`);
    return [];
  }
}
```

**验收标准**
* 不支持历史点的设备仅在首次 `Move` 时打印一条告警日志，后续移动零异常开销。
* 支持历史点的设备采样率与手写顺滑度保持不变。

**参考资料**
* [RETEMPT/moyu — InkInputService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/ink/InkInputService.ets)

### 1.3 将 PDF 位图缓存升级为“像素字节预算 + 动态页数”LRU（P1）

**现状与依据**
[PdfDocumentService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/document/PdfDocumentService.ets) 当前使用固定常量 `PAGE_CACHE_LIMIT = 3` 管理渲染后的 `image.PixelMap` LRU 缓存。

**问题分析**
平板横屏或顶栏分屏场景下，用户可能同时看到 2 页内容并在相邻页之间高频回翻；固定仅缓存 3 页会导致滑过 2 页即淘汰刚看过的页面，引发重复渲染和闪烁。同时，不同分辨率 PDF 单页的 `PixelMap` 内存占用差异巨大，按页数限流无法精确控制内存上限。

**具体实现方案**
利用 HarmonyOS `PixelMap.getPixelBytesNumber()` 精确统计每页缓存占用的字节数，同时设置“最大字节预算（如平板 48MB、手机 24MB）”与“最大页数硬上限（如 6 页）”，并在淘汰时显式释放 `PixelMap`：

```ts
// PdfDocumentService.ets：基于字节预算与页数双阈值的 LRU 缓存
interface CachedPageEntry {
  page: RenderedPdfPage;
  bytes: number;
}

private readonly MAX_CACHE_BYTES: number = 32 * 1024 * 1024; // 可按设备形态动态配置（手机 24MB / 平板 48MB）
private readonly MAX_CACHE_PAGES: number = 6;
private cachedBytes: number = 0;
private pageCache: Map<string, CachedPageEntry> = new Map();

private putPageCache(key: string, page: RenderedPdfPage): void {
  if (this.pageCache.has(key)) {
    const old = this.pageCache.get(key)!;
    this.cachedBytes -= old.bytes;
    this.pageCache.delete(key);
  }
  const bytes = page.pixelMap.getPixelBytesNumber();
  this.pageCache.set(key, { page, bytes });
  this.cachedBytes += bytes;

  // Map 迭代顺序即为插入顺序，队首为最久未使用项
  while (
    this.pageCache.size > 1 &&
    (this.cachedBytes > this.MAX_CACHE_BYTES || this.pageCache.size > this.MAX_CACHE_PAGES)
  ) {
    const oldestKey = this.pageCache.keys().next().value as string | undefined;
    if (!oldestKey) {
      break;
    }
    const evicted = this.pageCache.get(oldestKey)!;
    this.pageCache.delete(oldestKey);
    this.cachedBytes -= evicted.bytes;
    evicted.page.pixelMap.release().catch(() => {});
  }
}
```

**验收标准**
* 平板快速上下翻阅 5 页以内的课程讲义时，缓存命中率显著提升且无重复白屏闪动。
* 连续浏览百页高分扫描件时，应用位图缓存常驻内存稳定控制在预算上限以内，无 OOM。

**参考资料**
* [HUAWEI Developer — Interface (PixelMap) / getPixelBytesNumber](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-image-pixelmap)
* [HUAWEI Developer — PDF Kit 简介](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/pdf-introduction)

### 1.4 将 `LocalPdfEngine.ets` 的 JS 轮询桥接演进为 `WebMessagePort` 事件通道（P2）

**现状与依据**
[LocalPdfEngine.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/document/LocalPdfEngine.ets) 通过 `PdfEnginePort.execute(script)` 注入脚本，并借助定时器与轮询管理异步请求（`PdfPending`）。

**问题分析**
脚本轮询在高频渲染或大页扫描件解析时会产生额外的跨线程桥接开销；在低端机上若单页解码耗时波动，固定轮询与超时策略容易触发误判超时。

**具体实现方案**
在 ArkTS 与 `entry/src/main/resources/rawfile/offline-pdf/host.mjs` 之间使用 `WebviewController.createWebMessagePorts()` 建立双向 `WebMessagePort` 通道，由 `host.mjs` 在 PDF.js 渲染/文本提取完成后主动 `postMessage` 回传 `requestId` 与结果（或错误码），彻底消除轮询定时器。

**验收标准**
* 取消 `LocalPdfEngine.ets` 中的轮询定时器，所有渲染与文本提取请求均由消息回调驱动完成。
* 在大体积 PDF 文本提取场景下，主线程 CPU 占用降低且不因固定轮询间隔产生额外延迟。

**参考资料**
* [HUAWEI Developer — 建立应用侧与前端页面数据通道](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/web-app-page-data-channel)
* [HUAWEI Developer — Interface (WebMessagePort)](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-webview-webmessageport)

## 二、数据安全与备份存储架构演进

### 2.1 为 Fail-Closed 校验补齐“只读导出 / 隔离恢复”逃生通道（P1）

**现状与依据**
[ReviewStorageService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/study/ReviewStorageService.ets)、[CanvasStrokePolicy.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/ink/CanvasStrokePolicy.ets) 和 [PdfAnnotationPolicy.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/document/PdfAnnotationPolicy.ets) 均实现了严谨的 Fail-Closed 策略：一旦检测到单条记录或快照损坏，直接拒绝加载并报错，防止下次自动保存覆盖原数据。

**问题分析**
Fail-Closed 避免了静默丢数，但如果设备异常断电导致某一条复习卡片或某页批注 JSON 受损，用户界面若只弹出“记录损坏，请先保留设备数据”的报错而没有自救入口，会导致整个复习模块或该文档陷入不可用状态。

**具体实现方案**
1. 保留现有 Fail-Closed 拒收逻辑，不在自动加载路径中静默丢弃数据。
2. 定义结构化错误类型 `CorruptedStorageError(domain, rawPayload, reason)`，由 UI 层捕获后弹出恢复对话框，提供两个显式操作：
   * **导出原始损坏文件**：调用 `DocumentViewPicker` 将原始 JSON 导出备份，便于开发者定位或用户保留证据。
   * **隔离并部分恢复（用户主动确认后执行）**：先将原始文件归档到 `files/quarantine/<domain>-<timestamp>.json`，再调用容错模式仅提取通过校验的合法记录重新写入主存储。

**验收标准**
* 人为构造一条非法 `ReviewCard` 写入存储后，应用能阻止自动覆盖并弹出恢复弹窗。
* 点击“导出原始数据”可完整导出损坏前的原始字节；点击“隔离并恢复”后其余正常卡片恢复可读，且原文件留存于隔离目录。

**参考资料**
* [RETEMPT/moyu — ReviewStorageService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/study/ReviewStorageService.ets)
* [RETEMPT/moyu — StudyRestoreService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/study/StudyRestoreService.ets)

### 2.2 将 `.flowmind.json` 单体 Base64 备份升级为 ZIP 容器格式（P2）

**现状与依据**
[StudyBackupService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/study/StudyBackupService.ets) 将笔记、复习卡片与 PDF/图片/封面附件经 Base64 编码后打包进单个 `.flowmind.json` 文件，当前限制单附件 `<= 16MB`、附件总计 `<= 22MB`、总备份 `<= 32MB`。

**问题分析**
Base64 编码会带来约 33% 的体积膨胀（22MB 二进制附件编码后约 29.3MB，紧贴 32MB 总上限，留给正文与元数据的余量不足 2.7MB）；更重要的是，导出与导入时需要把整个大字符串一次性序列化/反序列化，内存峰值高且难以支撑多本教材 PDF 的整库备份。

**具体实现方案**
引入版本号为 `2` 的 `.moyu-backup.zip`（同时保留对旧版 `.flowmind.json` 的只读兼容导入），利用 HarmonyOS 原生 `@ohos.zlib` 模块在沙箱临时目录组装并压缩：

```text
backup-staging/
  manifest.json          # 版本号、导出时间、SHA-256 校验和清单
  notes.json             # 笔记元数据与正文
  cards.json             # 复习卡片数据
  attachments/
    <assetId>.pdf        # 原始二进制文件，零 Base64 膨胀
    <assetId>.png
```

```ts
// StudyBackupService.ets：使用 @ohos.zlib 将临时目录打包为 ZIP 备份
import { zlib } from '@kit.BasicServicesKit';

async function packBackupDirectory(stagingDir: string, outZipPath: string): Promise<void> {
  const options: zlib.Options = {
    level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
    memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
    strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
  };
  await zlib.compressFile(stagingDir, outZipPath, options);
}
```

**验收标准**
* 同等 20MB PDF 附件集合的备份体积减少约 25%–33%，且不再受 32MB 单 JSON 字符串上限约束。
* 备份与恢复过程内存峰值显著下降，且旧版 `.flowmind.json` 仍可正常导入。

**参考资料**
* [HUAWEI Developer — @ohos.zlib (Zip模块)](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-zlib)
* [RETEMPT/moyu — StudyBackupService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/study/StudyBackupService.ets)

## 三、工程化构建、兼容性与仓库瘦身

### 3.1 补充跨平台构建脚本并将大体积产物迁至 GitHub Releases（P1）

**现状与依据**
仓库根目录目前仅提供 Windows 批处理脚本 `build_hap.bat` 与 `deploy_hap.bat`，且根目录包含 `release/` 与 `materials/`（含 `墨语项目展示.pptx`、`墨语项目说明与技术可行性.pdf`）。

**问题分析**
macOS 与 Linux 开发者（以及 CI 环境）无法直接复用 `.bat` 构建流程；同时，将二进制发布包与大型演示文档长期提交在 Git 主分支中会持续放大 `.git` 历史体积，拖慢 `git clone` 速度。

**具体实现方案**
1. 在根目录新增 `build_hap.sh` 与 `deploy_hap.sh`（赋予 `chmod +x`），与 `.bat` 保持参数一致：

```bash
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-release}"
hvigorw assembleHap --mode module -p product=default -p buildMode="$MODE" --no-daemon
echo "Build completed ($MODE). Check entry/build/default/outputs/default/"
```

2. 将 `release/` 下的构建产物统一托管到 [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)，并在 `.gitignore` 中忽略本地构建产物目录，避免后续版本迭代继续提交二进制包。

**验收标准**
* Windows、macOS、Linux 均可按 README 一条命令完成 HAP 构建。
* 后续发布新版本时主分支不再新增大体积二进制提交，全部挂载在对应 Tag 的 Release 附件中。

**参考资料**
* [GitHub Docs — Managing releases in a repository](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository)

### 3.2 评估最低 API 24 依赖边界并输出真机适配清单（P1）

**现状与依据**
README 声明项目最低 API 版本为 **API 24**，同时 [PdfDocumentService.ets](https://github.com/RETEMPT/moyu/blob/main/entry/src/main/ets/services/document/PdfDocumentService.ets) 已经通过 `canIUse('SystemCapability.OfficeService.PDFService.Core')` 做了运行时能力探测与回退。

**问题分析**
过高的最低 API 门槛会大幅收窄可安装的真机与模拟器范围，影响应用商店自然下载量及开源社区贡献者的本地复现意愿。

**具体实现方案**
1. 全面审计代码中实际调用的 API 最低版本要求，区分“必须强依赖的新 API”与“可通过 `canIUse()` 运行时降级的能力”。
2. 若核心读写、手写与离线 PDF.js 均可在更低 API 版本运行，尝试调低 `compatibleSdkVersion`，并在 README 中补充明确的《设备与系统版本兼容矩阵》（列出已验证的手机/平板型号、手写笔支持情况与已知限制）。

**验收标准**
* README 包含清晰的设备兼容表与构建环境要求，减少外部开发者的环境试错成本。

**参考资料**
* [HUAWEI Developer — pdfService 能力](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/pdf-pdfservice-implements)

## 四、GitHub 仓库门面与开源生态优化

### 4.1 补全 GitHub About、Topics 与 Social Preview（P0）

**现状与依据**
当前 [RETEMPT/moyu](https://github.com/RETEMPT/moyu) 首页右侧 About 栏为空（*No description, website, or topics provided.*），无社交分享封面图，社区数据为 2 Stars / 0 Forks / [0 Issues](https://github.com/RETEMPT/moyu/issues)。

**具体实现方案**
* **About 简介（推荐中英双语，控制在 350 字符以内）**：
  `墨语 (Moyu) — 面向 HarmonyOS 手机与平板的本地优先资料库与研读笔记应用。Local-first HarmonyOS note-taking & PDF study workspace with handwriting, bidirectional links, OCR, and offline spaced review.`
* **Topics（全小写、连字符分隔，控制在 10 个以内）**：
  `harmonyos`、`openharmony`、`arkts`、`pdfjs`、`note-taking`、`pdf-reader`、`knowledge-management`、`handwriting`、`local-first`、`offline-first`
* **Social Preview**：在 `Settings -> General -> Social preview` 上传一张 `1280×640` PNG 封面图（建议展示平板分屏阅读 PDF + 手写批注 + 双链图谱界面），并取消勾选未使用的 Packages / Environments，保留 Releases 展示。

**验收标准**
* 仓库主页右侧完整显示简介、Topics 与 `墨语 v1.1.1` Release 入口。
* 分享仓库链接至社交平台或文档时自动渲染高清项目封面卡片。

**参考资料**
* [GitHub Docs — Classifying your repository with topics](https://docs.github.com/articles/classifying-your-repository-with-topics)
* [GitHub Docs — Customizing your repository's social media preview](https://docs.github.com/en/enterprise-server@3.22/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/customizing-your-repositorys-social-media-preview)

### 4.2 精确配置 `.gitattributes` 排除 PDF.js 统计并映射 `.ets` 语言（P0）

**现状与依据**
仓库内置的上游 PDF.js 资源位于 [offline-pdf 目录](https://github.com/RETEMPT/moyu/tree/main/entry/src/main/resources/rawfile/offline-pdf)，导致 GitHub 语言统计显示为 **JavaScript 99.6%**、**Other 0.4%**，掩盖了以 ArkTS 为主体的真实代码结构。现有 [.gitattributes](https://github.com/RETEMPT/moyu/blob/main/.gitattributes) 仅配置了 `-whitespace`，尚未配置 Linguist 排除属性。

**具体实现方案**
直接覆盖根目录 `.gitattributes`（完整保留原有规则，精准排除上游 PDF.js，保留自研 `host.html` / `host.mjs`，并可选将 `.ets` 映射为 TypeScript）：

```gitattributes
# PDF offsets and image streams must keep their bytes across Windows and Linux checkouts.
*.pdf binary

# Historical checksums describe the preserved bytes, including original line endings.
archive/ai/** -text

# Preserve upstream PDF.js and license bytes; whitespace checks still cover our host adapter.
entry/src/main/resources/rawfile/offline-pdf/pdf.mjs -whitespace linguist-vendored
entry/src/main/resources/rawfile/offline-pdf/pdf.worker.mjs -whitespace linguist-vendored
entry/src/main/resources/rawfile/offline-pdf/**/LICENSE* -whitespace linguist-vendored

# Exclude remaining upstream PDF.js static assets from GitHub Linguist statistics.
entry/src/main/resources/rawfile/offline-pdf/cmaps/** linguist-vendored
entry/src/main/resources/rawfile/offline-pdf/iccs/** linguist-vendored
entry/src/main/resources/rawfile/offline-pdf/standard_fonts/** linguist-vendored
entry/src/main/resources/rawfile/offline-pdf/wasm/** linguist-vendored

# Map ArkTS (.ets) to TypeScript so GitHub Linguist counts core app source files.
*.ets linguist-language=TypeScript linguist-detectable=true
```

**验收标准**
* 提交并推送至 `main` 分支后，GitHub 仓库右侧 Languages 统计恢复以 TypeScript（代表 ArkTS 主体源码）为主，不再被上游 PDF.js 淹没。

**参考资料**
* [GitHub Linguist — Overrides Documentation (.gitattributes)](https://github.com/github-linguist/linguist/blob/main/docs/overrides.md)
* [RETEMPT/moyu — 现有 .gitattributes](https://github.com/RETEMPT/moyu/blob/main/.gitattributes)

## 五、产品体验与开源鸿蒙大赛交付打磨

### 5.1 收敛离线版中“即将上线”的 AI 占位入口（P1）

**现状与依据**
README 说明商店版本为纯离线版，但界面中保留了显示“即将上线”的 AI 功能入口；[services/smart](https://github.com/RETEMPT/moyu/tree/main/entry/src/main/ets/services) 已预留服务目录。

**问题分析**
在应用商店分发与竞赛现场演示中，无法点击或仅弹出“即将上线”的占位按钮会直接拉低产品完整度评分，甚至引发商店审核对“未完成功能”的驳回风险。

**具体实现方案**
1. 在编译配置或功能开关（Feature Flag）中新增 `ENABLE_CLOUD_AI = false`，离线商店构建默认隐藏未上线的云 AI 入口。
2. 如希望在离线版保留“智能辅助”亮点，可优先上线完全基于本地规则的轻量能力（例如基于 `StudySourceService` 已有正文提取的“本地关键词高亮 / 一键生成空白题卡模板 / 高频错题自动归集”），做到“入口即可用、承诺与实现一致”。

**验收标准**
* 离线正式构建包中不存在任何点击后仅提示“即将上线”的死入口。

### 5.2 建立 Issue 模板与测试覆盖率基线（P2）

**现状与依据**
仓库已包含 `entry/src/test`、`entry/src/ohosTest`、`entry/src/mock` 目录，但目前 [Issues](https://github.com/RETEMPT/moyu/issues) 为 0，且外部访客无法从 README 直观了解单元测试覆盖情况。

**具体实现方案**
1. 在 `.github/ISSUE_TEMPLATE/` 下新增 `bug_report.yml`（引导填写设备型号、HarmonyOS 版本、API 版本与复现步骤）和 `feature_request.yml`。
2. 针对高度纯函数化的 `*Policy.ets` 模块（`CanvasStrokePolicy`、`ReviewPolicy`、`LearningProgressPolicy`、`PdfAnnotationPolicy`）补全边界单测（含超大 JSON、损坏数据、夏令时跨日、空输入等），并在 README 中公开测试运行命令与通过结果。

**验收标准**
* 全部核心 `*Policy.ets` 具备可一键复现的单元测试用例，外部贡献者可通过标准模板高效提交反馈。
