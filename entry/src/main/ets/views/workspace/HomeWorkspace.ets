/**
 * 首页工作台 (HomeWorkspace)
 *
 * 逆向 Craft & Notion 旗舰级个人信息工作台体验：
 *   1. 沉浸品牌欢迎区与快捷灵动胶囊操作岛
 *   2. Bento 资产矩阵看板（支持一键点击联动穿梭到资料库与图谱）
 *   3. 知识书架多维筛选（全部 / 置顶 / PDF真题 / 随堂手写 / 收藏）
 *   4. 统一精巧双层卡片架构（上层封面/排版摘录 + 下层元数据条，杜绝封面遮挡文字）
 *   5. 待拓展概念脉络（点击即刻物化为真实第二大脑笔记）
 *   6. 物理弹性微交互与流畅动效 (springMotion)
 */
import { curves } from '@kit.ArkUI';
import { NoteCoverVisual } from '../reader/NoteCoverVisual';
import { ColorPalette, LayoutTokens, TypographyTokens, AnimationTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { UnresolvedLink } from '../../common/types/LinkGraph';
import { WorkspaceStats } from '../../common/types/WorkspaceStats';
import { CourseSummary } from '../../common/types/StudyTypes';
import { BrandMark } from '../brand/BrandMark';
import { noteRenderKey } from '../../common/utils/ForEachKeys';
import { NAV_LIBRARY, NAV_GRAPH } from '../../common/constants/WorkspaceConstants';

export type ShelfFilterType = 'all' | 'pinned' | 'pdf' | 'handwriting' | 'favorite';

interface FilterOption {
  key: ShelfFilterType;
  label: string;
}

const SHELF_FILTERS: FilterOption[] = [
  { key: 'all', label: '全部' },
  { key: 'pinned', label: '▣ 置顶' },
  { key: 'pdf', label: '🗎 PDF真题' },
  { key: 'handwriting', label: '✎ 随堂稿纸' },
  { key: 'favorite', label: '☆ 重点收藏' }
];

@Component
export struct HomeWorkspace {
  @Prop stats: WorkspaceStats = { noteCount: 0, linkCount: 0, unresolvedCount: 0, tagCount: 0 };
  @Prop recentNotes: NoteItem[] = [];
  @Prop unresolvedLinks: UnresolvedLink[] = [];
  @Prop courses: CourseSummary[] = [];
  onOpenStudy: (course: string) => void = () => {};

  onSelectNote: (note: NoteItem) => void = () => {};
  onCreateNote: () => void = () => {};
  onImportDocument: () => void = () => {};
  onOpenGraph: () => void = () => {};
  onChooseCover: (noteId: string) => void = () => {};
  onTogglePin: (note: NoteItem) => void = () => {};
  onToggleFavorite: (note: NoteItem) => void = () => {};
  onDeleteNote: (noteId: string) => void = () => {};
  onSmartExtract: () => void = () => {};
  onOpenNoteByTitle: (title: string) => void = () => {};
  onNavigate: (navKey: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  @State private activeShelfFilter: ShelfFilterType = 'all';
  @State private pressedCardId: string = '';
  @State private hoveredCardId: string = '';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private isPdfNote(note: NoteItem): boolean {
    const t = note.type.toLowerCase();
    return t === 'pdf' || note.title.toLowerCase().endsWith('.pdf');
  }

  private isHandwritingNote(note: NoteItem): boolean {
    const t = note.type.toLowerCase();
    return t === 'canvas' || t === '白板' || t === '白纸笔记' || t === 'handwriting' || t === '稿纸';
  }

  /** 按筛选条件过滤并保证置顶在前 */
  private displayNotes(): NoteItem[] {
    let list: NoteItem[] = this.recentNotes.slice();

    if (this.activeShelfFilter === 'pinned') {
      list = list.filter((n: NoteItem) => n.isPinned === true);
    } else if (this.activeShelfFilter === 'pdf') {
      list = list.filter((n: NoteItem) => this.isPdfNote(n));
    } else if (this.activeShelfFilter === 'handwriting') {
      list = list.filter((n: NoteItem) => this.isHandwritingNote(n));
    } else if (this.activeShelfFilter === 'favorite') {
      list = list.filter((n: NoteItem) => n.favorite === true);
    }

    list.sort((a: NoteItem, b: NoteItem) => {
      const pinA: number = a.isPinned === true ? 1 : 0;
      const pinB: number = b.isPinned === true ? 1 : 0;
      if (pinB !== pinA) {
        return pinB - pinA;
      }
      return (b.updatedAt ?? 0) - (a.updatedAt ?? 0);
    });

    return list;
  }

  // ------------------------------------------------------------------
  // 卡片子组件：双层架构 (Top Cover + Bottom Info)
  // ------------------------------------------------------------------

  /** 统一卡片入口与微交互 */
  @Builder
  shelfCard(note: NoteItem) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        // ---- 1. 上半部分：封面/排版展示区 (高 106vp) ----
        Stack({ alignContent: Alignment.TopEnd }) {
          if (note.coverUrl && note.coverUrl.length > 0) {
            // 用户自定义图片封面
            NoteCoverVisual({ source: note.coverUrl })
              .width('100%')
              .height('100%')
          } else if (this.isPdfNote(note)) {
            // PDF 专属典雅排版
            this.pdfVisualCover(note)
          } else if (this.isHandwritingNote(note)) {
            // 稿纸手写专属温暖排版
            this.handwritingVisualCover(note)
          } else {
            // Markdown 随笔 Notion 极简排版
            this.markdownVisualCover(note)
          }

          if (!this.isPdfNote(note) && !this.isHandwritingNote(note)) {
            Row() {
              Image($r('app.media.ic_cover_white'))
                .width(18)
                .height(18)
                .objectFit(ImageFit.Contain)
            }
            .width(44)
            .height(44)
            .justifyContent(FlexAlign.Center)
            .borderRadius(10)
            .backgroundColor('rgba(0,0,0,0.55)')
            .margin({ right: 8, bottom: 8 })
            .accessibilityText('选择笔记封面')
            .onClick(() => {
              this.onChooseCover(note.id);
            })
          }
        }
        .width('100%')
        .height(106)
        .borderRadius({ topLeft: 13, topRight: 13 })
        .clip(true)

        // ---- 2. 下半部分：统一元数据信息条 (高 50vp) ----
        Column({ space: 3 }) {
          Row({ space: 6 }) {
            Text(note.title.length === 0 ? '未命名笔记' : note.title)
              .fontSize(TypographyTokens.BODY_REGULAR)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)

            if (note.isPinned === true) {
              Text('▣')
                .fontSize(11)
            }
            if (note.favorite === true) {
              Text('★')
                .fontSize(11)
                .fontColor(this.palette().warning)
            }
          }
          .width('100%')

          Row({ space: 8 }) {
            Text(note.category.length === 0 ? '未分类' : note.category)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().accent)
              .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              .borderRadius(4)
              .backgroundColor(this.palette().accentSoft)
              .maxLines(1)

            Blank()

            Text(note.updateTime)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
          .width('100%')
        }
        .width('100%')
        .height(50)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(this.palette().surface)
        .borderRadius({ bottomLeft: 13, bottomRight: 13 })
        .justifyContent(FlexAlign.Center)
      }
      .width('100%')
      .height(156)
    }
    .width('100%')
    .height(156)
    .borderRadius(14)
    .backgroundColor(this.palette().surface)
    .shadow({ radius: 10, color: this.isDarkMode ? 'rgba(0,0,0,0.45)' : 'rgba(0,0,0,0.04)', offsetY: 2 })
    .border({ width: 1, color: this.palette().borderSubtle })
    .scale({
      x: this.pressedCardId === note.id ? AnimationTokens.SCALE_PRESSED : 1.0,
      y: this.pressedCardId === note.id ? AnimationTokens.SCALE_PRESSED : 1.0
    })
    .animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut })
    .bindContextMenu(this.cardContextMenu(note), ResponseType.LongPress)
    .bindContextMenu(this.cardContextMenu(note), ResponseType.RightClick)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedCardId = note.id;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedCardId = '';
      }
    })
    .onHover((isHover: boolean) => {
      this.hoveredCardId = isHover ? note.id : '';
    })
    .onClick(() => {
      this.onSelectNote(note);
    })
  }

  /** PDF 视觉封面 */
  @Builder
  pdfVisualCover(note: NoteItem) {
    Column() {
      Row() {
        Text('PDF')
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor('#DC2626')
        Blank()
        Text(note.pageInfo && note.pageInfo.length > 0 ? note.pageInfo : '真题试卷')
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isDarkMode ? '#FCA5A5' : '#DC2626')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(this.isDarkMode ? '#3A2022' : '#FEE2E2')
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10 })

      Column({ space: 4 }) {
        Text('🗎')
          .fontSize(28)
          .fontColor('#DC2626')
        Text(note.title)
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? '#241D1E' : '#FFF1F2')
    .border({ width: { bottom: 1 }, color: { bottom: this.isDarkMode ? '#362829' : '#FFE4E6' } })
  }

  /** 稿纸手写视觉封面 */
  @Builder
  handwritingVisualCover(note: NoteItem) {
    Column() {
      Row() {
        Text('稿纸演算')
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor('#D97706')
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(this.isDarkMode ? '#382B1C' : '#FEF3C7')
        Blank()
        Text('✎ 矢量墨水')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10 })

      Column({ space: 4 }) {
        Text('✎')
          .fontSize(28)
          .fontColor('#D97706')
        Text(note.title)
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? '#26221D' : '#FFFBEB')
    .border({ width: { bottom: 1 }, color: { bottom: this.isDarkMode ? '#3D3425' : '#FEF3C7' } })
  }

  /** Markdown 随笔极简排版封面 */
  @Builder
  markdownVisualCover(note: NoteItem) {
    Column() {
      Row() {
        Text('Markdown')
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().accent)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(this.palette().accentSoft)
        Blank()
        Text('▤')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10 })

      Column({ space: 4 }) {
        Text(note.previewText.length > 0 ? note.previewText : note.title)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkSecondary)
          .lineHeight(16)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().surfaceSubtle)
    .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })
  }

  /** 右键/长按菜单 */
  @Builder
  cardContextMenu(note: NoteItem) {
    Menu() {
      MenuItem({
        content: note.isPinned === true ? '▣ 取消置顶' : '▣ 置顶此文档'
      })
      .onClick(() => {
        this.onTogglePin(note);
      })

      MenuItem({
        content: note.favorite === true ? '★ 取消收藏' : '☆ 加入收藏'
      })
      .onClick(() => {
        this.onToggleFavorite(note);
      })

      if (!this.isPdfNote(note) && !this.isHandwritingNote(note)) {
        MenuItem({ content: '更换封面' }).onClick(() => this.onChooseCover(note.id))
      }

      MenuItem({
        content: '⌫ 移至回收站'
      })
      .onClick(() => {
        this.onDeleteNote(note.id);
      })
    }
  }

  // ------------------------------------------------------------------
  // Bento 智能统计卡片
  // ------------------------------------------------------------------

  @Builder
  statBentoCard(icon: Resource, label: string, value: string, hint: string, iconBg: string, targetNav: string) {
    Column({ space: 8 }) {
      Row() {
        Row() {
          Image(icon)
            .width(18)
            .height(18)
            .objectFit(ImageFit.Contain)
        }
        .width(32)
        .height(32)
        .borderRadius(8)
        .backgroundColor(iconBg)
        .justifyContent(FlexAlign.Center)

        Blank()

        Text(`${label === '本地笔记' ? this.recentNotes.length : label === '双向链接' ? this.stats.linkCount : label === '待创建概念' ? this.stats.unresolvedCount : this.stats.tagCount}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column({ space: 2 }) {
        Text(label)
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
          .maxLines(1)
        Text(hint)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(92)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .borderRadius(14)
    .backgroundColor(this.palette().surface)
    .border({ width: 1, color: this.palette().borderSubtle })
    .shadow({ radius: 6, color: this.isDarkMode ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.03)', offsetY: 2 })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      if (targetNav.length > 0) {
        this.onNavigate(targetNav);
      }
    })
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          // ---- 1. 顶层品牌与快捷操作岛 ----
          Column({ space: 14 }) {
            Row({ space: 14 }) {
              BrandMark({ markSize: 46 })
              Column({ space: 4 }) {
                Row({ space: 8 }) {
                  Text('墨语')
                    .fontSize(TypographyTokens.TITLE_HERO)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette().inkPrimary)
                  Text('课程研读')
                    .fontSize(TypographyTokens.CAPTION)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.palette().accent)
                    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                    .borderRadius(999)
                    .backgroundColor(this.palette().accentSoft)
                }
                .alignItems(VerticalAlign.Bottom)

                Text('整理课程资料，回到原文核对，让每次复习都有据可循。')
                  .fontSize(TypographyTokens.BODY_REGULAR)
                  .fontColor(this.palette().inkSecondary)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 手机两列换行，避免第四项被裁剪；图标使用同一套 24px 线框。
            Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 8, unit: 1 }, cross: { value: 8, unit: 1 } } }) {
              // 主要行动：记随笔
              Row({ space: 5 }) {
                Image($r('app.media.ic_note_white'))
                  .width(18)
                  .height(18)
                Text('记随笔')
                  .fontSize(TypographyTokens.CAPTION)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
              }
              .width(this.isPhone ? '48%' : 112)
              .height(44)
              .justifyContent(FlexAlign.Center)
              .padding({ left: 14, right: 14 })
              .borderRadius(18)
              .backgroundColor(this.palette().accent)
              .shadow({ radius: 6, color: 'rgba(37,99,235,0.22)', offsetY: 2 })
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.onCreateNote())

              // 智能提取
              Row({ space: 5 }) {
                Image($r('app.media.ic_sparkle'))
                  .width(18)
                  .height(18)
                Text('智能提取')
                  .fontSize(TypographyTokens.CAPTION)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().accent)
              }
              .width(this.isPhone ? '48%' : 112)
              .height(44)
              .justifyContent(FlexAlign.Center)
              .padding({ left: 14, right: 14 })
              .borderRadius(18)
              .backgroundColor(this.palette().accentSoft)
              .border({ width: 1, color: this.palette().borderSubtle })
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.onSmartExtract())

              // 导入文档
              Row({ space: 5 }) {
                Image($r('app.media.ic_import'))
                  .width(18)
                  .height(18)
                Text('导入文档')
                  .fontSize(TypographyTokens.CAPTION)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().inkPrimary)
              }
              .width(this.isPhone ? '48%' : 112)
              .height(44)
              .justifyContent(FlexAlign.Center)
              .padding({ left: 14, right: 14 })
              .borderRadius(18)
              .backgroundColor(this.palette().surface)
              .border({ width: 1, color: this.palette().borderSubtle })
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.onImportDocument())

              // 星系图谱
              Row({ space: 5 }) {
                Image($r('app.media.ic_graph'))
                  .width(18)
                  .height(18)
                Text('星系图谱')
                  .fontSize(TypographyTokens.CAPTION)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().accent)
              }
              .width(this.isPhone ? '48%' : 112)
              .height(44)
              .justifyContent(FlexAlign.Center)
              .padding({ left: 14, right: 14 })
              .borderRadius(18)
              .backgroundColor(this.palette().surface)
              .border({ width: 1, color: this.palette().borderSubtle })
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.onOpenGraph())
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 20 })

          Column({ space: 8 }) {
            Row() {
              Text('课程学习与复习').fontSize(17).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
              Button('全部题卡').height(44).onClick(() => this.onOpenStudy(''))
            }.width('100%')
            Text('按资料分类组织课程；在侧栏新建项目即可建立课程资料区。').fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
            GridRow({ columns: this.isPhone ? 1 : 2, gutter: 8 }) {
              ForEach(this.courses.slice(0, 4), (course: CourseSummary) => {
                GridCol() {
                  Row({ space: 10 }) {
                    Image($r('app.media.ic_note')).width(22).height(22)
                    Column({ space: 4 }) {
                      Text(course.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).maxLines(1)
                      Text(`${course.noteCount} 份资料 · ${course.cardCount} 道题卡 · ${course.todoCount} 项关联待办`).fontSize(12).fontColor(this.palette().inkSecondary).maxLines(2)
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                    Text(course.dueCount ? `${course.dueCount} 道待复习` : '创建题卡').fontSize(12).fontColor(this.palette().accent)
                  }.width('100%').padding(12).constraintSize({ minHeight: 72 }).borderRadius(12).backgroundColor(this.palette().surfaceSubtle)
                    .accessibilityText(`${course.name}，${course.dueCount} 道待复习题卡`).onClick(() => this.onOpenStudy(course.name))
                }
              }, (course: CourseSummary) => course.name)
            }.width('100%')
          }.width('100%').margin({ bottom: 18 })

          // ---- 2. Bento 资产矩阵看板 ----
          GridRow({ columns: this.isPhone ? 2 : 4, gutter: this.isPhone ? 10 : 12 }) {
            GridCol() {
              this.statBentoCard($r('app.media.ic_note'), '本地笔记', `${this.stats.noteCount}`, 'Markdown 事实源', 'rgba(37,99,235,0.12)', NAV_LIBRARY)
            }
            GridCol() {
              this.statBentoCard($r('app.media.ic_link'), '双向链接', `${this.stats.linkCount}`, '[[概念]] 已解析', 'rgba(99,102,241,0.12)', NAV_GRAPH)
            }
            GridCol() {
              this.statBentoCard($r('app.media.ic_sparkle'), '待创建概念', `${this.stats.unresolvedCount}`, '思维脉络待扩充', 'rgba(217,119,6,0.12)', NAV_GRAPH)
            }
            GridCol() {
              this.statBentoCard($r('app.media.ic_tag'), '聚合标签', `${this.stats.tagCount}`, '#标签 自动归档', 'rgba(5,150,105,0.12)', NAV_LIBRARY)
            }
          }
          .width('100%')
          .margin({ bottom: 22 })

          // ---- 3. 知识书架与多维筛选 ----
          Column({ space: 8 }) {
            Text('知识书架')
              .fontSize(TypographyTokens.BODY_LARGE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)

            // 筛选标签栏 (横向滚动)
            Scroll() {
              Row({ space: 4 }) {
                ForEach(SHELF_FILTERS, (item: FilterOption) => {
                  Text(item.label)
                    .fontSize(TypographyTokens.TINY)
                    .fontWeight(this.activeShelfFilter === item.key ? FontWeight.Bold : FontWeight.Normal)
                    .fontColor(this.activeShelfFilter === item.key ? this.palette().accent : this.palette().inkSecondary)
                    .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                    .borderRadius(8)
                    .backgroundColor(this.activeShelfFilter === item.key ? this.palette().accentSoft : this.palette().surfaceSubtle)
                    .hoverEffect(HoverEffect.Highlight)
                    .onClick(() => {
                      animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
                        this.activeShelfFilter = item.key;
                      });
                    })
                }, (item: FilterOption) => item.key)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ bottom: 12 })

          if (this.displayNotes().length === 0) {
            Column({ space: 8 }) {
              Text('该分类下暂无文档')
                .fontSize(TypographyTokens.BODY_REGULAR)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().inkPrimary)
              Text('新建或导入一篇文档，立刻开启知识沉淀。')
                .fontSize(TypographyTokens.CAPTION)
                .fontColor(this.palette().inkMuted)
            }
            .width('100%')
            .padding(28)
            .borderRadius(14)
            .backgroundColor(this.palette().surface)
            .border({ width: 1, color: this.palette().borderSubtle })
            .alignItems(HorizontalAlign.Center)
            .margin({ bottom: 20 })
          } else {
            GridRow({ columns: this.isPhone ? 1 : 3, gutter: this.isPhone ? 10 : 14 }) {
              ForEach(this.displayNotes(), (note: NoteItem) => {
                GridCol() {
                  this.shelfCard(note)
                }
              }, (note: NoteItem) => noteRenderKey(note))
            }
            .width('100%')
            .margin({ bottom: 24 })
          }

          // ---- 4. 待创建的概念网络 (思维脉络) ----
          if (this.unresolvedLinks.length > 0) {
            Column({ space: 8 }) {
              Row() {
                Text('待拓展的思维脉络')
                  .fontSize(TypographyTokens.BODY_REGULAR)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.palette().inkPrimary)
                Blank()
                Text(`${this.unresolvedLinks.length} 处概念引用待物化`)
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkMuted)
              }
              .width('100%')

              Column({ space: 6 }) {
                ForEach(this.unresolvedLinks.slice(0, 4), (link: UnresolvedLink) => {
                  Row({ space: 8 }) {
                    Text('○')
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().link)
                    Text(`[[${link.target}]]`)
                      .fontSize(TypographyTokens.CAPTION)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.palette().link)
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`来自 ${link.sourceTitle}`)
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().inkMuted)
                      .maxLines(1)
                    Text('＋ 创建')
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().accent)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(4)
                      .backgroundColor(this.palette().accentSoft)
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .borderRadius(8)
                  .backgroundColor(this.palette().surface)
                  .border({ width: 1, color: this.palette().borderSubtle })
                  .hoverEffect(HoverEffect.Highlight)
                  .onClick(() => {
                    this.onOpenNoteByTitle(link.target);
                  })
                }, (link: UnresolvedLink) => `${link.sourceNoteId}-${link.target}`)
              }
              .width('100%')
            }
            .width('100%')
            .margin({ top: 4, bottom: 20 })
            .alignItems(HorizontalAlign.Start)
          }
        }
        .width('100%')
        .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH + 200 })
        .alignItems(HorizontalAlign.Start)
        .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 24, bottom: 48 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor(this.palette().canvas)
  }
}
