# 应用市场提交材料与验收

候选 1.0.2（1001002），包名 `com.retempt.flowmind`，最低系统配置 6.1.1(API 24)、目标 API 26。手机与 Pad 共用一个版本；GitHub 未签名开发发行不表示已上架。

## 填入真实发布资料

编辑 `app-market.json` 的公开字段：`publisher`、`supportEmail`、`privacyUrl`。发布者须与 AGC 和隐私说明一致。隐私咨询回复期限默认 15 个工作日，发布者需建立可执行的处理流程。禁止在此文件填写 Key、签名密码、证件或私钥。

执行 `node tools/generate-market-materials.mjs`，同步生成应用内说明、`docs/PRIVACY.md` 和 `site/privacy.html`。页面不依赖脚本、分析统计或服务端，可由现有静态托管服务承载。它是待托管文件；生成不表示已经拥有可用网址。填好主体后再托管，并核对网页与 APP 全文一致、公开链接稳定可访问。

商店介绍与审核操作见 [STORE_LISTING.md](STORE_LISTING.md)，依赖与素材见 [DEPENDENCIES.md](DEPENDENCIES.md)。真实截图清单写入 `app-market.json.screenshots`，每项格式：

```json
{ "device": "phone", "path": "release/evidence/phone-home.png", "appSha256": "本次签名APP的SHA256" }
```

`tablet` 另有对应项；这只是检查的最低覆盖要求，提交数量、格式与尺寸依当前 AGC 页面补足。不能使用 UI 设计稿或服务替身测试代替真实截图。

## 构建与检查

```powershell
# 使用当前工程对应的 DevEco Studio；模块和工程输出均清理
.\build_hap.bat -BuildMode release -AppPackage -Clean -StudioDir "<安装目录>"

# 服务逻辑测试（需本机 TypeScript 或 --typescript 指定 SDK 编译器文件）
node tools/verify-workflows.mjs
node tools/verify-app-market.mjs

# 只核验工程准备，缺失的账户/真机资料仍列为 BLOCKED
node tools/app-market-preflight.mjs --project-only --app "<APP路径>" --studio "<安装目录>" --report release/reports/preparation.json

# 正式提交前：默认严格模式，任何门槛缺失返回非零
node tools/app-market-preflight.mjs --app "<正式签名APP路径>" --studio "<安装目录>" --report release/reports/submission.json
```

签名在安全的 DevEco/AGC 环境中配置，工程当前 `signingConfigs` 为空。检查器不创建证书、不索取密码：解包 APP，校验实际模块身份、版本、权限、设备、备份与发布模式，调用安装 SDK 的 `hap-sign-tool verify-app` 验证每个 HAP。有效密码学签名还不等于有效市场发行身份，发布者仍需核对 AGC 发布证书和发布 profile。

正式包上传 AGC 之前，还需完成平台隐私/漏洞/兼容/性能测试，并保存结果。工程检查、服务测试和编译只证明其覆盖范围，不自动证明市场审核通过。首次市场签名与过去未签名开发包的身份可能不同，升级验收必须使用可升级的相同发布签名；切换身份时先导出资料，不能直接宣称覆盖安装可保留数据。

## 留下对应本次包的证据

复制 `device-evidence.template.json` 到本地忽略目录 `release/evidence/device-qa.json`，填写 APP 摘要、Git 提交、型号、系统、测试人和时间。每项先保留 TODO，实际完成后才填写 PASS 和本地证据文件。测试覆盖两个实际设备，记录必须对应本次包和提交，超过 30 天或未来日期均不放行。失败修复后重测相关步骤，不批量勾选未执行项。

| 检查 ID | 需要实际验收的结果 |
| --- | --- |
| privacy_offline | 首次说明、不同意离线使用、再次打开政策；没有默认授权或启动上传 |
| first_launch_empty | 干净安装的笔记、项目与待办为空；无样例 PDF/试题/笔记自动注入；升级保留已有内容 |
| local_assistant | release 无网络/无 Key 查询自建资料、要点摘录、待办候选、概览与真实出处；空库/无匹配给出下一步 |
| create_note | 首页、项目和日记模板正常创建；文字/手写类型正确；重复点击、存储失败后可重试，重启内容保留 |
| stylus_handwriting | 目标 Pad 与星闪笔的压感、手掌接触、双击/轻捏、分屏焦点、缩放平移、擦除撤销重做、横竖屏及保存重开 |
| offline_learning | 无网络/无 Key 的建课程、笔记、手动题卡、自测、待办与关键词搜索 |
| ocr_pdf_cancel | 图片/扫描 PDF、权限/能力不足、取消后无晚到结果，校对与来源页一致 |
| reader_restart | Markdown/PDF/手写/草稿保存、快速编辑、退出重开、正文与元数据不丢失 |
| upgrade_persistence | 同签名旧版本升级，内容、附件、封面、索引、题卡保留；Key 迁移与重新填写 |
| permission_denied | 拒绝附近设备权限，正常离线和文件备份；无反复强迫授权 |
| ai_consent_revoke | release 不展示远程入口、旧配置也不激活且无模型网络请求；debug 另测发送授权、地址/协议重授、移除 Key |
| ai_failure_cancel | release 本地处理中停止/返回/换文档无晚到结果；debug 另测错误 Key、429/500、断网、超时与三协议取消 |
| backup_restore | PDF、封面、笔迹与题卡真实恢复；取消、重复导入、局部失败重试、空间不足 |
| nearby_transfer | 手机与 Pad 同签名可信组网，双向传递并确认导入数量；缺少能力时回退文件备份 |
| nearby_interruption_cleanup | 断线/超时/过期码/错误码、关闭与异常退出再打开，临时数据清理 |
| keyboard_small_screen | 小屏、软键盘、滚动、底栏恢复，保存/关闭按钮可触及 |
| font_rotation_multiwindow | 最大字体、横竖屏、Pad 分屏/窗口宽度变化，信息不被遮挡 |
| dark_reduce_motion | 深浅主题、系统跟随、减少动态效果、辅助读屏与焦点/控件名称 |
| performance | 启动、长 PDF、连续笔迹、大图谱的实际性能报告；不虚填帧率、内存和耗电 |
| delete_export | 资料查看/导出、更正、回收站/彻底删除、单独删除会话/题卡、Key 移除 |

`review-evidence.template.json` 的四种记录需分别保存为忽略目录中的 JSON：SDK/AGC 接受条件、类别/资质/备案/权属、本地助手实际发布范围的适用要求、签名身份。在 `app-market.json` 填写对应路径。每份包含实际 reviewer、checkedAt、reference 与 reviewed:true。签名记录的证书链摘要来自检查器提取的公开链文件，不是私钥；同时填写对应 APP 摘要及 AGC 核对结果。

物理测试报告、录屏和截图保留在 `release/evidence/`；生成摘要报告在 `release/reports/`。目录默认不上传 Git。不要在公共 PR 上传发布凭据、学生资料或证件。

## 当前外部前置事项

真实发布主体/客服、公开隐私网址、AGC 帐号与发布签名、类别所需资质/备案、双真机验证、平台测试与真实截图尚待完成。项目侧工具会保留 BLOCKED，不能用 unsigned 文件更名、空报告、测试模板或构建成功代替。

官方依据：[应用审核指南](https://developer.huawei.com/consumer/cn/doc/app/50104)、[应用提交](https://developer.huawei.com/consumer/cn/app/submit)、[HarmonyOS 7 官方发布月刊](https://developer.huawei.com/consumer/cn/monthly/202608)、[AppPack 说明](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/application-package-glossary)。要求可能调整，以实际提交时的官方页面与 AGC 为准。
