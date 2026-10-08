# 墨语图标规范

v1.0.2 重绘了应用图标和 55 个工具资源。应用标记使用斜向笔尖、紫色笔帽与墨迹，分别提供浅色、深色和启动器前景/背景；工具使用统一 SVG 描边。

![图标资产预览](icon-preview.png)

该图是源资产预览，不能作为设备界面截图或真机验收证据。

- 工具网格为 24 × 24，描边为 1.8，端点与连接为圆角。默认显示 20vp，按钮触控区至少 44vp。
- `AppIcon` 使用 `Image.fillColor` 跟随主题；`IconButton` 提供原生提示、无障碍名称、选中与禁用状态。
- 常用操作只显示图标。导航、复杂菜单与确认操作保留简短名称；减少文字不能使操作失去含义。
- 狭窄手写工具栏可以横向滚动，颜色/笔粗折叠在设置图标中；笔、荧光笔、橡皮擦、撤销、重做始终位于一级工具栏。

生成向量资源与母版：

```powershell
node tools/generate-ui-icons.mjs
node tools/generate-ui-icons.mjs --check
```

生成 PNG：

```powershell
node tools/generate-icons.mjs --sharp-module "<sharp 模块目录>"
```

也可使用生成器已有的浏览器光栅化路径。启动器 PNG 为 1024px；品牌及启动图为 512px，资产预览为 1024px。修改图标时先更新生成器，再重新生成；CI 校验向量资源是否一致。
