# 应用市场提交材料与验收

候选 1.0.5（1001005），包名 com.retempt.flowmind，最低 HarmonyOS 6.1.1 / API 24，目标 API 26。手机与平板共用一个应用包。

## 发布资料与签名

签名和发布资料由发布负责人配置。在 app-market.json 填入真实 publisher、supportEmail、privacyUrl，须与 AGC 及隐私政策一致。执行 node tools/generate-market-materials.mjs，同步应用内政策、docs/PRIVACY.md 和 site/privacy.html；政策网页需实际托管并核对公开访问。当前 signingConfigs 为空，交付包为未签名开发构建，签名后才能安装与提交。

## 构建与检查

使用 build_hap.bat -BuildMode release -AppPackage -Clean 构建。服务回归为 tools/verify-workflows.mjs，PDF 专项为 verify-pdf-chain.mjs，发布规则为 verify-app-market.mjs，本地范围检查为 verify-local-release.mjs。编译后双端事件与布局检查为 verify-compiled-ui.mjs，传入 --typescript 指向当前 SDK 的 typescript.js。

app-market-preflight.mjs 的 --project-only 只核验项目和包结构，保留外部 BLOCKED 项。正式签名后运行默认严格模式，传入 --app、--studio、--python 和 --report，核对真实签名、当前包与发布证据。

## 真机证据

复制 device-evidence.template.json 到 release/evidence/device-qa.json，填写本次包 SHA256、源码提交、设备、系统、日期和测试人。每项先保留 TODO，实际通过后才填写 PASS 和证据路径。

- 首次托管隐私声明无第二个自建弹窗，拒绝、再次打开及政策更新行为正确。
- 图谱空库创建、重复名称、连续点击、存储失败、切换页面与重启保持。
- 本地整理的原文、标题列表、断行、日期和否定条件，预览与待办确认。
- PDF、笔迹、稿纸、保存退出、同签名升级、备份恢复与附近传递。
- 手机软键盘、大字体、横竖屏，平板分屏、深浅色与辅助读屏。

截图和录屏来自本次实际签名安装包，覆盖手机和平板。review-evidence.template.json 提供 sdk、qualification、feature-scope、signing 四种记录。签名、个人资料与证据目录不进入公开仓库。

商店文案和操作路径见 STORE_LISTING.md。正式提交仍需发布身份、公开隐私网址、SDK 与类别核对、市场签名和双端真机证据；自动检查不能代替平台审核。
