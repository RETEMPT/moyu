# 依赖与素材核对

当前应用使用 HarmonyOS 的 ArkUI、ArkData、CoreFileKit、PDF Kit、CoreVisionKit 文字识别、Penkit、系统分享与设备连接能力。

应用没有广告、分析统计、第三方帐号或支付 SDK。本地规则排版与原文待办提取由工程内的 SourceTextStructure、SourceTextParser 和 LocalTextFormatter 完成；普通 Markdown、TXT 与 PDF 导入使用本地服务，系统 OCR 能力继续保留。范围以 [产品声明](../PRODUCT_SCOPE.md) 为准。

图标与封面为工程内自有素材，项目许可证为 MIT。示例资料仅用于调试，不包含在 release 包中。提交截图应使用自行创作或具有授权的资料。隐私与类别资质仍需按实际发布地区核对。

Koodo Reader 2.4.7（提交 `2ac731c5f6b2baa37da9db4c2bacd0c0519a7ae9`）用于交互和职责划分研究，本轮没有包含其源码、组件或资源，因此没有新增该软件的运行依赖。来源映射与后续代码复用边界见 [参考记录](../docs/KOODO_REFERENCE.md)。

Memos 提交 `1a51572406e1db3e97c24b2497013c8005e88317`（MIT）用于随手记、草稿、时间流及前后端契约研究；本轮未包含其源码和素材，未引入服务器依赖。两套参考均在上述记录中注明具体源文件。

独立 AI 原型仅依赖 Python 3.10+ 标准库（含 sqlite3），生成任务通过用户部署的 Ollama 服务调用实际模型。DeepTutor、learn-claude-code、Open Notebook、Filee 仅作为思路参考，没有复制代码、资源或引入其依赖，详见[来源与边界](AI_REFERENCES.md)。Ollama 服务与模型不随仓库或 HarmonyOS 安装包分发，模型权重许可需按用户实际选型另行核验。

## 离线 PDF 兼容组件

内置 [Mozilla PDF.js](https://github.com/mozilla/pdf.js/releases/tag/v6.4.299) 6.4.299 legacy 发行资产，采用 Apache-2.0 许可证。文件位于 `entry/src/main/resources/rawfile/offline-pdf`，保留原发行 LICENSE；仅打包核心模块、worker、字符映射、标准字体、Wasm 与 ICC 支持文件，不包含官方 viewer 或示例资料。`host.html` 和 `host.mjs` 为本项目适配代码。

来源为官方 `pdfjs-6.4.299-legacy-dist.zip`，下载包SHA-256：`c894bce53b2f4c3e13141e088c89cc051a1f7118ba4a2c02ec058798ae1303d1`。字符映射与字体版权声明保留。资源本机加载，宿主禁止网络，不新增互联网权限；设备运行和真实课本导入仍需验证，方法见[开发指南](DEVELOPMENT_GUIDE.md)。
