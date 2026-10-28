# 墨语

HarmonyOS 手机与平板上的本地资料库与笔记工具。

[下载 1.1.1](https://github.com/RETEMPT/moyu/releases/tag/v1.1.1) · [使用说明](docs/USER_GUIDE.md) · [隐私说明](docs/PRIVACY.md)

[文档总览](docs/README.md) · [开发指南](docs/DEVELOPMENT_GUIDE.md) · [代码规范](docs/CODE_STANDARDS.md)

- 阅读 PDF、Markdown、TXT 与图片，支持顶栏标签拖放分屏
- 手写批注、随堂稿纸、区域/整笔橡皮
- 项目分类、双链图谱、搜索、回收站
- 待办、复习题卡、本地文字识别
- 资料备份与快传

资料保存在本地，无需账号，不联网。

> 商店版本为离线版，AI 功能显示"即将上线"，后续版本开放。
## 1.1.1 更新与能力边界

当前版本为 1.1.1（1010001）。本版增强本地课程复习，同时在仓库中提供独立 AI 实验与离线接入准备；三者的使用范围如下，完整边界以[产品范围](PRODUCT_SCOPE.md)为准。

| 内容 | 当前状态 |
| --- | --- |
| 本地复习增强 | 主应用新增按资料查看阅读与自测概况、筛选待巩固题、到期弱项优先；编辑题卡保留复习安排，手机和平板实际交互仍待验证 |
| [独立 AI 学习实验](cloud/ai/README.md) | 独立命令行原型，支持资料检索、可编辑学习记忆及 Ollama 摘要、问答、题卡、报告、复习计划草稿；未接入主软件，真实模型效果待验 |
| [离线结果接入准备](docs/LEARNING_INTEGRATION.md) | 已有结果导出、两端校验与单来源题卡候选转换；主程序尚无导入、自动保存或联网入口 |

主程序暂不开放云服务或 AI 业务。独立实验使用自己的明文工作区，不读取主应用数据库；项目借鉴与复用边界见[参考记录](docs/AI_REFERENCES.md)。

## 发展方向（规划）

墨语计划将公开资料发现、私人资料管理和云AI学习辅助逐步融入研读过程，让资料获取、批注、整理和复习之间保持联系。未来的云AI将围绕摘要、带出处问答和题卡候选等任务提供辅助，各项云服务可按需选择。团队托管云AI、收费云盘和公开资料库目前均为规划，尚未实现或开放购买。

这些方向将随产品演进逐步推进，与本地阅读、书写和复习衔接。详见[商业价值](docs/BUSINESS_PLAN.md)、[云AI服务方向](docs/CLOUD_AI_BUSINESS.md)、[产品特点](docs/INNOVATION.md)及[未来开发方向](docs/ROADMAP.md)。

## 开发与许可证

Release 附件为手机和平板共用的正式模式构建，不包含调试示例或测试资源。附件名标注 `unsigned` 时尚未配置发布签名，须签名后安装；升级时应保持签名一致，卸载前请先备份资料。

## 技术栈

- 语言：ArkTS
- UI：HarmonyOS Declarative UI
- 最低 API：24
- PDF：Mozilla PDF.js（离线）
- 存储：Preferences + 应用内文件目录

## 团队

- **孟博航** — 主导开发与架构设计
- **宋瑞博** — 功能开发与测试、商店发布

开源鸿蒙大赛参赛项目。

## 开源协议

MIT License. 内置 PDF.js 保留原 Apache-2.0 许可证。

## 反馈

问题与建议：[GitHub Issues](https://github.com/RETEMPT/moyu/issues)
