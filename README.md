# 墨语

HarmonyOS 手机与平板上的本地资料库与笔记工具。

[下载 1.1.1](https://github.com/RETEMPT/moyu/releases/tag/v1.1.1) · [使用说明](docs/USER_GUIDE.md) · [隐私说明](docs/PRIVACY.md)

[项目展示 PPT](materials/墨语项目展示.pptx) · [技术可行性说明](materials/墨语项目说明与技术可行性.pdf) · [架构](docs/ARCHITECTURE.md) · [开发指南](docs/DEVELOPMENT_GUIDE.md)

- 阅读 PDF、Markdown、TXT 与图片，支持顶栏标签拖放分屏
- 手写批注、随堂稿纸、区域/整笔橡皮
- 项目分类、双链图谱、搜索、回收站
- 待办、复习题卡、本地文字识别
- 资料备份与快传

资料保存在本地，无需账号，不联网。

> 商店版本为离线版，AI 功能显示"即将上线"，后续版本开放。

## 1.1.1 更新

本版增强本地课程复习：按资料查看阅读与自测概况、筛选待巩固题、到期弱项优先；编辑题卡保留复习安排。全部由本地阅读记录与自测反馈派生，不新增账号、权限或网络调用。

## 发展方向（规划）

墨语计划将公开资料发现、私人资料管理和云AI学习辅助逐步融入研读过程，让资料获取、批注、整理和复习之间保持联系。未来的云AI将围绕摘要、带出处问答和题卡候选等任务提供辅助，各项云服务可按需选择，目前均为规划。

详见[商业价值](docs/BUSINESS_PLAN.md)与[产品特点](docs/INNOVATION.md)。

## 开发与许可证

Release 附件为手机和平板共用的正式模式构建，不包含调试示例或测试资源。附件名标注 `unsigned` 时尚未配置发布签名，须签名后安装；升级时应保持签名一致，卸载前请先备份资料。

## 技术栈

- 语言：ArkTS
- UI：HarmonyOS Declarative UI
- 最低 API：24
- PDF：Mozilla PDF.js（离线）
- 存储：HarmonyOS RDB（SQLite）+ 应用内文件目录

## 团队

- **孟博航** — 主导开发与架构设计
- **宋瑞博** — 功能开发与测试、商店发布

开源鸿蒙大赛参赛项目。

## 开源协议

MIT License. 内置 PDF.js 保留原 Apache-2.0 许可证。

## 反馈

问题与建议：[GitHub Issues](https://github.com/RETEMPT/moyu/issues)
