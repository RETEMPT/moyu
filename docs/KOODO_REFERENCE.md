# Koodo Reader 与 Memos 双参考改造

参考源码核对日期：2026-10-17；文档口径更新：2026-10-22。当前视觉以Notion及首页参考稿为主，Memos用于本地记录行为参考。参考固定到 [Koodo Reader 2.4.7 的提交 2ac731c](https://github.com/koodo-reader/koodo-reader/tree/2ac731c5f6b2baa37da9db4c2bacd0c0519a7ae9)。项目仍使用 HarmonyOS、ArkTS、ArkUI 和本地文件服务，范围见[产品声明](../PRODUCT_SCOPE.md)。

另一核心参考为 [Memos 提交 1a515724](https://github.com/usememos/memos/tree/1a51572406e1db3e97c24b2497013c8005e88317)，历史记录提交日期为 2026-10-17（北京时间）。Koodo负责资料与阅读范式，Memos负责快速记录与时间流行为；整体视觉不再沿用Memos整页设计。本地功能映射与新增独立网站规划分别维护，网站不等于复现Memos服务端。

## 参考对应关系

| 源码证据 | 采用的设计 | 墨语实现 |
| --- | --- | --- |
| [书库列表](https://github.com/koodo-reader/koodo-reader/blob/2ac731c5f6b2baa37da9db4c2bacd0c0519a7ae9/src/containers/lists/bookList/component.tsx) | 书架／列表切换、真实结果数、分批展示、置顶优先、阅读状态过滤 | 资料库复用 LibraryPolicy，先展示 40 份；首页 MemoFeedPolicy 只展示文字记录，先展示 12 条，手动加载更多 |
| [排序面板](https://github.com/koodo-reader/koodo-reader/blob/2ac731c5f6b2baa37da9db4c2bacd0c0519a7ae9/src/components/dialogs/sortBookDialog/component.tsx) | 最近阅读与编辑日期分开，排序和方向可保存 | 最近打开／更新时间／创建时间／标题；书架模式与排序保存在独立显示设置中 |
| [资料行](https://github.com/koodo-reader/koodo-reader/blob/2ac731c5f6b2baa37da9db4c2bacd0c0519a7ae9/src/components/bookListItem/component.tsx) | 封面、资料身份和阅读进度相邻展示 | 使用现有统一封面；有页资料显示真实页码，无页资料仅显示“最近打开” |

上游源码用于研究交互、状态划分和职责。上述 ArkTS 服务及界面改动为本项目实现，没有导入上游 React／Electron 代码、资源、商标或新增其依赖。上游仓库的 [LICENSE](https://github.com/koodo-reader/koodo-reader/blob/2ac731c5f6b2baa37da9db4c2bacd0c0519a7ae9/LICENSE) 标识为 AGPL-3.0；以后若直接引入代码或资源，应单独记录来源并核对分发义务，不能仅保留本项目 MIT 声明。

## Memos 前后端参考对应

| 源码证据 | 采用的原则 | 墨语实现 |
| --- | --- | --- |
| [保存用例 useMemoSave](https://github.com/usememos/memos/blob/1a51572406e1db3e97c24b2497013c8005e88317/web/src/components/MemoEditor/hooks/useMemoSave.ts) | 保存流程独立于编辑器外壳；成功之后再清草稿、刷新列表 | QuickMemoService 提交普通 Markdown 笔记；正文和元数据完成后发布，失败保留草稿 |
| [草稿 useAutoSave](https://github.com/usememos/memos/blob/1a51572406e1db3e97c24b2497013c8005e88317/web/src/components/MemoEditor/hooks/useAutoSave.ts) | 草稿与已保存记录分开，离开时提交，清稿后不被晚到自动保存复活 | MemoDraftService 独立快照、500ms 合并输入、页面隐藏时提交；修订号阻止旧保存回报覆盖新状态 |
| [保存校验](https://github.com/usememos/memos/blob/1a51572406e1db3e97c24b2497013c8005e88317/web/src/components/MemoEditor/services/validationService.ts) | 空内容与重复提交在入口阻止 | 空白不可保存，提交期间锁定输入与按钮；稳定草稿 ID 支持幂等重试 |
| [API 创建与列表](https://github.com/usememos/memos/blob/1a51572406e1db3e97c24b2497013c8005e88317/server/api/memo_service.go)、[存储契约](https://github.com/usememos/memos/blob/1a51572406e1db3e97c24b2497013c8005e88317/store/memo.go) | 创建时间与更新时间分开、查询分页、写入及权限校验分层 | 时间流以创建时间倒序，编辑旧记录不顶到最新；条目分批显示；本地用例与保存适配分离 |

Memos 的 [LICENSE](https://github.com/usememos/memos/blob/1a51572406e1db3e97c24b2497013c8005e88317/LICENSE) 为 MIT。本轮同样没有复制其源码或引入其服务端。上游的多用户、权限、附件和事务边界不能因为阅读了接口就宣称已经在墨语实现；这些服务端能力也不属于当前去中心化范围。

主页新增随手记：无需填写标题，首行生成资料标题，Markdown 原文保留，正文标签由现有结构解析器提取，代码和公式中的标签不作为分类。保存结果仍是普通本机 Markdown 笔记，可以编辑、搜索、备份和加入项目。草稿单独保存，损坏时保留并阻止覆盖；首次启动资料未完成加载前不接受新草稿。

主页视觉已改为 Notion 文档工作台，保留本地记录的创建时间顺序；资料库的书架／列表／时间流直接显示。时间流只展示文字记录，使用真实创建时间和有限正文摘录，点击标签进入检索，不额外建立一套重复笔记数据库。没有创建时间的历史数据沿用现有启动迁移策略，不能把迁移补值当成真实历史日期。

## 已落地的前端改进

- 主页为居中窄时间流、置顶输入框、原生 Markdown 预览和独立记录菜单；日历与标签按真实创建日期及文字记录统计，组合过滤不修改资料。资料库模式与排序重启保留。
- 资料库展示匹配数／全库数，提供标签、类型和阅读状态过滤，可一键清除筛选。空资料库与无匹配结果有不同反馈。
- 类型入口只展示当前支持导入的资料类型；旧 Word 记录仍可在“全部”中访问。
- “继续阅读”依据最近打开记录，显示保存页码；从未打开的资料不会冒充阅读历史。页码表示到达位置，“已到末页”不等于完成学习。
- 原件缺失、阅读组件未就绪和文档损坏继续沿用已有分别反馈；不改写原件或已有笔迹。

## 已落地的服务改进

- `LibraryPolicy` 合并类型归一化、多标签、正文／校对页文字匹配及排序。`#标签` 专门搜索标签；普通关键词查标题、分类、正文、摘要和全部标签。搜索读取已装载文本，不在界面构建时重读原文件。全库高级搜索仍由 NoteSearchService 提供异步取消和结果定位。
- `lastReadAt`／`readPage` 与编辑时间分开；阅读提交只合并自身字段，保留新封面、分类、正文和笔迹，不重写 Markdown，也不重建图谱。
- 翻页记录合并 600ms 内的连续变化；退出等待已在途的位置保存。失败保留重试位置，旧事件不能覆盖较新记录。文档切换仍通过现有保存流程处理批注。
- 阅读位置在实际页数内恢复；旧数据没有阅读字段时正常打开。学习备份只保留有效阅读记录，不改变备份版本。
- 显示设置独立保存，写入成功后更新界面，失败回退缓存并提示。

## 清理与边界

本轮删除无入口引用的 `PdfAnnotationService.ets`、`TagSheet.ets`、12 个未调用私有方法和 6 份无运行时引用的 SVG；编译器查找集中到 `resolve-typescript.mjs`，`verify-project.mjs` 汇总检查。历史存档、设计证据、用户资料、原件以及 `tmp` 中的设备备份和性能证据均保留，不按“临时文件”一刀切删除。

## 验证与边界

完整入口：`node tools/verify-project.mjs --compiled`，编译后交互检查需要先完成本轮 release APP 构建。工具自动复用 DevEco 编译器，也支持 `--typescript` 明确指定。

Memos 相关回归覆盖原文保留、自动标题、代码内标签排除、保存顺序、失败不发布、草稿重启、损坏草稿保护、幂等重试与时间流排序；编译后交互检查验证编辑器按钮、显示方式和标签入口。

回归覆盖正文与校对页检索、组合筛选、不可变排序、阅读记录合并、失败不发布、显示设置恢复、备份边界和连续翻页。方法见[开发指南](DEVELOPMENT_GUIDE.md)，具体运行和设备记录本地维护，不把历史通过数作为当前结论。

EPUB／MOBI、用户自有存储同步、插件与外部处理服务尚未完成，已按用户最新要求进入[完整功能清单](FEATURE_PARITY.md)。资料／项目／回收站已接入鸿蒙事务型 RDB 快照仓储，旧数据保留。去中心化同步尚未实现：方向是设备密钥 + 端到端加密 + 操作日志／CRDT，传输使用附近、用户自有 WebDAV／S3／网络文件夹，以及未来可选的无账号加密中继；不建设中心账号或服务端权限。离线 PDF、8 份真实课本、关系数据库设备迁移、手机大字体和物理笔仍需设备证据；不能据编译或桌面检查宣称全部设备和跨文件持久化无问题。
