/**
 * 知识与项目文件资源管理器侧边栏
 *
 * Notion 文档侧栏：
 *   1. 顶部只作品牌标识，首页进入全局导航
 *   2. 快捷搜索 + 首页 / 知识图谱 / 自由白板 / 收藏 / 待办 / 回收站
 *   3. 项目文件资源管理器：细线文件夹、箭头 90° 展开；
 *      折叠状态来自 Index 的 space.isOpen，这里不主动展开任何项目
 *   4. 项目更多菜单、新建项目、收起全部、资料行菜单端口全部保留
 */
import {
  AnimationTokens,
  ColorPalette,
  LayoutTokens,
  TypographyTokens
} from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { SpaceFolder } from '../../common/types/SpaceFolder';
import { NAV_CANVAS, NAV_FAVORITE, NAV_GRAPH, NAV_HOME, NAV_LIBRARY, NAV_SETTINGS, NAV_TODO, NAV_TRASH } from '../../common/constants/WorkspaceConstants';
import { AppIcon } from '../common/AppIcon';
import { IconButton } from '../common/IconButton';
import { documentIcon } from '../../common/utils/DocumentPresentation';
import { noteRenderKey, spaceRenderKey } from '../../common/utils/ForEachKeys';
import { BrandMark } from '../brand/BrandMark';
import { projectIcon } from '../../common/utils/ProjectIcons';

const ROW_HEIGHT: number = 44;
const FILE_ROW_HEIGHT: number = 44;

@Component
export struct Sidebar {
  @Prop spaces: SpaceFolder[] = [];
  onToggleSidebar: () => void = () => {};

  @Prop activeNav: string = '';
  @Prop activeSpaceId: string = '';
  @Prop  activeNoteId: string = '';


  onToggleSpace: (spaceId: string) => void = () => {};
  onCollapseAllSpaces: () => void = () => {};
  onSelectSpace: (spaceId: string) => void = () => {};
  onOpenSearch: () => void = () => {};
  onSelectNote: (note: NoteItem) => void = () => {};
  onSelectNav: (navKey: string) => void = () => {};
  onOpenSettings: () => void = () => {};
  /** 请求 Index 层挂载指定底部弹层（全屏遮罩，而非被侧栏 260vp 宽度裁剪） */
  onOpenSheet: (type: string, project: SpaceFolder | null, note: NoteItem | null) => void = () => {};
  /** 请求打开居中「新建项目」对话框 */
  onOpenCreateProject: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;
  @State pressedItemId: string = '';
  private suppressRowClick: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  /** 抽屉宽度：手机窄屏按屏宽百分比，避免几乎盖满；宽屏用固定宽度。 */
  private drawerWidth(): Length {
    return this.isPhone ? '94%' : LayoutTokens.SIDEBAR_WIDTH;
  }

  // ------------------------------------------------------------------
  // 触感物理动画属性生成器
  // ------------------------------------------------------------------

  private getItemScale(id: string): number {
    if (this.pressedItemId === id) {
      return AnimationTokens.SCALE_PRESSED;
    }
    return 1.0;
  }

  // ------------------------------------------------------------------
  // 视图构建：项目与资源文件树
  // ------------------------------------------------------------------

  @Builder
  projectRow(space: SpaceFolder) {
    Column() {
      // ---- 项目节点行：细线文件夹 + 克制展开动画 ----
      Row({ space: 6 }) {
        AppIcon({ source: $r('app.media.ic_chevron_right'), iconSize: 13, tint: this.palette().inkMuted })
          .rotate({ angle: space.isOpen ? 90 : 0 })
          .animation({ duration: AnimationTokens.duration(140), curve: Curve.EaseInOut })

        AppIcon({
          source: projectIcon(space.icon || ''), iconSize: 17,
          tint: this.palette().inkSecondary
        })

        // 项目名称
        Text(space.name)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(space.id === this.activeSpaceId ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(space.id === this.activeSpaceId ? this.palette().inkPrimary : this.palette().inkSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)


        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_more'), iconSize: 15, tint: this.palette().inkMuted })
        }.width(44).height(44).padding(0).borderRadius(8).backgroundColor(Color.Transparent)
          .accessibilityText('项目操作 ' + space.name)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.suppressRowClick = true;
            this.onOpenSheet('project_menu', space, null);
          })
      }
      .width('100%')
      .height(ROW_HEIGHT)
      .padding({ left: 8, right: 2 })
      .borderRadius(6)
      .backgroundColor(space.id === this.activeSpaceId ? this.palette().activeBg : Color.Transparent)
      .accessibilityText('项目 ' + space.name + '，' + space.count + ' 份资料')
      .accessibilityDescription(space.isOpen ? '已展开' : '已折叠')
      .hoverEffect(HoverEffect.Highlight)
      // 单点整行切换展开/收起并激活选中；不主动展开任何项目。
      .onClick(() => {
        if (this.suppressRowClick) {
          this.suppressRowClick = false;
          return;
        }
        this.onToggleSpace(space.id);
        this.onSelectSpace(space.id);
      })
      // 长按保留项目菜单端口，不做放大 / 阴影位移。
      .gesture(
        LongPressGesture({ repeat: false, duration: 480 })
          .onAction(() => {
            this.onOpenSheet('project_menu', space, null);
          })
      )

      // ---- 下辖子资料文件列表（仍由 Index 的 isOpen 状态决定） ----
      if (space.isOpen) {
        Column({ space: 0 }) {
          if (!space.notes || space.notes.length === 0) {
            Row({ space: 4 }) {
              Text('＋')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
              Text('新建资料')
                .fontSize(TypographyTokens.CAPTION)
                .fontColor(this.palette().inkMuted)
            }
            .width('100%')
            .height(32)
            .padding({ left: 30, right: 8 })
            .borderRadius(6)
            .accessibilityText('在项目 ' + space.name + ' 中新建资料')
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.onOpenSheet('new_content', space, null);
            })
          } else {
            ForEach(space.notes, (note: NoteItem) => {
              this.fileRow(note, space.name)
            }, (note: NoteItem) => noteRenderKey(note))
          }
        }
        .width('100%')
        .padding({ top: 1, bottom: 2 })
        .transition(
          AppStorage.get<boolean>('flowmindReduceMotion') === true
            ? TransitionEffect.IDENTITY
            : TransitionEffect.OPACITY.animation({ duration: AnimationTokens.duration(140), curve: Curve.EaseInOut })
        )
      }
    }
    .width('100%')
    .margin({ bottom: 1 })
  }

  @Builder
  fileRow(note: NoteItem, projectName: string) {
    Row({ space: 6 }) {
      // 文件类型专属图标（彩色）
      AppIcon({ source: documentIcon(note.type), iconSize: 16, tint: this.palette().inkSecondary })

      // 文件标题
      Text(note.title)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(note.id === this.activeNoteId ? this.palette().inkPrimary : this.palette().inkSecondary)
        .fontWeight(note.id === this.activeNoteId ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      // 更多操作菜单按钮 (···)
      if (note.id === this.activeNoteId) {
        Text('···')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
          .width(22)
          .height(20)
          .textAlign(TextAlign.Center)
          .borderRadius(4)
          .backgroundColor(this.palette().surfaceSubtle)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.suppressRowClick = true;
            this.onOpenSheet('note_menu', null, note);
          })
      } else if (note.tag && note.tag.length > 0) {
        Text(note.tag)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .maxLines(1)
      }
    }
    .width('100%')
    .height(FILE_ROW_HEIGHT)
    .padding({ left: 32, right: 6 })
    .borderRadius(6)
    .backgroundColor(note.id === this.activeNoteId ? this.palette().activeBg : Color.Transparent)
    .hoverEffect(HoverEffect.Highlight)
    // 短按：打开阅读/编辑并选中
    .onClick(() => {
      if (this.suppressRowClick) {
        this.suppressRowClick = false;
        return;
      }
      this.onSelectNote(note);
    })
    // 长按：呼出文件操作菜单，不做位移
    .gesture(
      LongPressGesture({ repeat: false, duration: 480 })
        .onAction(() => {
          this.onOpenSheet('note_menu', null, note);
        })
    )
  }

  // ------------------------------------------------------------------
  // 视图构建：全局快捷导航行
  // ------------------------------------------------------------------

  @Builder
  navRow(icon: Resource, label: string, navKey: string) {
    Row({ space: 8 }) {
      AppIcon({ source: icon, iconSize: 20, tint: this.activeNav === navKey ? this.palette().inkPrimary : this.palette().inkSecondary })
      Text(label)
        .fontSize(TypographyTokens.BODY_REGULAR)
        .fontColor(this.activeNav === navKey ? this.palette().inkPrimary : this.palette().inkSecondary)
        .fontWeight(this.activeNav === navKey ? FontWeight.Medium : FontWeight.Normal)
        .layoutWeight(1)
    }
    .width('100%')
    .height(44)
    .padding({ left: 10, right: 10 })
    .borderRadius(5)
    .backgroundColor(this.activeNav === navKey ? this.palette().activeBg : Color.Transparent)
    .accessibilityText(label)
    .scale({
      x: this.getItemScale(`nav-${navKey}`),
      y: this.getItemScale(`nav-${navKey}`)
    })
    .animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedItemId = `nav-${navKey}`;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedItemId = '';
      }
    })
    .onClick(() => this.onSelectNav(navKey))
  }

  // ------------------------------------------------------------------
  // 视图构建：对话记录列表
  // ------------------------------------------------------------------

  /** 项目资料区段头：收起全部 + 新建项目 */
  @Builder
  treeSectionHeader() {
    Row({ space: 0 }) {
      Text('私人页面').fontSize(12).fontColor(this.palette().inkMuted).fontWeight(FontWeight.Medium)
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      IconButton({ icon: $r('app.media.ic_chevron_up'), label: '收起所有项目', compact: true, onAction: this.onCollapseAllSpaces })
      IconButton({ icon: $r('app.media.ic_plus'), label: '新建项目', compact: true, onAction: this.onOpenCreateProject })
    }.width('100%').height(44).padding({ left: 8, right: 0 }).margin({ bottom: 2 })
  }

  // ------------------------------------------------------------------
  // 交互式弹层：由 Index 层挂载（全屏遮罩），此处仅触发
  // ------------------------------------------------------------------

  // ------------------------------------------------------------------
  // 主布局构建
  // ------------------------------------------------------------------

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // ---- 顶部工作区品牌（只作品牌，不冒充导航） ----
        Row({ space: 8 }) {
          BrandMark({ markSize: 22 })
          Text('墨语')
            .fontSize(TypographyTokens.BODY_LARGE)
            .fontColor(this.palette().inkPrimary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          IconButton({ icon: $r('app.media.ic_menu'), label: '收起侧栏', compact: true, onAction: this.onToggleSidebar })
        }
        .width('100%')
        .height(44)
        .padding({ left: 10, right: 8 })
        .margin({ bottom: 4 })

        // ---- 快速搜索入口 ----
        Row({ space: 8 }) {
          AppIcon({ source: $r('app.media.ic_search'), iconSize: 20, tint: this.palette().inkSecondary })
          Text('搜索')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkMuted)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .height(44)
        .padding({ left: 10, right: 10 })
        .borderRadius(5)
        .backgroundColor(this.palette().surfaceSubtle)
        .accessibilityText('搜索笔记、文件或内容')
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.onOpenSearch())
        .margin({ bottom: 8 })

        // ---- 全局核心功能导航 ----
        Column({ space: 2 }) {
          this.navRow($r('app.media.ic_home'), '主页', NAV_HOME)
          this.navRow($r('app.media.ic_read'), '资料库', NAV_LIBRARY)
          this.navRow($r('app.media.ic_star'), '收藏', NAV_FAVORITE)
          this.navRow($r('app.media.ic_check'), '待办', NAV_TODO)
        }
        .width('100%')
        .margin({ bottom: 18 })

        Divider()
          .strokeWidth(1)
          .color(this.palette().borderSubtle)
          .margin({ top: 2, bottom: 2 })

        // 私人项目树在所有工作区均可达。
          this.treeSectionHeader()

          // 项目树滚动容器
          Scroll() {
            Column() {
                ForEach(this.spaces, (space: SpaceFolder) => {
                  this.projectRow(space)
                }, (space: SpaceFolder) => spaceRenderKey(space))
                Button({ type: ButtonType.Normal }) {
                  Row({ space: 8 }) {
                    AppIcon({ source: $r('app.media.ic_plus'), iconSize: 16, tint: this.palette().inkMuted })
                    Text('新建项目').fontSize(13).fontColor(this.palette().inkSecondary)
                  }.width('100%')
                }.width('100%').height(44).padding({ left: 10, right: 10 }).borderRadius(5).backgroundColor(Color.Transparent)
                  .accessibilityText('添加私人项目').onClick(() => this.onOpenCreateProject())
            }
            .width('100%')
          }
          .layoutWeight(1)
          .align(Alignment.TopStart)
          .scrollBar(BarState.Off)

        Column({ space: 0 }) {
          this.navRow($r('app.media.ic_graph'), '知识图谱', NAV_GRAPH)
          this.navRow($r('app.media.ic_canvas'), '自由白板', NAV_CANVAS)
          this.navRow($r('app.media.ic_trash'), '回收站', NAV_TRASH)
        }.width('100%').padding({ top: 8 }).border({ width: { top: 1 }, color: this.palette().borderSubtle })

        // ---- 底部设置入口 ----
        Row({ space: 8 }) {
          AppIcon({ source: $r('app.media.ic_settings'), tint: this.palette().inkSecondary })
          Text('设置')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkSecondary)
            .layoutWeight(1)
        }
        .width('100%')
        .height(48)
        .padding({ left: 10, right: 10 })
        .borderRadius(5)
        .backgroundColor(this.activeNav === NAV_SETTINGS ? this.palette().activeBg : Color.Transparent)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.onOpenSettings())
        .margin({ top: 4, bottom: 6 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 8, right: 8, top: 8 })

    }
    .width(this.drawerWidth())
    .height('100%')
    .backgroundColor(this.palette().sidebar)
    .border({ width: { right: 1 }, color: { right: this.palette().borderSubtle } })
  }
}
