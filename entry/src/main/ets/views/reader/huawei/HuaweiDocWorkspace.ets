/**
 * 华为风独立全屏文档与稿纸工作台 (HuaweiDocWorkspace)
 *
 * 核心设计：
 *   1. 沉浸全屏阅读体验：
 *      - 顶栏与底栏支持平滑隐藏与呼出，释放 100% 屏幕空间。
 *      - 触控边缘感知（顶部/底部相近区域滑动或点击即刻呼出）。
 *      - 非笔触防误触（严格过滤手写笔 Pen 触控，避免书写涂画时意外弹出工具栏）。
 *   2. 华为自带 PDF 风格与高级极简质感：
 *      - 告别单调图标占位：全部控件采用胶囊药丸、图文联动与微排版。
 *      - 顶栏：退出全屏药丸、文档标题与格式勋章、居中分屏胶囊（全屏/AI伴读/稿纸）、撤销重做、检索分享、沉浸切换。
 *      - 二级 Tab：文件 (蓝) / 查看 (青) / 播放 (橙) / 签批 (红) / AI 助学 (紫)。
 *      - 功能区 Action Ribbon：丰富生动的操作卡片，带有清晰功能指示与说明。
 *   3. 浮动翻页与阅读控制台 (HUD Console)：
 *      - ◀ 上一页 / 下一页 ▶
 *      - 页面进度滑块 (Slider) 与百分比指示
 *      - 快捷页码跳转与连续/单页排版模式切换
 *   4. 双模分屏与统一模态弹窗。
 */
import { curves, promptAction } from '@kit.ArkUI';
import { ColorPalette, TypographyTokens, LayoutTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import { AnnotationTool } from '../../../common/types/PdfAnnotationTypes';
import { PdfAnnotatorView } from '../pdf/PdfAnnotatorView';
import { HandwritingCanvas } from '../HandwritingCanvas';
import { HuaweiAiSplitPanel } from './HuaweiAiSplitPanel';
import { HuaweiDocActionDialog, HuaweiDocDialogType } from './HuaweiDocActionDialog';

export type HuaweiTabType = 'file' | 'view' | 'play' | 'annotate' | 'ai';
export type SplitModeType = 'none' | 'ai' | 'scratchpad';

@Component
export struct HuaweiDocWorkspace {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  onClose: () => void = () => {};
  onSaved: (note: NoteItem, content: string) => void = () => {};
  onSaveStateChange: (state: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  // 顶底栏沉浸与显隐状态
  @State barsVisible: boolean = true;

  // 模式与批注状态（鸿蒙笔控设计）
  @State isAnnotateMode: boolean = false;
  @State isPenPaletteExpanded: boolean = true;
  @State currentTool: AnnotationTool = 'pen';
  @State selectedColor: string = '#DC2626';
  @State selectedWidth: number = 3;
  @State undoTrigger: number = 0;
  @State clearTrigger: number = 0;
  @State moreMenuOpen: boolean = false;
  @State exitDialogOpen: boolean = false;

  // 导航与功能区状态
  @State activeTab: HuaweiTabType = 'file';
  @State splitMode: SplitModeType = 'none';
  @State activeModal: HuaweiDocDialogType = '';

  // 页码与阅读控制
  @State currentPage: number = 4;
  @State totalPages: number = 9;
  @State zoomPercent: number = 100;
  @State isContinuousScroll: boolean = true;
  @State isPresentationMode: boolean = false;
  @State jumpDialogOpen: boolean = false;

  // 稿纸底纹状态
  @State paperBackground: string = 'grid'; // 'grid' | 'ruled' | 'blank'

  // 轻量提示
  @State toastText: string = '';
  @State toastOpen: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    if (this.isDocumentOrExam()) {
      this.currentPage = 4;
      this.totalPages = 9;
    } else {
      this.currentPage = 1;
      this.totalPages = 1;
    }
  }

  onNoteChanged(): void {
    this.activeModal = '';
    this.jumpDialogOpen = false;
  }

  /** 是否为 PDF / Word 试卷或参考资料 */
  private isDocumentOrExam(): boolean {
    const t = this.note.type.toLowerCase();
    const cat = this.note.category;
    return t === 'pdf' || t === 'doc' || t === 'docx' || cat === '试卷题库' || this.note.id === 'note-seed-exam' || this.note.id === 'note-seed-pdf';
  }

  /** 是否为纯稿纸/白纸手写型笔记 */
  private isHandwritingNote(): boolean {
    const t = this.note.type.toLowerCase();
    return t === 'canvas' || t === '白板' || t === '白纸笔记' || t === 'handwriting' || t === '稿纸';
  }

  /**
   * 判断是否为手指触控（严格过滤手写笔 Pen 触控，避免笔迹落笔时误触发呼出）
   */
  private isFingerTouch(event: TouchEvent): boolean {
    try {
      // 鸿蒙 ArkUI 中 SourceType.Pen 为 3，过滤手写笔触控
      if (event.source === 3) {
        return false;
      }
    } catch (e) {
      // 容错降级
    }
    return true;
  }

  /** 切换顶底栏显隐 */
  private toggleBars(visible: boolean): void {
    animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
      this.barsVisible = visible;
    });
  }

  /** 上一页 */
  private prevPage(): void {
    if (this.currentPage > 1) {
      this.currentPage--;
      this.showToast(`已翻至第 ${this.currentPage} 页`);
    }
  }

  /** 下一页 */
  private nextPage(): void {
    if (this.currentPage < this.totalPages) {
      this.currentPage++;
      this.showToast(`已翻至第 ${this.currentPage} 页`);
    }
  }

  /** 跳转指定页码 */
  private jumpToPage(page: number): void {
    const p = Math.max(1, Math.min(this.totalPages, Math.round(page)));
    this.currentPage = p;
    this.jumpDialogOpen = false;
    this.showToast(`已跳转至第 ${this.currentPage} 页`);
  }

  /** 清空当前页批注 */
  private clearCurrentPageAnnotations(): void {
    this.clearTrigger++;
    this.showToast(`第 ${this.currentPage} 页手写批注已清空`);
  }

  private showToast(msg: string): void {
    this.toastText = msg;
    this.toastOpen = true;
    try {
      promptAction.showToast({ message: msg, duration: 1500 });
    } catch (e) {
      // ignore
    }
    setTimeout(() => {
      this.toastOpen = false;
    }, 2000);
  }

  // ------------------------------------------------------------------
  // 顶栏构建：退出、标题勋章、居中分屏胶囊、快捷工具
  // ------------------------------------------------------------------

  // ------------------------------------------------------------------
  // 顶栏构建：退出、标题勋章、模式分段（阅读/批注）、分屏胶囊、更多
  // ------------------------------------------------------------------

  @Builder
  topNavigationBar() {
    Row({ space: 12 }) {
      // 1. 退出全屏胶囊（Obsidian 简约返回样式，触发退出保存确认）
      Row({ space: 5 }) {
        Text('←')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
        Text('退出')
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
      }
      .padding({ left: 10, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: 1, color: this.palette().borderSubtle })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.exitDialogOpen = true;
      })

      // 2. 文档标题与 Obsidian 质感格式勋章
      Row({ space: 8 }) {
        Text(this.note.title.startsWith('《') ? this.note.title : `《${this.note.title}》`)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.isDocumentOrExam() ? 'PDF · 考研真题' : (this.isHandwritingNote() ? '稿纸 · 手写演算' : this.note.type.toUpperCase()))
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Normal)
          .fontColor(this.palette().inkSecondary)
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor(this.palette().surfaceSubtle)
          .border({ width: 1, color: this.palette().borderSubtle })
      }
      .layoutWeight(1)

      // 3. 居中模式分段选择器：阅读模式 vs 手写批注 (Obsidian 极简几何图标)
      Row({ space: 3 }) {
        // 阅读模式
        Row({ space: 5 }) {
          Text('▤')
            .fontSize(12)
            .fontColor(!this.isAnnotateMode ? this.palette().accent : this.palette().inkSecondary)
          Text('阅读')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(!this.isAnnotateMode ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(!this.isAnnotateMode ? this.palette().accent : this.palette().inkSecondary)
        }
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .borderRadius(14)
        .backgroundColor(!this.isAnnotateMode ? this.palette().surface : Color.Transparent)
        .border({ width: 1, color: !this.isAnnotateMode ? this.palette().borderSubtle : Color.Transparent })
        .shadow(!this.isAnnotateMode ? { radius: 6, color: this.isDarkMode ? 'rgba(0,0,0,0.4)' : 'rgba(0,0,0,0.06)', offsetY: 1 } : { radius: 0, color: 'transparent' })
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
            this.isAnnotateMode = false;
            this.showToast('已进入阅读模式：触控滑动翻页，防误触');
          });
        })

        // 手写批注
        Row({ space: 5 }) {
          Text('✎')
            .fontSize(12)
            .fontColor(this.isAnnotateMode ? '#DC2626' : this.palette().inkSecondary)
          Text('批注')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(this.isAnnotateMode ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.isAnnotateMode ? '#DC2626' : this.palette().inkSecondary)
        }
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
        .borderRadius(14)
        .backgroundColor(this.isAnnotateMode ? this.palette().surface : Color.Transparent)
        .border({ width: 1, color: this.isAnnotateMode ? this.palette().borderSubtle : Color.Transparent })
        .shadow(this.isAnnotateMode ? { radius: 6, color: this.isDarkMode ? 'rgba(0,0,0,0.4)' : 'rgba(0,0,0,0.06)', offsetY: 1 } : { radius: 0, color: 'transparent' })
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
            this.isAnnotateMode = true;
            this.isPenPaletteExpanded = true;
            this.showToast('已进入手写批注模式：可随时落笔书写或点击退出');
          });
        })
      }
      .padding(3)
      .borderRadius(18)
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: 1, color: this.palette().borderSubtle })

      Blank()

      // 4. 右侧分屏模式与更多操作 (Obsidian 极简图标)
      Row({ space: 8 }) {
        // 分屏胶囊
        Row({ space: 3 }) {
          this.splitSegmentItem('⊡', '单页', 'none')
          this.splitSegmentItem('✦', 'AI 伴读', 'ai')
          this.splitSegmentItem('▦', '稿纸', 'scratchpad')
        }
        .padding(3)
        .borderRadius(18)
        .backgroundColor(this.palette().surfaceSubtle)
        .border({ width: 1, color: this.palette().borderSubtle })

        // 沉浸阅读隐藏顶底栏
        Row({ space: 4 }) {
          Text('⛶')
            .fontSize(12)
            .fontColor(this.palette().accent)
          Text('沉浸')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().accent)
        }
        .padding({ left: 10, right: 12, top: 5, bottom: 5 })
        .borderRadius(14)
        .backgroundColor(this.palette().accentSoft)
        .border({ width: 1, color: this.palette().borderSubtle })
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.toggleBars(false);
          this.showToast('已进入沉浸全屏，触碰屏幕顶/底边缘即可唤回');
        })

        // 更多操作入口（Obsidian 风格中点省略号）
        Row({ space: 4 }) {
          Text('⋯')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
          Text('更多')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary)
        }
        .padding({ left: 10, right: 12, top: 5, bottom: 5 })
        .borderRadius(14)
        .backgroundColor(this.palette().surfaceSubtle)
        .border({ width: 1, color: this.palette().borderSubtle })
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.moreMenuOpen = !this.moreMenuOpen;
        })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.palette().surface)
    .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })
  }

  @Builder
  splitSegmentItem(icon: string, label: string, mode: SplitModeType) {
    Row({ space: 4 }) {
      Text(icon)
        .fontSize(12)
        .fontColor(this.splitMode === mode ? this.palette().accent : this.palette().inkSecondary)
      Text(label)
        .fontSize(TypographyTokens.CAPTION)
        .fontWeight(this.splitMode === mode ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.splitMode === mode ? this.palette().accent : this.palette().inkSecondary)
    }
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .borderRadius(14)
    .backgroundColor(this.splitMode === mode ? this.palette().surface : Color.Transparent)
    .border({ width: 1, color: this.splitMode === mode ? this.palette().borderSubtle : Color.Transparent })
    .shadow(this.splitMode === mode ? { radius: 6, color: this.isDarkMode ? 'rgba(0,0,0,0.4)' : 'rgba(0,0,0,0.06)', offsetY: 1 } : { radius: 0, color: 'transparent' })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
        this.splitMode = mode;
      });
    })
  }

  // ------------------------------------------------------------------
  // 灵动悬浮笔盘 (Floating Pen Palette) - 遵循鸿蒙笔控设计规范与 Obsidian 极简质感
  // ------------------------------------------------------------------

  @Builder
  floatingPenPalette() {
    Row({ space: 8 }) {
      // 1. 突出「退出批注」胶囊 (一键退出回阅读模式)
      Row({ space: 4 }) {
        Text('✕')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#DC2626')
        Text('退出')
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor('#DC2626')
      }
      .padding({ left: 10, right: 12, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.isDarkMode ? '#3B181E' : '#FEE2E2')
      .border({ width: 1, color: this.isDarkMode ? '#5C2229' : '#FCA5A5' })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
          this.isAnnotateMode = false;
          this.showToast('已退出批注，恢复阅读模式');
        });
      })

      Divider()
        .vertical(true)
        .height(18)
        .color(this.palette().borderSubtle)

      // 2. 笔工具模式选择 (钢笔 / 荧光笔 / 橡皮擦 / 漫游平移 - Obsidian 极简几何字形)
      // 钢笔
      Row({ space: 4 }) {
        Text('✎')
          .fontSize(13)
          .fontColor(this.currentTool === 'pen' ? '#FFFFFF' : this.palette().inkPrimary)
        Text('钢笔')
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(this.currentTool === 'pen' ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentTool === 'pen' ? '#FFFFFF' : this.palette().inkPrimary)
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.currentTool === 'pen' ? '#2563EB' : this.palette().surfaceSubtle)
      .border({ width: 1, color: this.currentTool === 'pen' ? '#2563EB' : this.palette().borderSubtle })
      .onClick(() => {
        this.currentTool = 'pen';
        if (this.selectedColor === '#FACC15' || this.selectedColor === '#4ADE80') {
          this.selectedColor = '#DC2626';
        }
        this.selectedWidth = 3;
      })

      // 荧光笔 (Obsidian 风格几何粗矩形块 ▰)
      Row({ space: 4 }) {
        Text('▰')
          .fontSize(13)
          .fontColor(this.currentTool === 'highlighter' ? '#FFFFFF' : this.palette().inkPrimary)
        Text('荧光')
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(this.currentTool === 'highlighter' ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentTool === 'highlighter' ? '#FFFFFF' : this.palette().inkPrimary)
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.currentTool === 'highlighter' ? '#EAB308' : this.palette().surfaceSubtle)
      .border({ width: 1, color: this.currentTool === 'highlighter' ? '#EAB308' : this.palette().borderSubtle })
      .onClick(() => {
        this.currentTool = 'highlighter';
        this.selectedColor = '#FACC15';
        this.selectedWidth = 14;
      })

      // 橡皮擦 (Obsidian 退格删除符号 ⌫)
      Row({ space: 4 }) {
        Text('⌫')
          .fontSize(13)
          .fontColor(this.currentTool === 'eraser' ? '#FFFFFF' : this.palette().inkPrimary)
        Text('橡皮')
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(this.currentTool === 'eraser' ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentTool === 'eraser' ? '#FFFFFF' : this.palette().inkPrimary)
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.currentTool === 'eraser' ? '#DC2626' : this.palette().surfaceSubtle)
      .border({ width: 1, color: this.currentTool === 'eraser' ? '#DC2626' : this.palette().borderSubtle })
      .onClick(() => {
        this.currentTool = 'eraser';
      })

      // 漫游平移 (Obsidian 极简四向漫游十字 ✥)
      Row({ space: 4 }) {
        Text('✥')
          .fontSize(13)
          .fontColor(this.currentTool === 'pan' ? '#FFFFFF' : this.palette().inkPrimary)
        Text('漫游')
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(this.currentTool === 'pan' ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.currentTool === 'pan' ? '#FFFFFF' : this.palette().inkPrimary)
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.currentTool === 'pan' ? '#475569' : this.palette().surfaceSubtle)
      .border({ width: 1, color: this.currentTool === 'pan' ? '#475569' : this.palette().borderSubtle })
      .onClick(() => {
        this.currentTool = 'pan';
      })

      Divider()
        .vertical(true)
        .height(18)
        .color(this.palette().borderSubtle)

      // 3. 颜色选择器
      if (this.currentTool === 'pen') {
        Row({ space: 6 }) {
          ForEach(['#1C1917', '#2563EB', '#DC2626', '#059669'], (c: string) => {
            Circle({ width: 18, height: 18 })
              .fill(c)
              .stroke(this.selectedColor === c ? (this.isDarkMode ? '#FFFFFF' : '#000000') : 'transparent')
              .strokeWidth(2)
              .onClick(() => {
                this.selectedColor = c;
              })
          }, (c: string) => c)
        }
      } else if (this.currentTool === 'highlighter') {
        Row({ space: 6 }) {
          ForEach(['#FACC15', '#4ADE80'], (c: string) => {
            Circle({ width: 18, height: 18 })
              .fill(c)
              .stroke(this.selectedColor === c ? (this.isDarkMode ? '#FFFFFF' : '#000000') : 'transparent')
              .strokeWidth(2)
              .onClick(() => {
                this.selectedColor = c;
              })
          }, (c: string) => c)
        }
      }

      // 4. 笔宽选择 (Obsidian 简约几何圆点 · / ● / ⬤)
      if (this.currentTool === 'pen') {
        Divider()
          .vertical(true)
          .height(18)
          .color(this.palette().borderSubtle)

        Row({ space: 5 }) {
          ForEach([2, 4, 8], (w: number) => {
            Text(w === 2 ? '· 细' : (w === 4 ? '● 中' : '⬤ 粗'))
              .fontSize(TypographyTokens.TINY)
              .fontWeight(this.selectedWidth === w ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.selectedWidth === w ? this.palette().accent : this.palette().inkSecondary)
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(6)
              .backgroundColor(this.selectedWidth === w ? this.palette().accentSoft : this.palette().surfaceSubtle)
              .border({ width: 1, color: this.selectedWidth === w ? this.palette().accent : this.palette().borderSubtle })
              .onClick(() => {
                this.selectedWidth = w;
              })
          }, (w: number) => `w_${w}`)
        }
      }

      Divider()
        .vertical(true)
        .height(18)
        .color(this.palette().borderSubtle)

      // 5. 撤销 (Obsidian 弧形单线撤销箭头 ↶)
      Row({ space: 4 }) {
        Text('↶')
          .fontSize(14)
          .fontColor(this.palette().inkPrimary)
        Text('撤销')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkPrimary)
      }
      .padding({ left: 8, right: 10, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: 1, color: this.palette().borderSubtle })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.undoTrigger++;
        this.showToast('已撤销上一笔');
      })

      // 6. 收起为悬浮球 (Obsidian 极简减号/水平杠 —)
      Row({ space: 4 }) {
        Text('—')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkMuted)
        Text('折叠')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .padding({ left: 8, right: 10, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: 1, color: this.palette().borderSubtle })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
          this.isPenPaletteExpanded = false;
        });
      })
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .borderRadius(26)
    .backgroundColor(this.isDarkMode ? 'rgba(30, 30, 35, 0.95)' : 'rgba(255, 255, 255, 0.96)')
    .backdropBlur(16)
    .shadow({
      radius: 20,
      color: this.isDarkMode ? 'rgba(0,0,0,0.6)' : 'rgba(0,0,0,0.14)',
      offsetY: 8
    })
    .border({ width: 1, color: this.palette().borderSubtle })
    .margin({ bottom: 20 })
    .zIndex(60)
    .animation({ curve: curves.springMotion(0.28, 0.76) })
  }

  // ------------------------------------------------------------------
  // 灵动悬浮球 (Floating Ball) - 华为笔记极简收折形态 (Obsidian 钢笔字形)
  // ------------------------------------------------------------------

  @Builder
  floatingBall() {
    Row({ space: 6 }) {
      Text('✎')
        .fontSize(15)
        .fontColor('#FFFFFF')
      if (!this.isAnnotateMode) {
        Text('批注')
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
      }
    }
    .padding(this.isAnnotateMode ? 12 : { left: 14, right: 16, top: 10, bottom: 10 })
    .borderRadius(24)
    .backgroundColor(this.palette().accent)
    .shadow({
      radius: 16,
      color: this.isDarkMode ? 'rgba(0,0,0,0.5)' : 'rgba(37,99,235,0.35)',
      offsetY: 6
    })
    .hoverEffect(HoverEffect.Highlight)
    .margin({ right: 24, bottom: 24 })
    .zIndex(60)
    .onClick(() => {
      animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
        if (!this.isAnnotateMode) {
          this.isAnnotateMode = true;
          this.isPenPaletteExpanded = true;
          this.showToast('已进入手写批注模式');
        } else {
          this.isPenPaletteExpanded = true;
        }
      });
    })
  }

  // ------------------------------------------------------------------
  // 「··· 更多」功能操作面板与统一入口 (Obsidian 简约命令卡片风格)
  // ------------------------------------------------------------------

  @Builder
  moreActionSheet() {
    Column() {
      // 操作卡片
      Column({ space: 16 }) {
        Row() {
          Text('文档操作与工具')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)

          Blank()

          Text('✕')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
            .width(24)
            .height(24)
            .textAlign(TextAlign.Center)
            .borderRadius(12)
            .backgroundColor(this.palette().surfaceSubtle)
            .border({ width: 1, color: this.palette().borderSubtle })
            .onClick(() => {
              this.moreMenuOpen = false;
            })
        }
        .width('100%')

        // 功能网格 (Obsidian 极简几何矢量符号卡片) - 静态双行布局，杜绝虚拟化网格与多层撕裂
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            this.moreActionItem('⭳', '保存沙箱', '持久化落盘', () => {
              this.onSaved(this.note, this.note.contentDetail);
              this.moreMenuOpen = false;
              this.showToast('文档与批注已保存至本地沙箱');
            })
            this.moreActionItem('↗', '另存为', 'PDF/Docx', () => {
              this.moreMenuOpen = false;
              this.activeModal = 'save_as';
            })
            this.moreActionItem('⇄', '格式转换', 'OCR提取', () => {
              this.moreMenuOpen = false;
              this.activeModal = 'convert';
            })
            this.moreActionItem('⧉', '输出长图', '超清拼接', () => {
              this.moreMenuOpen = false;
              this.activeModal = 'export_image';
            })
          }
          .width('100%')

          Row({ space: 10 }) {
            this.moreActionItem('⎙', '无线打印', 'A4 规格', () => {
              this.moreMenuOpen = false;
              this.activeModal = 'print';
            })
            this.moreActionItem('⌕', '全文检索', '关键词查找', () => {
              this.moreMenuOpen = false;
              this.showToast('已唤起全文关键词检索');
            })
            this.moreActionItem(this.isContinuousScroll ? '☰' : '▯', this.isContinuousScroll ? '连续滚动' : '单页排版', '切换视图', () => {
              this.isContinuousScroll = !this.isContinuousScroll;
              this.moreMenuOpen = false;
              this.showToast(this.isContinuousScroll ? '已切换为连续纵向滚动' : '已切换为单页排版');
            })
            this.moreActionItem('⎚', '清空批注', '清空本页笔迹', () => {
              this.moreMenuOpen = false;
              this.clearCurrentPageAnnotations();
            })
          }
          .width('100%')
        }
        .width('100%')
      }
      .width(440)
      .padding(20)
      .borderRadius(16)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 16, color: this.isDarkMode ? 'rgba(0,0,0,0.5)' : 'rgba(0,0,0,0.12)', offsetY: 4 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .onClick(() => {
        // 阻止点击穿透到背景遮罩
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.isDarkMode ? 'rgba(0,0,0,0.65)' : 'rgba(0,0,0,0.45)')
    .zIndex(220)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    .onClick(() => {
      this.moreMenuOpen = false;
    })
  }

  @Builder
  moreActionItem(icon: string, title: string, subtitle: string, onClick: () => void) {
    Column({ space: 5 }) {
      // Obsidian 图标小徽章
      Row() {
        Text(icon)
          .fontSize(16)
          .fontColor(this.palette().accent)
      }
      .width(32)
      .height(32)
      .borderRadius(8)
      .backgroundColor(this.palette().accentSoft)
      .justifyContent(FlexAlign.Center)

      Text(title)
        .fontSize(TypographyTokens.CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().inkPrimary)

      Text(subtitle)
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
    }
    .layoutWeight(1)
    .height(86)
    .padding({ top: 8, bottom: 8, left: 4, right: 4 })
    .borderRadius(12)
    .backgroundColor(this.palette().surfaceSubtle)
    .border({ width: 1, color: this.palette().borderSubtle })
    .justifyContent(FlexAlign.Center)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(onClick)
  }

  // ------------------------------------------------------------------
  // 底部高级浮动翻页与阅读控制台 (HUD Console) - Obsidian 极简几何字形
  // ------------------------------------------------------------------

  @Builder
  bottomReadingConsole() {
    Row({ space: 14 }) {
      // 1. 上一页胶囊按钮 (Obsidian 单线角标 ‹)
      Row({ space: 5 }) {
        Text('‹')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.currentPage <= 1 ? this.palette().inkMuted : this.palette().inkPrimary)
        Text('上一页')
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.currentPage <= 1 ? this.palette().inkMuted : this.palette().inkPrimary)
      }
      .padding({ left: 12, right: 14, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.currentPage <= 1 ? Color.Transparent : this.palette().surfaceSubtle)
      .border({ width: 1, color: this.currentPage <= 1 ? Color.Transparent : this.palette().borderSubtle })
      .enabled(this.currentPage > 1)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.prevPage())

      // 2. 页码指示与滑块进度条
      Row({ space: 10 }) {
        // 当前页码胶囊
        Text(`第 ${this.currentPage} / ${this.totalPages} 页`)
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)

        // 翻页进度滑块
        Slider({
          value: this.currentPage,
          min: 1,
          max: this.totalPages,
          step: 1,
          style: SliderStyle.OutSet
        })
        .width(160)
        .trackColor(this.palette().surfaceSubtle)
        .selectedColor(this.palette().accent)
        .onChange((val: number) => {
          this.currentPage = Math.round(val);
        })

        // 百分比胶囊
        Text(`${Math.round((this.currentPage / this.totalPages) * 100)}%`)
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().accent)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(6)
          .backgroundColor(this.palette().accentSoft)
      }

      // 3. 下一页胶囊按钮 (Obsidian 单线角标 ›)
      Row({ space: 5 }) {
        Text('下一页')
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.currentPage >= this.totalPages ? this.palette().inkMuted : this.palette().inkPrimary)
        Text('›')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.currentPage >= this.totalPages ? this.palette().inkMuted : this.palette().inkPrimary)
      }
      .padding({ left: 14, right: 12, top: 7, bottom: 7 })
      .borderRadius(16)
      .backgroundColor(this.currentPage >= this.totalPages ? Color.Transparent : this.palette().surfaceSubtle)
      .border({ width: 1, color: this.currentPage >= this.totalPages ? Color.Transparent : this.palette().borderSubtle })
      .enabled(this.currentPage < this.totalPages)
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.nextPage())

      Divider()
        .vertical(true)
        .height(18)
        .color(this.palette().borderSubtle)

      // 4. 连续/单页视图切换 (Obsidian 单线排版字形 ☰ / ▯)
      Row({ space: 5 }) {
        Text(this.isContinuousScroll ? '☰' : '▯')
          .fontSize(13)
          .fontColor(this.palette().inkSecondary)
        Text(this.isContinuousScroll ? '连续' : '单页')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkSecondary)
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: 1, color: this.palette().borderSubtle })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.isContinuousScroll = !this.isContinuousScroll;
        this.showToast(this.isContinuousScroll ? '已切换为连续滚动视图' : '已切换为单页排版');
      })

      // 5. 快速页码跳转 (Obsidian 准星定位字形 ⌖)
      Row({ space: 4 }) {
        Text('⌖')
          .fontSize(12)
          .fontColor(this.palette().inkSecondary)
        Text('跳转')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkSecondary)
      }
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: 1, color: this.palette().borderSubtle })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.jumpDialogOpen = true;
      })

      // 6. 沉浸隐藏底栏按钮
      Row({ space: 3 }) {
        Text('⌄')
          .fontSize(13)
          .fontColor(this.palette().inkMuted)
        Text('隐藏')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
      .padding({ left: 8, right: 10, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: 1, color: this.palette().borderSubtle })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        this.toggleBars(false);
      })
    }
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .borderRadius(26)
    .backgroundColor(this.isDarkMode ? 'rgba(30, 30, 35, 0.92)' : 'rgba(255, 255, 255, 0.94)')
    .backdropBlur(16)
    .border({ width: 1, color: this.palette().borderSubtle })
    .shadow({
      radius: 20,
      color: this.isDarkMode ? 'rgba(0,0,0,0.5)' : 'rgba(0,0,0,0.12)',
      offsetY: 6
    })
    .margin({ bottom: 20 })
    .translate({ y: this.barsVisible ? 0 : 96 })
    .opacity(this.barsVisible ? 1 : 0)
    .enabled(this.barsVisible)
    .animation({ curve: curves.springMotion(0.28, 0.76) })
  }

  // ------------------------------------------------------------------
  // 隐藏态下的触控呼出热区与极简浮动手柄（非笔触触发）
  // ------------------------------------------------------------------

  @Builder
  topProximityZone() {
    Stack({ alignContent: Alignment.Top }) {
      // 触控感知热区 (无色透明，覆盖顶部 52vp)
      Row()
        .width('100%')
        .height(52)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
        .onTouch((event: TouchEvent) => {
          if (this.isFingerTouch(event)) {
            if (event.type === TouchType.Down || event.type === TouchType.Move) {
              this.toggleBars(true);
            }
          }
        })

      // 居中半透明极简呼出手柄
      Row({ space: 4 }) {
        Text('▾')
          .fontSize(10)
          .fontColor(this.palette().inkSecondary)
        Text('呼出导航栏')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkSecondary)
      }
      .padding({ left: 12, right: 12, top: 4, bottom: 4 })
      .borderRadius(12)
      .backgroundColor(this.isDarkMode ? 'rgba(30,30,35,0.85)' : 'rgba(255,255,255,0.88)')
      .backdropBlur(12)
      .shadow({ radius: 8, color: 'rgba(0,0,0,0.1)', offsetY: 2 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .margin({ top: 6 })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.toggleBars(true))
    }
    .width('100%')
    .height(52)
    .position({ x: 0, y: 0 })
    .zIndex(50)
  }

  @Builder
  bottomProximityZone() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 触控感知热区 (无色透明，覆盖底部 56vp)
      Row()
        .width('100%')
        .height(56)
        .backgroundColor(Color.Transparent)
        .hitTestBehavior(HitTestMode.Transparent)
        .onTouch((event: TouchEvent) => {
          if (this.isFingerTouch(event)) {
            if (event.type === TouchType.Down || event.type === TouchType.Move) {
              this.toggleBars(true);
            }
          }
        })

      // 居中半透明极简控制台唤回手柄
      Row({ space: 6 }) {
        Text('▲')
          .fontSize(10)
          .fontColor(this.palette().inkSecondary)
        Text(`第 ${this.currentPage} / ${this.totalPages} 页 · 呼出控制台`)
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
      }
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.isDarkMode ? 'rgba(30,30,35,0.88)' : 'rgba(255,255,255,0.92)')
      .backdropBlur(12)
      .shadow({ radius: 10, color: 'rgba(0,0,0,0.12)', offsetY: 3 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .margin({ bottom: 12 })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.toggleBars(true))
    }
    .width('100%')
    .height(56)
    .position({ x: 0, y: '100%' })
    .translate({ y: -56 })
    .zIndex(50)
  }

  // ------------------------------------------------------------------
  // 快速页码跳转弹窗
  // ------------------------------------------------------------------

  @Builder
  quickJumpDialog() {
    Column() {
      // 弹窗卡片
      Column({ space: 16 }) {
        Row() {
          Text('快速跳转至指定页')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)

          Blank()

          Text('✕')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
            .width(24)
            .height(24)
            .textAlign(TextAlign.Center)
            .borderRadius(12)
            .backgroundColor(this.palette().surfaceSubtle)
            .onClick(() => {
              this.jumpDialogOpen = false;
            })
        }
        .width('100%')

        // 快速单选页码药丸
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9], (pNum: number) => {
            Text(`第 ${pNum} 页`)
              .fontSize(TypographyTokens.CAPTION)
              .fontWeight(this.currentPage === pNum ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentPage === pNum ? '#FFFFFF' : this.palette().inkPrimary)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .margin(4)
              .borderRadius(14)
              .backgroundColor(this.currentPage === pNum ? this.palette().accent : this.palette().surfaceSubtle)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.jumpToPage(pNum))
          }, (pNum: number) => `jump_page_${pNum}`)
        }
        .width('100%')
      }
      .width(320)
      .padding(20)
      .borderRadius(16)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 16, color: this.isDarkMode ? 'rgba(0,0,0,0.5)' : 'rgba(0,0,0,0.12)', offsetY: 4 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .onClick(() => {
        // 阻止点击穿透到背景遮罩
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.isDarkMode ? 'rgba(0,0,0,0.65)' : 'rgba(0,0,0,0.45)')
    .zIndex(200)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    .onClick(() => {
      this.jumpDialogOpen = false;
    })
  }

  // ------------------------------------------------------------------
  // 退出阅读器确认弹窗 (Obsidian 简约高级模态弹窗)
  // ------------------------------------------------------------------

  @Builder
  exitConfirmationDialog() {
    Column() {
      // 弹窗卡片
      Column({ space: 18 }) {
        // 头部：图标 + 标题
        Row({ space: 12 }) {
          // Obsidian 风格圆角图标徽章
          Row() {
            Text('✎')
              .fontSize(16)
              .fontColor(this.palette().accent)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(this.palette().accentSoft)
          .justifyContent(FlexAlign.Center)

          Column({ space: 4 }) {
            Text('保存文档修改？')
              .fontSize(TypographyTokens.BODY_LARGE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)

            Text('退出前是否保存当前手写批注与阅读进度？')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkSecondary)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')

        // 提示信息条 (Obsidian 沉浸淡灰/深灰提示块)
        Row({ space: 8 }) {
          Text('ℹ')
            .fontSize(12)
            .fontColor(this.palette().inkMuted)
          Text('若选择放弃，本次会话中未保存的手写笔迹与文档状态将不会落盘。')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(10)
        .backgroundColor(this.palette().surfaceSubtle)
        .border({ width: 1, color: this.palette().borderSubtle })

        // 底部操作按钮组: [ 放弃修改 ] [ 取消 ] [ 保存并退出 ]
        Row({ space: 10 }) {
          // 放弃修改 (次要危险动作)
          Button('放弃修改')
            .type(ButtonType.Normal)
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDarkMode ? '#F87171' : '#DC2626')
            .backgroundColor(this.isDarkMode ? '#3B181E' : '#FEE2E2')
            .border({ width: 1, color: this.isDarkMode ? '#5C2229' : '#FCA5A5' })
            .borderRadius(10)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.exitDialogOpen = false;
              this.showToast('已放弃本次修改');
              this.onClose();
            })

          // 取消 (关闭弹窗，留在当前阅读器)
          Button('取消')
            .type(ButtonType.Normal)
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary)
            .backgroundColor(this.palette().surfaceSubtle)
            .border({ width: 1, color: this.palette().borderSubtle })
            .borderRadius(10)
            .height(36)
            .layoutWeight(1)
            .onClick(() => {
              this.exitDialogOpen = false;
            })

          // 保存并退出 (主确认动作)
          Button('保存并退出')
            .type(ButtonType.Normal)
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .backgroundColor(this.palette().accent)
            .borderRadius(10)
            .height(36)
            .layoutWeight(1.2)
            .onClick(() => {
              this.onSaved(this.note, this.note.contentDetail);
              this.exitDialogOpen = false;
              this.showToast('文档修改已保存');
              setTimeout(() => {
                this.onClose();
              }, 200);
            })
        }
        .width('100%')
      }
      .width(400)
      .padding(22)
      .borderRadius(16)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 24, color: this.isDarkMode ? 'rgba(0,0,0,0.65)' : 'rgba(0,0,0,0.18)', offsetY: 8 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .onClick(() => {
        // 阻止点击穿透到背景遮罩
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.isDarkMode ? 'rgba(0,0,0,0.65)' : 'rgba(0,0,0,0.45)')
    .zIndex(300)
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    .onClick(() => {
      this.exitDialogOpen = false;
    })
  }

  // ------------------------------------------------------------------
  // 稿纸分屏面板
  // ------------------------------------------------------------------

  @Builder
  scratchpadSplitPane() {
    Column() {
      // 顶栏：底纹选择与清空
      Row({ space: 8 }) {
        Row() {
          Text('···')
            .fontSize(TypographyTokens.BODY_LARGE)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkMuted)
        }
        .width(36)
        .height(18)
        .justifyContent(FlexAlign.Center)

        Text('随堂演算稿纸')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)

        Blank()

        Row({ space: 4 }) {
          Text('方格')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.paperBackground === 'grid' ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .borderRadius(4)
            .backgroundColor(this.paperBackground === 'grid' ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .onClick(() => { this.paperBackground = 'grid'; })

          Text('横线')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.paperBackground === 'ruled' ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .borderRadius(4)
            .backgroundColor(this.paperBackground === 'ruled' ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .onClick(() => { this.paperBackground = 'ruled'; })

          Text('白纸')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.paperBackground === 'blank' ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .borderRadius(4)
            .backgroundColor(this.paperBackground === 'blank' ? this.palette().accentSoft : this.palette().surfaceSubtle)
            .onClick(() => { this.paperBackground = 'blank'; })
        }

        Text('✕')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
          .width(24)
          .height(24)
          .textAlign(TextAlign.Center)
          .borderRadius(12)
          .backgroundColor(this.palette().surfaceSubtle)
          .onClick(() => {
            animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
              this.splitMode = 'none';
            });
          })
      }
      .width('100%')
      .height(42)
      .padding({ left: 12, right: 12 })
      .backgroundColor(this.palette().surface)
      .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })

      // 稿纸手写画布
      Column() {
        HandwritingCanvas({
          note: this.note,
          isScratchpad: true,
          onSaved: this.onSaved,
          onSaveStateChange: this.onSaveStateChange
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().canvas)
  }

  // ------------------------------------------------------------------
  // 主布局构建
  // ------------------------------------------------------------------

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // ---- 1. 顶部极简导航栏 (单行 48vp)，支持平滑上滑隐藏 ----
        Column() {
          this.topNavigationBar()
        }
        .width('100%')
        .translate({ y: this.barsVisible ? 0 : -56 })
        .opacity(this.barsVisible ? 1 : 0)
        .enabled(this.barsVisible)
        .animation({ curve: curves.springMotion(0.28, 0.76) })

        // ---- 2. 主视口区（左文档 + 右分屏）----
        Row() {
          // 左侧主文档 / 试卷 / 稿纸编辑区
          Stack({ alignContent: Alignment.Bottom }) {
            if (this.isHandwritingNote()) {
              // 纯稿纸/白纸手写笔记
              HandwritingCanvas({
                note: this.note,
                isScratchpad: false,
                onSaved: this.onSaved,
                onSaveStateChange: this.onSaveStateChange
              })
            } else {
              // PDF / 试卷真题原盘批注
              PdfAnnotatorView({
                note: this.note,
                currentPage: this.currentPage,
                barsVisible: this.barsVisible,
                isAnnotateMode: this.isAnnotateMode,
                currentTool: this.currentTool,
                selectedColor: this.selectedColor,
                selectedWidth: this.selectedWidth,
                undoTrigger: this.undoTrigger,
                clearTrigger: this.clearTrigger,
                onSaved: this.onSaved,
                onSaveStateChange: this.onSaveStateChange
              })
            }

            // 批注模式下展示灵动悬浮笔盘；阅读模式下展示浮动翻页控制台
            if (this.isAnnotateMode) {
              if (this.isPenPaletteExpanded && this.barsVisible) {
                this.floatingPenPalette()
              }
            } else {
              this.bottomReadingConsole()
            }
          }
          .layoutWeight(this.splitMode === 'none' ? 100 : 55)
          .height('100%')
          .animation({ duration: 250, curve: Curve.EaseInOut })

          // 右侧分屏区
          if (this.splitMode !== 'none') {
            Divider()
              .vertical(true)
              .strokeWidth(1)
              .color(this.palette().borderSubtle)
              .height('100%')

            Column() {
              if (this.splitMode === 'ai') {
                HuaweiAiSplitPanel({
                  note: this.note,
                  onClose: () => {
                    this.splitMode = 'none';
                  }
                })
              } else if (this.splitMode === 'scratchpad') {
                this.scratchpadSplitPane()
              }
            }
            .layoutWeight(45)
            .height('100%')
            .transition(
              TransitionEffect.move(TransitionEdge.END)
                .combine(TransitionEffect.OPACITY)
                .animation({ duration: 250, curve: Curve.EaseInOut })
            )
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.palette().canvas)

      // ---- 3. 灵动悬浮球（在批注模式折叠态或阅读模式下提供一键唤起）----
      if (!this.isAnnotateMode || !this.isPenPaletteExpanded) {
        Stack({ alignContent: Alignment.BottomEnd }) {
          this.floatingBall()
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // ---- 4. 隐藏状态下的顶部/底部感应呼出区域（过滤笔触）----
      if (!this.barsVisible) {
        this.topProximityZone()
        this.bottomProximityZone()
      }

      // ---- 5. 快速页码跳转弹窗 ----
      if (this.jumpDialogOpen) {
        this.quickJumpDialog()
      }

      // ---- 6. 统一顶层操作模态弹窗（另存为、格式转换、长图输出、打印）----
      if (this.activeModal.length > 0) {
        HuaweiDocActionDialog({
          note: this.note,
          dialogType: this.activeModal,
          onClose: () => {
            this.activeModal = '';
          },
          onConfirm: (actionType: string, payload: string) => {
            this.showToast(`操作成功：${actionType} (${payload})`);
          }
        })
      }

      // ---- 7. 「··· 更多」功能操作面板 ----
      if (this.moreMenuOpen) {
        this.moreActionSheet()
      }

      // ---- 8. 退出阅读器保存确认弹窗 (Obsidian 风格) ----
      if (this.exitDialogOpen) {
        this.exitConfirmationDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().canvas)
  }
}
