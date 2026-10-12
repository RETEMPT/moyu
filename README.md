# FlowMind（墨语）

墨语是一款面向课程学习的 HarmonyOS 本地资料与笔记应用，支持手机和平板。当前版本 1.0.5（1001005），最低 HarmonyOS 6.1.1 / API 24，目标 API 26。

## 当前功能

- Markdown 笔记、项目分类、收藏、搜索与双链图谱。
- PDF 原件导入、页面阅读、笔迹批注、随堂稿纸与自由白板。
- 系统文字识别、校对和本地规则排版，支持原文保留、标题列表整理、可选断行合并和明确待办提取。
- 导入 Markdown、文字及 Marker 转换结果；转换结果须自行核对。
- 手动题卡、自测和按反馈安排复习；农历、节日与日历待办。
- 本地文件备份与恢复，附近设备副本传递。
- 外观主题、明暗模式、减少动效和按窗口宽度适配。

本版本无需帐号或服务密钥；资料整理在本机完成。图片识别、PDF Kit、手写笔和附近传递依赖设备系统能力。

## 1.0.5 修复

图谱主题同时包含已保存项目和笔记分类，空主题也可见。新建操作等待保存结果，失败时保留输入；手机主题表单使用独立输入行与 48vp 操作区，平板保留宽窗口布局。首次启动交由已配置的平台隐私托管处理，设置中可查看隐私政策。

可选功能源码保存在 [功能存档](archive/optional-features/README.md)，位于应用源目录之外，不参与编译打包。

## 构建与验证

使用 DevEco Studio 构建：

```powershell
.\build_hap.bat -BuildMode release -AppPackage -Clean
node tools/verify-workflows.mjs
node tools/verify-pdf-chain.mjs
node tools/verify-app-market.mjs
node tools/verify-local-release.mjs
node tools/generate-market-materials.mjs --check
```

未签名开发产物需要配置适用签名后安装。发布签名、真实发布主体、公开隐私链接与真机验收见 [提交材料](release/README.md)。编译及自动检查通过不表示应用市场已审核通过。

使用流程见 [用户指引](docs/USER_GUIDE.md)，本次发行见 [1.0.5 说明](docs/RELEASE_1.0.5.md)。项目采用 MIT 许可证。
