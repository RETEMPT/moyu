/**
 * 原生 PDF / 试卷原盘直接批注工作台 (PdfAnnotatorView)
 *
 * 核心设计：
 *   1. 华为笔记风格的悬浮灵动胶囊工具栏 (Floating Capsule HUD)：
 *      - 钢笔模式 (4 色：炭黑、经典蓝、朱红、翡翠绿)
 *      - 荧光笔模式 (半透明黄、薄荷绿，保证不遮挡试卷文字)
 *      - 像素/单笔橡皮擦与撤销 (Undo) 栈
 *      - 漫游手势模式 (Pan mode)：支持单指平移与双指捏合缩放，硬件级防手掌误触
 *   2. 多页 A4 物理排版连续视口 (Continuous Multi-Page Viewport)：
 *      - 支持无级缩放 (0.7x ~ 2.5x) 与居中自适应
 *   3. 归一化矢量数据自动持久化：
 *      - 防抖自动落盘至 NoteItem.pageAnnotations
 */
import { curves } from '@kit.ArkUI';
import { ColorPalette, TypographyTokens, AnimationTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import {
  AnnotationTool,
  DocumentAnnotationData,
  PageAnnotationStroke,
  PdfPageModel
} from '../../../common/types/PdfAnnotationTypes';
import { PdfPageCanvas } from './PdfPageCanvas';

const PEN_COLORS: string[] = ['#DC2626', '#2563EB', '#1C1917', '#059669'];
const HIGHLIGHTER_COLORS: string[] = ['#FACC15', '#4ADE80'];
const STROKE_WIDTHS: number[] = [2, 4, 8];

@Component
export struct PdfAnnotatorView {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop @Watch('onCurrentPageChanged') currentPage: number = 1;
  @Prop barsVisible: boolean = true;
  onSaved: (note: NoteItem, content: string) => void = () => {};
  onSaveStateChange: (state: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  // 交互与工具栏状态
  @Prop isAnnotateMode: boolean = false;
  @Prop currentTool: AnnotationTool = 'pen';
  @Prop selectedColor: string = '#DC2626';
  @Prop selectedWidth: number = 3;
  @Prop @Watch('onUndoTriggered') undoTrigger: number = 0;
  @Prop @Watch('onClearTriggered') clearTrigger: number = 0;
  @State zoomScale: number = 1.0;
  @State currentPageIdx: number = 0;

  // 滚动控制器
  private scroller: Scroller = new Scroller();

  // 批注数据集（按页）
  @State pageStrokes: Record<number, PageAnnotationStroke[]> = {};
  // 撤销历史栈
  private undoStack: PageAnnotationStroke[] = [];
  private saveTimer: number = -1;

  onCurrentPageChanged(): void {
    const idx = Math.max(0, Math.min(this.pages.length - 1, this.currentPage - 1));
    this.currentPageIdx = idx;
    try {
      this.scroller.scrollTo({
        xOffset: 0,
        yOffset: idx * 920,
        animation: { duration: 300, curve: Curve.EaseInOut }
      });
    } catch (e) {
      // ignore
    }
  }

  // 模拟真实考研试卷分页排版模型
  @State pages: PdfPageModel[] = [
    {
      pageIndex: 0,
      pageNumberText: '第 1 页 · 共 2 页',
      sections: [
        {
          type: 'header',
          title: '一、单项选择题（每题 5 分，共 40 分）',
          text: '在每小题给出的四个选项中，只有一项是符合题目要求的。请在题干中划线并在答题区直接书写解析。'
        },
        {
          type: 'question',
          tag: '操作系统 · 死锁',
          score: '5分',
          text: '1. 系统中有 4 个进程 P1~P4，竞争 3 类资源 R1(6), R2(4), R3(4)。若当前 Allocation 矩阵为 [ [2,1,0], [1,0,2], [1,1,0], [0,1,1] ]，则此时系统处于哪种状态？\n' +
            'A. 一定处于安全状态，存在至少一条安全序列\n' +
            'B. 发生死锁，涉及进程为 P1 和 P3\n' +
            'C. 不安全状态，但尚未发生死锁\n' +
            'D. 资源分配出现严重越界异常'
        },
        {
          type: 'blank',
          text: '【答题与演算区域】请直接在此处用笔写下 Banker\'s Algorithm 计算步骤...'
        },
        {
          type: 'question',
          tag: '数据结构 · 树与图',
          score: '5分',
          text: '2. 已知某二叉树的前序遍历序列为 A B D E C F，中序遍历序列为 D B E A F C，则该二叉树的后序遍历序列为？\n' +
            'A. D E B F C A\n' +
            'B. D E B C F A\n' +
            'C. E D B F C A\n' +
            'D. B D E F C A'
        }
      ]
    },
    {
      pageIndex: 1,
      pageNumberText: '第 2 页 · 共 2 页',
      sections: [
        {
          type: 'header',
          title: '二、综合解答与推导题（共 20 分）',
          text: '解答应写出文字说明、演算步骤或推导证明过程。请使用红笔订正，蓝笔作答。'
        },
        {
          type: 'question',
          tag: '线性代数 · 特征值',
          score: '10分',
          text: '3. 设三阶实对称矩阵 A 的特征值为 λ1 = 1, λ2 = 2, λ3 = -2，对应的特征向量分别为 α1, α2, α3。\n' +
            '（1）证明特征向量 α1 与 α3 正交；\n' +
            '（2）若矩阵 B = A³ - 2A² + E，求矩阵 B 的行列式 |B| 的值。'
        },
        {
          type: 'blank',
          text: '【解题推导空白区】请在此书写特征多项式分解与正交化证明...'
        },
        {
          type: 'question',
          tag: '系统调用 · 内核态',
          score: '10分',
          text: '4. 简述从用户态发起 write() 系统调用至数据真正写入页缓存（Page Cache）的完整中断与陷阱（Trap）流程。'
        },
        {
          type: 'blank',
          text: '【流程草图区】请在此手绘 Trap 门、中断向量表与内核栈切换示意图...'
        }
      ]
    }
  ];

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.loadAnnotations();
  }

  onNoteChanged(): void {
    this.loadAnnotations();
  }

  /** 从笔记中加载归一化矢量批注 */
  private loadAnnotations(): void {
    const raw = this.note.pageAnnotations;
    if (raw && raw.length > 0) {
      try {
        const parsed = JSON.parse(raw) as DocumentAnnotationData;
        if (parsed && parsed.pages) {
          this.pageStrokes = parsed.pages;
          return;
        }
      } catch (e) {
        console.error(`加载文档批注数据失败: ${JSON.stringify(e)}`);
      }
    }
    this.pageStrokes = { 0: [], 1: [] };
  }

  /** 收到单笔新增时追加并触发防抖持久化 */
  private handleStrokeAdded(stroke: PageAnnotationStroke): void {
    const pIdx = stroke.pageIndex;
    const current = this.pageStrokes[pIdx] ? [...this.pageStrokes[pIdx]] : [];
    current.push(stroke);
    this.pageStrokes[pIdx] = current;
    this.undoStack.push(stroke);
    this.scheduleSave();
  }

  /** 橡皮擦点位命中擦除 */
  private handleEraseAtPoint(pageIndex: number, u: number, v: number): void {
    const current = this.pageStrokes[pageIndex];
    if (!current || current.length === 0) {
      return;
    }
    // 阈值：归一化距离 0.04 内的笔画予以清除
    const remaining = current.filter((stroke) => {
      for (let i = 0; i < stroke.points.length; i++) {
        const pt = stroke.points[i];
        const distSq = (pt.u - u) * (pt.u - u) + (pt.v - v) * (pt.v - v);
        if (distSq < 0.0016) {
          return false;
        }
      }
      return true;
    });

    if (remaining.length !== current.length) {
      this.pageStrokes[pageIndex] = remaining;
      this.scheduleSave();
    }
  }

  /** 撤销上一笔 */
  private handleUndo(): void {
    if (this.undoStack.length === 0) {
      return;
    }
    const lastStroke = this.undoStack.pop();
    if (!lastStroke) {
      return;
    }
    const pIdx = lastStroke.pageIndex;
    const current = this.pageStrokes[pIdx];
    if (current && current.length > 0) {
      this.pageStrokes[pIdx] = current.filter((s) => s.id !== lastStroke.id);
      this.scheduleSave();
    }
  }

  onUndoTriggered(): void {
    this.handleUndo();
  }

  onClearTriggered(): void {
    this.handleClearCurrentPage();
  }

  /** 清空当前页全部批注 */
  private handleClearCurrentPage(): void {
    const pIdx = this.currentPageIdx;
    this.pageStrokes[pIdx] = [];
    this.undoStack = this.undoStack.filter((s) => s.pageIndex !== pIdx);
    this.scheduleSave();
  }

  /** 计划防抖自动落盘 */
  private scheduleSave(): void {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
    }
    this.onSaveStateChange('批注保存中...');
    this.saveTimer = setTimeout(() => {
      this.flushSave();
    }, 800);
  }

  /** 序列化并存入 NoteItem.pageAnnotations */
  private flushSave(): void {
    const data: DocumentAnnotationData = {
      version: 1,
      pageCount: this.pages.length,
      pages: this.pageStrokes
    };
    const serialized = JSON.stringify(data);
    const updatedNote: NoteItem = {
      id: this.note.id,
      title: this.note.title,
      category: this.note.category,
      type: this.note.type,
      previewText: this.note.previewText,
      tag: this.note.tag,
      tagColor: this.note.tagColor,
      updateTime: this.note.updateTime,
      contentDetail: this.note.contentDetail,
      pageInfo: this.note.pageInfo,
      extraInfo: this.note.extraInfo,
      coverUrl: this.note.coverUrl,
      strokes: this.note.strokes,
      scratchpadStrokes: this.note.scratchpadStrokes,
      pageAnnotations: serialized
    };
    this.onSaved(updatedNote, updatedNote.contentDetail);
    this.onSaveStateChange('原盘批注已保存');
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // ---- 底层：多页 A4 视口 (可缩放、连续滚屏) ----
      Scroll(this.scroller) {
        Column({ space: 24 }) {
          ForEach(this.pages, (pm: PdfPageModel) => {
            PdfPageCanvas({
              pageModel: pm,
              strokes: this.pageStrokes[pm.pageIndex] || [],
              isAnnotateMode: this.isAnnotateMode,
              tool: this.currentTool,
              selectedColor: this.selectedColor,
              selectedWidth: this.selectedWidth,
              isDarkMode: this.isDarkMode,
              onStrokeAdded: (stroke: PageAnnotationStroke) => this.handleStrokeAdded(stroke),
              onEraseAtPoint: (u: number, v: number) => this.handleEraseAtPoint(pm.pageIndex, u, v)
            })
          }, (pm: PdfPageModel) => `page_${pm.pageIndex}`)
        }
        .width(`${100 * this.zoomScale}%`)
        .padding({ left: 32, right: 32, top: 24, bottom: 96 })
        .animation({ curve: curves.springMotion(0.28, 0.76) })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .backgroundColor(this.palette().canvas)
    }
    .width('100%')
    .height('100%')
  }
}
