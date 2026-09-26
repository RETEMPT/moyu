/**
 * 知识与项目文件资源管理器侧边栏 (Apple 流体动效与体感交互)
 *
 * 核心架构：
 *   1. 顶部：工作区标识与全局首页入口
 *   2. 快捷检索与全局导航（知识图谱 / 自由白板 / AI 墨客）
 *   3. 项目文件资源管理器（Project Explorer）：
 *      - 项目（Project）作为一级容器，包含主题色、图标与下辖资料
 *      - 短按：触感凹陷回弹（0.96 scale + springMotion(0.25, 0.76) 弹簧曲线），箭头 90° 平滑旋转，展开/折叠子文件树
 *      - 长按：280ms 快速触发呼吸感微上浮（1.025 scale + 柔和阴影），呼出 Apple-style 悬浮操作面板（Action Sheet）
 *      - 资料类型可视化胶囊（▤ 笔记 / ⬡ 白板 / 🗎 资料 / ☑ 待办）
 *   4. 交互式弹层：新建项目、重命名项目、项目/文件操作面板（含二次确认防误触）
 */
import { curves } from '@kit.ArkUI';
import {
  AnimationTokens,
  ColorPalette,
  LayoutTokens,
  ResourceTypeTokens,
  TypographyTokens
} from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { SpaceFolder } from '../../common/types/SpaceFolder';
import { ChatSession, StoredMessage } from '../../common/types/ChatSession';
import { NAV_AI, NAV_CANVAS, NAV_FAVORITE, NAV_GRAPH, NAV_HOME, NAV_TODO, NAV_TRASH } from '../../common/constants/WorkspaceConstants';
import { noteRenderKey, spaceRenderKey } from '../../common/utils/ForEachKeys';
import { BrandMark } from '../brand/BrandMark';
import { ProjectMenuSheet } from './sheets/ProjectMenuSheet';
import { NewProjectSheet } from './sheets/NewProjectSheet';
import { NewContentSheet } from './sheets/NewContentSheet';
import { RenameProjectSheet } from './sheets/RenameProjectSheet';
import { NoteMenuSheet } from './sheets/NoteMenuSheet';
import { RenameNoteSheet } from './sheets/RenameNoteSheet';
import { MoveNoteSheet } from './sheets/MoveNoteSheet';
import { TagSheet } from './sheets/TagSheet';
import { TemplateSheet } from './sheets/TemplateSheet';

const ROW_HEIGHT: number = 38;
const FILE_ROW_HEIGHT: number = 36;

/** 侧栏中段模式：项目资料树 / 对话记录列表 */
export const SIDEBAR_MODE_TREE: string = 'tree';
export const SIDEBAR_MODE_SESSIONS: string = 'sessions';

@Component
export struct Sidebar {
  @Prop spaces: SpaceFolder[] = [];
  @Prop recentNotes: NoteItem[] = [];
  @Prop activeNav: string = '';
  @Prop activeSpaceId: string = '';
  @Prop  activeNoteId: string = '';
  /** 回收站中的笔记数，用于「回收站」导航角标 */
  @Prop trashCount: number = 0;
  /** 全部未完成待办数，用于「待办」导航角标 */
  @Prop todoPendingCount: number = 0;
  /** 中段模式：'tree' 项目资料树 | 'sessions' 对话记录 */
  @Prop sidebarMode: string = SIDEBAR_MODE_TREE;
  /** 对话记录（sessions 模式渲染） */
  @Prop sessions: ChatSession[] = [];
  @Prop activeSessionId: string = '';
  /** 收藏（置顶/星标）笔记数，用于「收藏」导航角标 */
  @Prop favoriteCount: number = 0;

  onToggleSpace: (spaceId: string) => void = () => {};
  onCollapseAllSpaces: () => void = () => {};
  onSelectSpace: (spaceId: string) => void = () => {};
  onOpenSearch: () => void = () => {};
  onSelectNote: (note: NoteItem) => void = () => {};
  onCreateNote: () => void = () => {};
  onCreateNoteInProject: (title: string, projectName: string, type: string) => void = () => {};
  onCreateFromTemplate: (templateName: string, projectName: string) => void = () => {};
  /** 在指定项目内发起系统文件导入（PDF / Word / Markdown / 文本），导入后归入该项目 */
  onImportIntoProject: (projectName: string) => void = () => {};
  onCreateProject: (name: string, color: string, icon: string) => void = () => {};
  onRenameProject: (oldName: string, newName: string) => void = () => {};
  onDeleteProject: (name: string) => void = () => {};
  onDeleteNote: (noteId: string) => void = () => {};
  onRenameNote: (note: NoteItem, newTitle: string) => void = () => {};
  onMoveNote: (note: NoteItem, category: string) => void = () => {};
  onApplyTags: (note: NoteItem, tags: string[]) => void = () => {};
  onSelectNav: (navKey: string) => void = () => {};
  onOpenSettings: () => void = () => {};
  /** 请求 Index 层挂载指定底部弹层（全屏遮罩，而非被侧栏 260vp 宽度裁剪） */
  onOpenSheet: (type: string, project: SpaceFolder | null, note: NoteItem | null) => void = () => {};
  /** 请求打开居中「新建项目」对话框 */
  onOpenCreateProject: () => void = () => {};
  /** 切换中段模式（资料树 ↔ 对话记录） */
  onSidebarModeChange: (mode: string) => void = () => {};
  onSelectSession: (session: ChatSession) => void = () => {};
  onNewSession: () => void = () => {};
  onDeleteSession: (sessionId: string) => void = () => {};
  onTogglePinSession: (session: ChatSession) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;
  @State pressedItemId: string = '';
  @State liftedItemId: string = '';
  private suppressRowClick: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  /** 抽屉宽度：手机窄屏按屏宽百分比，避免几乎盖满；宽屏用固定宽度。 */
  private drawerWidth(): Length {
    return this.isPhone ? '82%' : LayoutTokens.SIDEBAR_WIDTH;
  }
  // ------------------------------------------------------------------
  // 辅助函数：文件类型与色彩
  // ------------------------------------------------------------------

  private getFileTypeIcon(type: string): string {
    const t = type.toLowerCase();
    if (t === 'canvas' || t === '白板') {
      return '⬡';
    }
    if (t === 'doc' || t === '资料') {
      return '🗎';
    }
    if (t === 'task' || t === '待办') {
      return '☑';
    }
    return '▤';
  }

  private getFileTypeColor(type: string): string {
    const t = type.toLowerCase();
    if (t === 'canvas' || t === '白板') {
      return ResourceTypeTokens.COLOR_CANVAS;
    }
    if (t === 'doc' || t === '资料') {
      return ResourceTypeTokens.COLOR_DOC;
    }
    if (t === 'task' || t === '待办') {
      return ResourceTypeTokens.COLOR_TASK;
    }
    return ResourceTypeTokens.COLOR_MARKDOWN;
  }

  // ------------------------------------------------------------------
  // 触感物理动画属性生成器
  // ------------------------------------------------------------------

  private getItemScale(id: string): number {
    if (this.liftedItemId === id) {
      return AnimationTokens.SCALE_LIFTED;
    }
    if (this.pressedItemId === id) {
      return AnimationTokens.SCALE_PRESSED;
    }
    return 1.0;
  }

  // 返回类型必须写成 ShadowOptions 而不是 object：
  // ArkTS 不接受无类型对象字面量，声明成 object 会直接编译不过。
  private getItemShadow(id: string): ShadowOptions {
    if (this.liftedItemId === id) {
      return { radius: 14, color: this.isDarkMode ? 'rgba(0,0,0,0.55)' : 'rgba(0,0,0,0.14)', offsetY: 4 };
    }
    return { radius: 0, color: 'transparent' };
  }

  // ------------------------------------------------------------------
  // 视图构建：项目与资源文件树
  // ------------------------------------------------------------------

  @Builder
  projectRow(space: SpaceFolder) {
    Column() {
      // ---- 项目节点行 ----
      Row({ space: 4 }) {
        // 展开/折叠指示器（顺滑 90° 旋转）
        Text('▸')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
          .width(16)
          .height(16)
          .textAlign(TextAlign.Center)
          .rotate({ angle: space.isOpen ? 90 : 0 })
          .animation({ curve: curves.springMotion(0.25, 0.76) })

        // 项目专属图标与颜色指示
        Text(space.icon && space.icon.length > 0 ? space.icon : '📁')
          .fontSize(TypographyTokens.BODY_REGULAR)

        // 项目名称
        Text(space.name)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(space.id === this.activeSpaceId ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(space.id === this.activeSpaceId ? this.palette().inkPrimary : this.palette().inkSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        // 资料统计胶囊
        Text(`${space.count}`)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .borderRadius(10)
          .backgroundColor(this.palette().surfaceSubtle)

        // 在当前项目内新建内容：先让用户选类型，防止事件冒泡
        Text('＋')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width(18)
          .height(18)
          .textAlign(TextAlign.Center)
          .borderRadius(4)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.suppressRowClick = true;
            this.onOpenSheet('new_content', space, null);
          })

        // 更多操作菜单按钮 (···)，防止事件冒泡
        Text('···')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Bold)
          .fontColor(space.id === this.activeSpaceId ? this.palette().inkPrimary : this.palette().inkMuted)
          .width(20)
          .height(18)
          .textAlign(TextAlign.Center)
          .borderRadius(4)
          .backgroundColor(space.id === this.activeSpaceId ? this.palette().surfaceSubtle : Color.Transparent)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.suppressRowClick = true;
            animateTo({ curve: curves.springMotion(0.28, 0.72) }, () => {
              this.liftedItemId = `project-${space.id}`;
              this.onOpenSheet('project_menu', space, null);
            });
          })
      }
      .width('100%')
      .height(ROW_HEIGHT)
      .padding({ left: 6, right: 6 })
      .borderRadius(8)
      .backgroundColor(space.id === this.activeSpaceId ? this.palette().activeBg : Color.Transparent)
      .scale({
        x: this.getItemScale(`project-${space.id}`),
        y: this.getItemScale(`project-${space.id}`)
      })
      .shadow(this.getItemShadow(`project-${space.id}`))
      .border({
        width: 1,
        color: this.liftedItemId === `project-${space.id}`
          ? (this.isDarkMode ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)')
          : Color.Transparent
      })
      .animation({ curve: curves.springMotion(0.25, 0.76) })
      // 触控即时凹陷体感
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressedItemId = `project-${space.id}`;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedItemId = '';
        }
      })
      // 类 VSCode 风格：单点整行直接切换展开/收起，并激活选中
      .onClick(() => {
        if (this.suppressRowClick) {
          this.suppressRowClick = false;
          return;
        }
        this.onToggleSpace(space.id);
        this.onSelectSpace(space.id);
      })
      // 长按：280ms 快速浮起并呼出操作菜单
      .gesture(
        LongPressGesture({ repeat: false, duration: 280 })
          .onAction(() => {
            animateTo({ curve: curves.springMotion(0.28, 0.72) }, () => {
              this.liftedItemId = `project-${space.id}`;
              this.onOpenSheet('project_menu', space, null);
            });
          })
      )

      // ---- 下辖子资料文件列表 (收起时仅保留顶级项目名) ----
      if (space.isOpen) {
        Column({ space: 1 }) {
          if (!space.notes || space.notes.length === 0) {
            Row({ space: 4 }) {
              Text('＋')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
              Text('点击新建资料')
                .fontSize(TypographyTokens.CAPTION)
                .fontColor(this.palette().inkMuted)
            }
            .width('100%')
            .height(26)
            .padding({ left: 28, right: 8 })
            .borderRadius(6)
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
        .padding({ top: 2, bottom: 4 })
        .transition(
          TransitionEffect.OPACITY
            .combine(TransitionEffect.scale({ y: 0.8, centerY: 0 }))
            .animation({ curve: curves.springMotion(0.25, 0.76) })
        )
      }
    }
    .width('100%')
    .margin({ bottom: 2 })
  }

  @Builder
  fileRow(note: NoteItem, projectName: string) {
    Row({ space: 6 }) {
      // 文件类型专属图标（彩色）
      Text(this.getFileTypeIcon(note.type))
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.getFileTypeColor(note.type))
        .width(16)
        .textAlign(TextAlign.Center)

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
            animateTo({ curve: curves.springMotion(0.28, 0.72) }, () => {
              this.liftedItemId = `note-${note.id}`;
              this.onOpenSheet('note_menu', null, note);
            });
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
    .padding({ left: 26, right: 8 })
    .borderRadius(6)
    .backgroundColor(note.id === this.activeNoteId ? this.palette().activeBg : Color.Transparent)
    .scale({
      x: this.getItemScale(`note-${note.id}`),
      y: this.getItemScale(`note-${note.id}`)
    })
    .shadow(this.getItemShadow(`note-${note.id}`))
    .animation({ curve: curves.springMotion(0.25, 0.76) })
    // 短按凹陷
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedItemId = `note-${note.id}`;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedItemId = '';
      }
    })
    // 短按：打开阅读/编辑并选中
    .onClick(() => {
      if (this.suppressRowClick) {
        this.suppressRowClick = false;
        return;
      }
      this.onSelectNote(note);
    })
    // 长按：280ms 呼出文件操作菜单
    .gesture(
      LongPressGesture({ repeat: false, duration: 280 })
        .onAction(() => {
          animateTo({ curve: curves.springMotion(0.28, 0.72) }, () => {
            this.liftedItemId = `note-${note.id}`;
            this.onOpenSheet('note_menu', null, note);
          });
        })
    )
  }

  // ------------------------------------------------------------------
  // 视图构建：全局快捷导航行
  // ------------------------------------------------------------------

  @Builder
  navRow(icon: string, label: string, navKey: string, badge: number = 0) {
    Row({ space: 8 }) {
      Text(icon)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.activeNav === navKey ? this.palette().accent : this.palette().inkSecondary)
        .width(16)
        .textAlign(TextAlign.Center)
      Text(label)
        .fontSize(TypographyTokens.BODY_REGULAR)
        .fontColor(this.activeNav === navKey ? this.palette().inkPrimary : this.palette().inkSecondary)
        .fontWeight(this.activeNav === navKey ? FontWeight.Medium : FontWeight.Normal)
        .layoutWeight(1)
      if (badge > 0) {
        Text(`${badge}`)
          .fontSize(TypographyTokens.TINY)
          .fontColor(Color.White)
          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
          .borderRadius(8)
          .backgroundColor(navKey === NAV_TRASH ? this.palette().inkMuted :
            (navKey === NAV_FAVORITE ? this.palette().warning : this.palette().danger))
      }
    }
    .width('100%')
    .height(38)
    .padding({ left: 10, right: 10 })
    .borderRadius(8)
    .backgroundColor(this.activeNav === navKey ? this.palette().activeBg : Color.Transparent)
    .border({ width: { left: this.activeNav === navKey ? 3 : 0 }, color: { left: this.palette().accent } })
    .scale({
      x: this.getItemScale(`nav-${navKey}`),
      y: this.getItemScale(`nav-${navKey}`)
    })
    .animation({ curve: curves.springMotion(0.25, 0.76) })
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
  // 视图构建：对话记录列表（AI 墨客左栏第二模式）
  // ------------------------------------------------------------------

  /** 会话列表条目的时间副标题：今天显示时刻，其余显示日期 */
  private sessionTime(ts: number): string {
    const d: Date = new Date(ts);
    const now: Date = new Date();
    const sameDay: boolean = d.getFullYear() === now.getFullYear()
      && d.getMonth() === now.getMonth()
      && d.getDate() === now.getDate();
    if (sameDay) {
      const hh: string = d.getHours() < 10 ? `0${d.getHours()}` : `${d.getHours()}`;
      const mm: string = d.getMinutes() < 10 ? `0${d.getMinutes()}` : `${d.getMinutes()}`;
      return `${hh}:${mm}`;
    }
    return `${d.getMonth() + 1}月${d.getDate()}日`;
  }

  /** 会话最后一条消息摘要 */
  private sessionPreview(session: ChatSession): string {
    for (let i = session.messages.length - 1; i >= 0; i--) {
      const m: StoredMessage = session.messages[i];
      if (m.text.length > 0) {
        return m.text.replace(/\n/g, ' ').slice(0, 40);
      }
    }
    return '暂无消息';
  }

  @Builder
  sessionRow(session: ChatSession) {
    Column({ space: 2 }) {
      Row({ space: 6 }) {
        Text(session.pinned ? '★' : '✦')
          .fontSize(TypographyTokens.TINY)
          .fontColor(session.pinned ? this.palette().accent : this.palette().inkMuted)
          .width(14)
          .textAlign(TextAlign.Center)

        Text(session.title.length > 0 ? session.title : '新对话')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(session.id === this.activeSessionId ? this.palette().inkPrimary : this.palette().inkSecondary)
          .fontWeight(session.id === this.activeSessionId ? FontWeight.Medium : FontWeight.Normal)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (session.id === this.activeSessionId) {
          Text('✕')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .width(18).height(18)
            .textAlign(TextAlign.Center)
            .borderRadius(4)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.suppressRowClick = true;
              this.onDeleteSession(session.id);
            })
        }
      }
      .width('100%')

      Row({ space: 6 }) {
        Text(this.sessionTime(session.updatedAt))
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
        Text(this.sessionPreview(session))
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20 })
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
    .borderRadius(8)
    .backgroundColor(session.id === this.activeSessionId ? this.palette().activeBg : Color.Transparent)
    .scale({
      x: this.getItemScale(`session-${session.id}`),
      y: this.getItemScale(`session-${session.id}`)
    })
    .animation({ curve: curves.springMotion(0.25, 0.76) })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedItemId = `session-${session.id}`;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedItemId = '';
      }
    })
    .onClick(() => {
      if (this.suppressRowClick) {
        this.suppressRowClick = false;
        return;
      }
      this.onSelectSession(session);
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 280 })
        .onAction(() => {
          this.onTogglePinSession(session);
        })
    )
  }

  /** 中段模式切换器：仅在 AI 墨客下出现，用于从会话列表切回资料树 */
  @Builder
  modeToggle() {
    Row({ space: 1 }) {
      Text('资料树')
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.sidebarMode === SIDEBAR_MODE_TREE ? Color.White : this.palette().inkSecondary)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(5)
        .backgroundColor(this.sidebarMode === SIDEBAR_MODE_TREE ? this.palette().accent : Color.Transparent)
        .onClick(() => this.onSidebarModeChange(SIDEBAR_MODE_TREE))

      Text('对话')
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.sidebarMode === SIDEBAR_MODE_SESSIONS ? Color.White : this.palette().inkSecondary)
        .padding({ left: 8, right: 8, top: 3, bottom: 3 })
        .borderRadius(5)
        .backgroundColor(this.sidebarMode === SIDEBAR_MODE_SESSIONS ? this.palette().accent : Color.Transparent)
        .onClick(() => this.onSidebarModeChange(SIDEBAR_MODE_SESSIONS))
    }
    .padding(2)
    .borderRadius(7)
    .backgroundColor(this.palette().surfaceSubtle)
  }

  /** 对话记录区段头：新建对话 + 模式切换 */
  @Builder
  sessionSectionHeader() {
    Row({ space: 4 }) {
      Text('对话记录')
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
        .fontWeight(FontWeight.Medium)

      Blank()

      Row({ space: 2 }) {
        Text('＋')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().accent)
        Text('新对话')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().accent)
      }
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .borderRadius(6)
      .backgroundColor(this.palette().accentSoft)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.onNewSession())

      this.modeToggle()
    }
    .width('100%')
    .height(28)
    .padding({ left: 8, right: 4 })
    .margin({ bottom: 4 })
  }

  /** 项目资料区段头：收起全部 + 新建项目 + 模式切换 */
  @Builder
  treeSectionHeader() {
    Row({ space: 4 }) {
      Text('项目与资料')
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
        .fontWeight(FontWeight.Medium)

      Blank()

      // 全部折叠按钮（类 VSCode Collapse All）
      Row({ space: 2 }) {
        Text('⊟')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
        Text('收起')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .padding({ left: 5, right: 5, top: 3, bottom: 3 })
      .borderRadius(6)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.onCollapseAllSpaces();
      })

      // 新建项目按钮（无遮罩内联卡片，不遮蔽侧栏）
      Row({ space: 2 }) {
        Text('＋')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().accent)
        Text('新建项目')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().accent)
      }
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .borderRadius(6)
      .backgroundColor(this.palette().accentSoft)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.onOpenCreateProject();
      })

      if (this.activeNav === NAV_AI) {
        this.modeToggle()
      }
    }
    .width('100%')
    .height(28)
    .padding({ left: 8, right: 4 })
    .margin({ bottom: 4 })
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
        // ---- 顶部工作区品牌 ----
        Row({ space: 8 }) {
          BrandMark({ markSize: 22 })
          Text('墨语 · 空间')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.activeNav === NAV_HOME ? this.palette().inkPrimary : this.palette().inkSecondary)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .height(42)
        .padding({ left: 10, right: 8 })
        .borderRadius(8)
        .backgroundColor(this.activeNav === NAV_HOME ? this.palette().activeBg : Color.Transparent)
        .scale({
          x: this.getItemScale('brand-home'),
          y: this.getItemScale('brand-home')
        })
        .animation({ curve: curves.springMotion(0.25, 0.76) })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressedItemId = 'brand-home';
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressedItemId = '';
          }
        })
        .onClick(() => this.onSelectNav(NAV_HOME))
        .margin({ bottom: 4 })

        // ---- 快速搜索入口 ----
        Row({ space: 8 }) {
          Text('⌕')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkMuted)
          Text('快速搜索')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkMuted)
            .layoutWeight(1)
          Text('全库')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.palette().surface)
        }
        .width('100%')
        .height(38)
        .padding({ left: 10, right: 10 })
        .borderRadius(10)
        .backgroundColor(this.palette().surfaceSubtle)
        .border({ width: 1, color: this.palette().borderSubtle })
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.onOpenSearch())
        .margin({ bottom: 8 })

        // ---- 全局核心功能导航 ----
        Column({ space: 2 }) {
          this.navRow('◍', '知识图谱', NAV_GRAPH)
          this.navRow('⬡', '自由白板', NAV_CANVAS)
          this.navRow('✦', 'AI 墨客', NAV_AI)
          this.navRow('⭐', '收藏', NAV_FAVORITE, this.favoriteCount)
          this.navRow('☑', '待办', NAV_TODO, this.todoPendingCount)
          this.navRow('🗑', '回收站', NAV_TRASH, this.trashCount)
        }
        .width('100%')
        .margin({ bottom: 8 })

        // ---- 中段：项目资料树 ↔ 对话记录（AI 墨客下自动切到对话） ----
        if (this.sidebarMode === SIDEBAR_MODE_SESSIONS) {
          this.sessionSectionHeader()

          Scroll() {
            Column({ space: 2 }) {
              if (this.sessions.length === 0) {
                Row({ space: 4 }) {
                  Text('✦')
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().inkMuted)
                  Text('还没有对话，点「新对话」开始')
                    .fontSize(TypographyTokens.CAPTION)
                    .fontColor(this.palette().inkMuted)
                }
                .width('100%')
                .height(32)
                .padding({ left: 12, right: 8 })
              } else {
                ForEach(this.sessions, (session: ChatSession) => {
                  this.sessionRow(session)
                }, (session: ChatSession) => session.id)
              }
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        } else {
          this.treeSectionHeader()

          // 项目树滚动容器
          Scroll() {
            Column() {
              ForEach(this.spaces, (space: SpaceFolder) => {
                this.projectRow(space)
              }, (space: SpaceFolder) => spaceRenderKey(space))
            }
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }

        // ---- 底部设置入口 ----
        Row({ space: 8 }) {
          Text('⚙')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
          Text('外观与数据设置')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkSecondary)
            .layoutWeight(1)
          Text('v2.0')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .padding({ left: 6, right: 6, top: 1, bottom: 1 })
            .borderRadius(4)
            .backgroundColor(this.palette().surfaceSubtle)
        }
        .width('100%')
        .height(38)
        .padding({ left: 10, right: 10 })
        .borderRadius(8)
        .backgroundColor(this.palette().surfaceSubtle)
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
