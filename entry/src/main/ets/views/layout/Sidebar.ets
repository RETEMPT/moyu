/**
 * 知识与项目文件资源管理器侧边栏
 *
 * 主工作区、项目树和实用工具各有自己的导航区。
 * 项目名称打开项目，箭头控制文件树，更多按钮打开项目操作。
 */
import {
  AnimationTokens,
  ColorPalette,
  LibraryColors,
  LayoutTokens,
  TypographyTokens
} from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { SpaceFolder } from '../../common/types/SpaceFolder';
import { NAV_CANVAS, NAV_CHAT, NAV_FAVORITE, NAV_GRAPH, NAV_HOME, NAV_LIBRARY, NAV_SETTINGS, NAV_TODO, NAV_TRASH } from '../../common/constants/WorkspaceConstants';
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
  @StorageProp('flowmindStudyPreview') studyPreview: boolean = false;
  @State pressedItemId: string = '';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  /** 抽屉宽度：手机窄屏按屏宽百分比，避免几乎盖满；宽屏用固定宽度。 */
  private drawerWidth(): Length {
    return this.isPhone ? '84%' : LayoutTokens.SIDEBAR_WIDTH;
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
      Row({ space: 0 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 10 }) {
            AppIcon({ source: projectIcon(space.icon || ''), iconSize: 19, tint: this.palette().inkSecondary })
            Text(space.name).fontSize(TypographyTokens.BODY_REGULAR).maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              .fontWeight(space.id === this.activeSpaceId ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(space.id === this.activeSpaceId ? this.palette().inkPrimary : this.palette().inkSecondary)
          }.width('100%')
        }.layoutWeight(1).height(ROW_HEIGHT).padding({ left: 10, right: 2 }).backgroundColor(Color.Transparent)
          .accessibilityText('项目 ' + space.name + '，' + space.count + ' 份资料')
          .accessibilityDescription(space.id === this.activeSpaceId ? '已选中' : '')
          .hoverEffect(HoverEffect.Highlight).onClick(() => this.onSelectSpace(space.id))
        if (space.notes && space.notes.length > 0) {
          Button({ type: ButtonType.Normal }) {
            AppIcon({ source: $r('app.media.ic_chevron_right'), iconSize: 13, tint: this.palette().inkMuted })
              .rotate({ angle: space.isOpen ? 90 : 0 })
              .animation({ duration: AnimationTokens.duration(140), curve: Curve.EaseInOut })
          }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
            .accessibilityText((space.isOpen ? '收起项目 ' : '展开项目 ') + space.name)
            .onClick(() => this.onToggleSpace(space.id))
        }
        IconButton({ icon: $r('app.media.ic_more'), label: '项目操作 ' + space.name, compact: true,
          onAction: () => this.onOpenSheet('project_menu', space, null) })
      }
      .width('100%')
      .height(ROW_HEIGHT)
      .borderRadius(8)
      .backgroundColor(space.id === this.activeSpaceId ? this.palette().activeBg : Color.Transparent)
      if (space.isOpen && space.notes && space.notes.length > 0) {
        Column() {
          ForEach(space.notes, (note: NoteItem) => {
            this.fileRow(note)
          }, (note: NoteItem) => noteRenderKey(note))
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
  fileRow(note: NoteItem) {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          AppIcon({ source: documentIcon(note.type), iconSize: 16, tint: this.palette().inkSecondary })
          Text(note.title).fontSize(TypographyTokens.CAPTION).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            .fontColor(note.id === this.activeNoteId ? this.palette().inkPrimary : this.palette().inkSecondary)
        }.width('100%')
      }.layoutWeight(1).height(FILE_ROW_HEIGHT).backgroundColor(Color.Transparent).padding({ left: 30, right: 5 })
        .accessibilityText('打开 ' + note.title).hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.onSelectNote(note))
        .gesture(LongPressGesture({ repeat: false, duration: 480 }).onAction(() => this.onOpenSheet('note_menu', null, note)))
      if (note.id === this.activeNoteId) {
        IconButton({ icon: $r('app.media.ic_more'), label: '资料操作 ' + note.title, compact: true,
          onAction: () => this.onOpenSheet('note_menu', null, note) })
      }
    }
    .width('100%')
    .height(FILE_ROW_HEIGHT)
    .borderRadius(6)
    .backgroundColor(note.id === this.activeNoteId ? this.palette().activeBg : Color.Transparent)
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
    .accessibilityDescription(this.activeNav === navKey ? '已选中' : '')
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
      Text('项目').fontSize(12).fontColor(this.palette().inkMuted).fontWeight(FontWeight.Medium)
        .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.spaces.some((space: SpaceFolder) => space.isOpen && space.count > 0)) {
        IconButton({ icon: $r('app.media.ic_chevron_up'), label: '收起所有项目', compact: true, onAction: this.onCollapseAllSpaces })
      }
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
            .fontSize(21)
            .fontColor(this.palette().inkPrimary)
            .fontWeight(FontWeight.Bold)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          IconButton({ icon: $r('app.media.ic_menu'), label: '收起侧栏', compact: true, onAction: this.onToggleSidebar })
        }
        .width('100%')
        .height(54)
        .padding({ left: 10, right: 8 })
        .margin({ bottom: 10 })

        // ---- 全局核心功能导航 ----
        Scroll() {
          Column() {
            Column({ space: 4 }) {
              this.navRow($r('app.media.ic_home'), '主页', NAV_HOME)
              this.navRow($r('app.media.ic_folder'), '资料库', NAV_LIBRARY)
              this.navRow($r('app.media.ic_chat'), this.studyPreview ? NAV_CHAT : '学习工具', NAV_CHAT)
              this.navRow($r('app.media.ic_check'), '待办', NAV_TODO)
              this.navRow($r('app.media.ic_star'), '收藏', NAV_FAVORITE)
            }.width('100%').margin({ bottom: 12 })
            Divider().strokeWidth(1).color(this.palette().border)
            this.treeSectionHeader()
            ForEach(this.spaces, (space: SpaceFolder) => {
              this.projectRow(space)
            }, (space: SpaceFolder) => spaceRenderKey(space))
          }.width('100%')
        }.layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)

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
    .backgroundColor(this.isDarkMode ? this.palette().sidebar : LibraryColors.sidebar)
    .border({ width: { right: 1 }, color: { right: this.palette().borderSubtle } })
  }
}
