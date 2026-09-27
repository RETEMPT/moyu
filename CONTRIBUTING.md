# 协作与贡献指南

## 分支模型

仓库采用“稳定主干 + 短期功能分支”的方式协作：

```text
main
├── feature/phone-adaptation       手机端适配工作分支
├── feature/<功能名称>              独立功能开发
└── fix/<问题名称>                  缺陷修复
```

- `main` 始终保持可构建、可安装和可演示。
- `feature/phone-adaptation` 是手机端适配的工作分支。
- 手机端适配完成后，通过 Pull Request 合并回 `main`。
- 后续功能与缺陷修复请从最新 `main` 创建短期分支，避免长期分叉。

## 模块分层约定

应用严格遵循**单向向下依赖**原则：`pages/` → `views/` → `services/` → `common/`。

- `pages/Index.ets`：顶层页面状态与路由装配；
- `views/`：ArkUI 声明式视图组件库，通过 `@Prop` / `@Link` 与事件回调通信；
- `services/`：数据持久化、全文检索、双链图谱、文档导入与模型服务；
- `common/`：类型定义、主题 Token、常量与示例数据工厂。

公共类型、主题 Token、`Index.ets` 和跨层 API 修改前，建议先在 Issue 或 PR 中确认接口，避免同时大范围改动同一文件。

## 开发流程

### 创建功能分支

```powershell
git switch main
git pull --ff-only origin main
git switch -c feature/your-feature
```

### 提交和推送

```powershell
git status
git diff --check
git add <changed-files>
git commit -m "feat(module): 描述本次改动"
git push -u origin feature/your-feature
```

### 发起 Pull Request

目标分支统一选择 `main`。Pull Request 请包含：

- 改动目的和涉及范围；
- 手动或自动验证方式；
- 是否涉及数据格式、公共 API 或页面状态链路；
- 手机端、平板端或模拟器的验证结果；
- 已知限制和后续工作。

合并前至少由另一位成员 Review。不要直接向 `main` 推送未审查的功能代码。

## 手机端适配边界

手机端适配优先复用以下共享层：

- `common/`
- `services/`
- 数据模型和持久化逻辑

优先在以下位置增加响应式处理：

- `views/layout/AppShell.ets`
- `views/layout/GlobalTopBar.ets`
- `views/layout/Sidebar.ets`
- `views/reader/`
- `pages/Index.ets`

只有当手机和平板的交互流程确实无法共用时，才拆分独立组件，例如 `PhoneReaderWorkspace` 和 `TabletReaderWorkspace`。不要复制整套服务层或长期维护两套独立服务分支。

## 合并前检查

```powershell
git diff --check
```

使用 DevEco Studio 构建 `entry` 模块，并在目标设备上至少验证：

- 页面切换和返回链路；
- 弹层关闭和遮罩点击；
- 笔记保存、重新打开和搜索；
- PDF 阅读、批注和手写；
- 手机端窄屏布局；
- 平板端三栏布局。

本地快捷构建与部署脚本：

```powershell
# 编译 HAP
.\build_hap.bat

# 一键编译并安装部署到在线设备
.\deploy_hap.bat
```

## 提交信息规范

提交信息使用简短、明确的动词描述，推荐遵循 Conventional Commits 规范，例如：

- `feat(layout): 新增手机端底部导航抽屉`
- `fix(reader): 修复窄屏弹层关闭区域`
- `perf(graph): 优化图谱物理仿真性能`
- `docs: 更新技术栈与协作指南`

一次提交只解决一类问题，避免把无关格式化、重命名和功能改动混在一起。
