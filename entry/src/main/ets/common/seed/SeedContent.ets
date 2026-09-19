/**
 * 首次启动与「载入示例数据」共用的示例内容。
 *
 * 从 pages/Index.ets 抽出来单独成模块的原因：这批数据有 400 行，全是字面量，
 * 和顶层的状态与事件处理混在一个文件里会把真正的逻辑淹掉。示例内容本身
 * 不依赖任何组件状态，是纯数据，放在 common/ 下也不会引入循环依赖。
 *
 * 这里同时是进入「原盘批注」PDF 阅读器的兜底入口：老设备的笔记快照早于
 * 示例数据，load() 只在快照完全缺失时才灌种子，因此需要一个显式补入的路径
 * （见 Index.loadSeedData）。
 */
import { NoteItem } from '../types/NoteItem';
import { SpaceFolder } from '../types/SpaceFolder';
import { CanvasStroke } from '../types/CanvasStroke';
import { DocumentAnnotationData } from '../types/PdfAnnotationTypes';

/**
 * 示例手写笔迹。
 * 必须显式标注为 CanvasStroke[] —— ArkTS 不允许无类型对象字面量，
 * JSON.stringify([{...}]) 这种写法会直接编译不过（arkts-no-untyped-obj-literals）。
 */
const SEED_HANDWRITING_STROKES: CanvasStroke[] = [
  {
    points: [{ x: 80, y: 120 }, { x: 180, y: 120 }, { x: 280, y: 140 }, { x: 380, y: 120 }],
    color: '#1C1917',
    width: 4,
    isHighlighter: false,
    isEraser: false
  },
  {
    points: [{ x: 80, y: 160 }, { x: 140, y: 240 }, { x: 200, y: 160 }, { x: 260, y: 240 }],
    color: '#2563EB',
    width: 3,
    isHighlighter: false,
    isEraser: false
  },
  {
    points: [{ x: 70, y: 110 }, { x: 400, y: 110 }],
    color: '#EAB308',
    width: 14,
    isHighlighter: true,
    isEraser: false
  }
];

/** 示例草稿板笔迹，同上需显式类型 */
const SEED_SCRATCHPAD_STROKES: CanvasStroke[] = [
  {
    points: [{ x: 50, y: 80 }, { x: 220, y: 80 }, { x: 220, y: 150 }, { x: 50, y: 150 }, { x: 50, y: 80 }],
    color: '#2563EB',
    width: 3,
    isHighlighter: false,
    isEraser: false
  },
  {
    points: [{ x: 60, y: 110 }, { x: 200, y: 110 }],
    color: '#1C1917',
    width: 3,
    isHighlighter: false,
    isEraser: false
  },
  {
    points: [{ x: 230, y: 70 }, { x: 300, y: 140 }],
    color: '#DC2626',
    width: 4,
    isHighlighter: false,
    isEraser: false
  }
];

/** 原生 PDF / 试卷原盘归一化矢量批注（包含高亮、勾选批改与解题步骤） */
const SEED_EXAM_PAGE_ANNOTATIONS: DocumentAnnotationData = {
  version: 1,
  pageCount: 2,
  pages: {
    0: [
      {
        id: 'seed_hl_1',
        pageIndex: 0,
        color: '#FACC15',
        width: 14,
        isHighlighter: true,
        isEraser: false,
        points: [
          { u: 0.18, v: 0.19 },
          { u: 0.48, v: 0.19 }
        ]
      },
      {
        id: 'seed_check_1',
        pageIndex: 0,
        color: '#DC2626',
        width: 3.5,
        isHighlighter: false,
        isEraser: false,
        points: [
          { u: 0.08, v: 0.27 },
          { u: 0.11, v: 0.30 },
          { u: 0.16, v: 0.24 }
        ]
      },
      {
        id: 'seed_score_text',
        pageIndex: 0,
        color: '#DC2626',
        width: 2.5,
        isHighlighter: false,
        isEraser: false,
        points: [
          { u: 0.75, v: 0.21 },
          { u: 0.82, v: 0.21 },
          { u: 0.78, v: 0.18 },
          { u: 0.78, v: 0.24 }
        ]
      },
      {
        id: 'seed_calc_1',
        pageIndex: 0,
        color: '#2563EB',
        width: 2.5,
        isHighlighter: false,
        isEraser: false,
        points: [
          { u: 0.15, v: 0.44 },
          { u: 0.42, v: 0.44 },
          { u: 0.35, v: 0.48 },
          { u: 0.60, v: 0.48 }
        ]
      }
    ],
    1: [
      {
        id: 'seed_hl_2',
        pageIndex: 1,
        color: '#4ADE80',
        width: 14,
        isHighlighter: true,
        isEraser: false,
        points: [
          { u: 0.18, v: 0.20 },
          { u: 0.52, v: 0.20 }
        ]
      },
      {
        id: 'seed_calc_p2',
        pageIndex: 1,
        color: '#2563EB',
        width: 2.5,
        isHighlighter: false,
        isEraser: false,
        points: [
          { u: 0.15, v: 0.42 },
          { u: 0.45, v: 0.42 }
        ]
      }
    ]
  }
};

/**
 * 首次启动时的默认项目。
 * 用工厂函数而不是常量数组：项目对象在 renameProject 里会被就地改名，
 * 若共享同一批对象，恢复到默认值时拿到的会是上一次被改过的脏数据。
 */
export function defaultProjects(): SpaceFolder[] {
  return [
    { id: 'space-计算机基础', name: '计算机基础', count: 0, isOpen: true, children: [], color: '#4F46E5', icon: '💻', notes: [] },
    { id: 'space-数学基础', name: '数学基础', count: 0, isOpen: true, children: [], color: '#059669', icon: '📐', notes: [] }
  ];
}

/**
 * 首次启动的示例内容：展示双链、标签与大纲能力，可被用户直接删除。
 *
 * 每次调用都返回全新对象，调用方可以放心就地修改（Index 里会直接改 category）。
 */
export function seedNotes(): NoteItem[] {
  return [
    {
      id: 'note-seed-os',
      title: '操作系统 · 死锁与银行家算法',
      category: '计算机基础',
      type: 'Markdown',
      previewText: '死锁的四个必要条件，以及银行家算法如何做安全序列判定。',
      tag: '重点',
      tagColor: '',
      updateTime: '示例',
      contentDetail: '# 死锁与银行家算法\n\n' +
        '## 死锁的四个必要条件\n\n' +
        '- 互斥：资源同一时刻只能被一个进程占用\n' +
        '- 占有并等待：持有资源的同时申请新资源\n' +
        '- 不可剥夺：资源只能由持有者主动释放\n' +
        '- 循环等待：存在进程与资源的环形等待链\n\n' +
        '> 不安全状态不等于死锁，但死锁一定发生在不安全状态之后。\n\n' +
        '## 银行家算法\n\n' +
        '核心是每次分配前做一次安全性检查，若能找到安全序列才真正分配。\n\n' +
        '相关数学工具见 [[线性代数 · 特征值与特征向量]]。\n\n' +
        '#操作系统 #考研'
    },
    {
      id: 'note-seed-math',
      title: '线性代数 · 特征值与特征向量',
      category: '数学基础',
      type: 'Markdown',
      previewText: '特征值刻画线性变换在特定方向上的伸缩比例。',
      tag: '基础',
      tagColor: '',
      updateTime: '示例',
      contentDetail: '# 特征值与特征向量\n\n' +
        '## 定义\n\n' +
        '若存在非零向量 v 使得 Av = λv，则 λ 是矩阵 A 的特征值。\n\n' +
        '## 几何直觉\n\n' +
        '特征向量是变换后方向不变、只被拉伸或压缩的方向。\n\n' +
        '在概率模型的收敛性分析中会用到 [[概率论 · 贝叶斯定理]] 的思想。\n\n' +
        '```\n' +
        'det(A - λI) = 0\n' +
        '```\n\n' +
        '#数学 #线性代数'
    },
    {
      id: 'note-seed-prob',
      title: '概率论 · 贝叶斯定理',
      category: '数学基础',
      type: 'Markdown',
      previewText: '用先验与似然更新后验，是本地 AI 问答置信度估计的基础。',
      tag: '基础',
      tagColor: '',
      updateTime: '示例',
      contentDetail: '# 贝叶斯定理\n\n' +
        '## 公式\n\n' +
        'P(A|B) = P(B|A) · P(A) / P(B)\n\n' +
        '## 用途\n\n' +
        '- 垃圾邮件分类\n' +
        '- 端侧检索问答的置信度估计\n' +
        '- 与 [[操作系统 · 死锁与银行家算法]] 无关，但同属考研复习范围\n\n' +
        '#数学 #概率论'
    },
    {
      id: 'note-seed-pdf',
      title: '现代操作系统原理与虚拟化.pdf',
      category: '计算机基础',
      type: 'PDF',
      previewText: '深入理解进程调度、内存分页与硬件虚拟化技术架构。',
      tag: 'PDF文献',
      tagColor: '#E11D48',
      pageInfo: '348 页',
      updateTime: '昨天',
      contentDetail: '# 现代操作系统原理与虚拟化 (PDF)\n\n本书详细讨论了现代操作系统的四大支柱：虚拟化、并发、持久化与分布式系统。\n\n重点内容参考 [[操作系统 · 死锁与银行家算法]]。',
      pageAnnotations: JSON.stringify(SEED_EXAM_PAGE_ANNOTATIONS)
    },
    {
      id: 'note-seed-handwriting',
      title: '考研数学 · 极限思想思维手稿',
      category: '数学基础',
      type: '白纸笔记',
      previewText: '[白纸手写] 包含多颜色笔推演草图与几何示意',
      tag: '手写手稿',
      tagColor: '#D97706',
      updateTime: '今天',
      contentDetail: '# 考研数学 · 极限思想思维手稿\n\n[白纸手写笔记]\n',
      strokes: JSON.stringify(SEED_HANDWRITING_STROKES)
    },
    {
      id: 'note-seed-exam',
      title: '2026 计算机考研专业综合模拟试卷.docx',
      category: '计算机基础',
      type: 'Doc',
      previewText: '[真题试卷] 原生三层原盘批注 + 边读边写草稿，支持红笔勾选与高亮',
      tag: '试卷题目',
      tagColor: '#2563EB',
      updateTime: '刚刚',
      contentDetail: '# 2026 计算机考研专业综合模拟试卷\n\n' +
        '> 提示：点击顶栏「✎ 原盘批注」可直接在试卷上批改解题；点击「◫ 边读边写」可调出随堂草稿板。\n\n' +
        '## 一、选择题（每小题 2 分）\n\n' +
        '1. 在具有安全序列的系统中，下列关于死锁的说法正确的是（  ）\n' +
        '• A. 系统必定不会发生死锁\n' +
        '• B. 系统可能会发生死锁\n' +
        '• C. 此时所有进程均已释放资源\n' +
        '• D. 死锁的循环等待链已经形成\n\n' +
        '> 答案：A。解析详见 [[操作系统 · 死锁与银行家算法]]，安全序列意味着至少存在一种资源分配顺序使所有进程顺利执行完。\n\n' +
        '## 二、综合应用大题（15 分）\n\n' +
        '某系统有 A、B、C 三类资源，当前分配状态如下：\n' +
        '- 进程 P1 申请资源 [1, 0, 2]\n' +
        '- 试用银行家算法分析系统当前是否安全，并给出一种安全序列。\n\n' +
        '--- \n' +
        '相关考点：[[操作系统 · 死锁与银行家算法]]、[[线性代数 · 特征值与特征向量]]\n\n' +
        '#考研真题 #试卷演练',
      scratchpadStrokes: JSON.stringify(SEED_SCRATCHPAD_STROKES),
      pageAnnotations: JSON.stringify(SEED_EXAM_PAGE_ANNOTATIONS)
    }
  ];
}
