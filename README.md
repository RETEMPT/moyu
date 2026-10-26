# 墨语 FlowMind

> HarmonyOS 本地课程资料与笔记应用 —— 阅读、批注、整理、复习，全部离线完成。

[![version](https://img.shields.io/badge/version-1.1.0-blue)](https://github.com/RETEMPT/moyu/releases/tag/v1.1.0)
[![platform](https://img.shields.io/badge/platform-HarmonyOS%20Phone%20%26%20Tablet-purple)](https://developer.huawei.com/consumer/cn/)
[![license](https://img.shields.io/badge/license-Apache--2.0-green)](LICENSE)

---

## 项目简介

墨语是一款面向校园学习的 HarmonyOS 应用，支持手机与平板。学生可以用它阅读 PDF、Markdown、TXT 与图片资料，在手写画布上批注和做随堂稿纸，用本地文字识别整理笔记，并通过双链图谱、待办与复习题卡构建个人知识体系。

**核心设计原则：本地优先、零账号、零联网。** 所有资料保存在本机，无需注册，不上传云端，不收集设备标识或位置信息。

## 核心功能

### 资料收集与整理

- 导入 PDF、Markdown、TXT 及 PNG/JPG/WebP/BMP/GIF 图片，一次最多 20 份
- 本地文字识别（OCR）+ 规则排版，生成学习笔记与待办清单
- 项目分类、标签筛选、关键词搜索（含 PDF 校对文字定位页码）
- 回收站支持整项目恢复与逐篇恢复

### 阅读与手写批注

- 自由白板、PDF、图片、手写笔记共用同一套工作台
- 笔、荧光笔、橡皮（区域/整笔两种模式）、图形工具（直线/矩形/椭圆/箭头）
- 双指缩放（100%–250%）与平移，压力感应笔迹
- 随堂稿纸（白纸/横线/方格），笔迹独立保存，不改写原件
- 分屏阅读：顶栏拖放或搜索，最多 8 个标签，手机上下/平板左右排列

### 知识管理

- 双向链接与知识图谱：点击两个节点建立关联
- 待办系统：按日期组织，完成进度实时计算
- 课程复习：手动填写问题/答案/引用，"不会/模糊/掌握"安排下次复习
- 文字笔记支持 Markdown、代码块、表格、任务勾选、实时分栏预览

### 备份与快传

- 按项目勾选资料，导出包含正文、原 PDF、图片、封面、笔迹、校对文字、题卡的 JSON 包
- 快传通过系统分享面板选择接收设备，应用不申请数据同步权限
- 恢复创建副本并保留原分类

### 外观与无障碍

- 8 套配色主题（白蓝/白青/白绿/白玫/暖砂/墨紫/黑白/雾蓝）
- 跟随系统/浅色/深色三种模式，切换即时生效
- 减少动效选项，阅读器与弹窗同步切换

## 技术架构

```
┌─────────────────────────────────────────────┐
│  视图层 (ArkTS Declarative UI)              │
│  @StorageProp 响应式 · 13 组件热切换主题     │
├─────────────────────────────────────────────
│  业务层                                      │
│  NoteStorageService · InkInputService        │
│  PDFRenderer · OCRService · GraphService     │
─────────────────────────────────────────────┤
│  引擎层                                      │
│  Mozilla PDF.js (离线, Apache-2.0)           │
│  InkFrameComposer (离屏合成 + transfer)      │
│  CanvasViewport (世界坐标 · 缩放 · 平移)     │
├─────────────────────────────────────────────┤
│  平台层 (HarmonyOS API)                      │
│  Preferences · BundleManager · Configuration │
│  System Share Panel · File Picker            │
└─────────────────────────────────────────────
```

- **语言**: ArkTS (TypeScript 超集)
- **UI 框架**: HarmonyOS Declarative UI
- **最低 API**: 24 (兼容 API 26+)
- **PDF 引擎**: Mozilla PDF.js 离线版
- **数据存储**: Preferences (主题/设置) + 应用内文件目录 (资料/笔迹)
- **签名**: 华为发布证书 + Profile，release .app 分发

## 版本历史

| 版本 | 日期 | 主要变更 |
|------|------|----------|
| 1.1.0 | 2026-10 | 本地阅读器重构、手写笔迹可靠性修复、智能整理入口、商店 gating |
| 1.0.5 | 2026-10 | PDF 导入持久化、响应式阅读器优化 |
| 1.0.4 | 2026-10 | 隐私说明离线化、AI 界面隐藏 |
| 1.0.3 | 2026-10 | 阅读器控件、可选 AI、PDF 导入、UI 清理 |
| 1.0.2 | 2026-10 | 离线助手、原生笔控制、图标 UI |
| 1.0.1 | 2026-10 | 多设备稳定性、附近传递 |
| 1.0.0 | 2026-10 | 初始版本 |

## 界面预览

<!-- 替换为实际截图路径 -->
| 手机 | 平板 |
|------|------|
| ![手机-首页](docs/screenshots/phone-home.png) | ![平板-阅读](docs/screenshots/pad-reader.png) |
| ![手机-手写](docs/screenshots/phone-handwriting.png) | ![平板-图谱](docs/screenshots/pad-graph.png) |

## 安装

1. 从 [Releases](https://github.com/RETEMPT/moyu/releases) 下载最新 `.app` 文件
2. 使用华为应用市场或 DevEco Studio 安装到 HarmonyOS 设备
3. 首次打开无需登录，直接开始使用

> 升级时请保持签名一致；卸载前请先通过"设置 → 备份与快传"导出资料。

## 项目结构

```
moyu/
├── AppScope/           # 应用级配置与资源
├── entry/              # 主模块
│   └── src/main/
│       ├── ets/        # ArkTS 源码
│       │   ├── common/     # 主题、类型、工具
│       │   ├── services/   # 业务服务 (存储/笔迹/PDF/OCR)
│       │   └── views/      # 视图组件 (首页/阅读器/设置/图谱)
│       └── resources/  # 模块资源
├── docs/               # 项目文档
└── tools/              # 构建辅助工具
```

## 团队

- **孟博航** — 主导开发与架构设计
- **宋瑞博** — 功能开发与设计、商店发布

（开源鸿蒙大赛参赛项目）

## 未来规划

当前版本为离线单机版，以下功能已在代码库中预留，后续版本将逐步接入：

- 云同步：跨设备笔记与资料同步
- 在线 AI 辅助：智能整理、问答、内容生成
- 协作分享：多人实时协作编辑

## 开源协议

本项目采用 Apache-2.0 许可证。内置 Mozilla PDF.js 离线引擎保留其原始 Apache-2.0 许可证。

## 反馈

- 问题与建议：[GitHub Issues](https://github.com/RETEMPT/moyu/issues)
- 隐私咨询：见 [隐私说明](docs/PRIVACY.md)
