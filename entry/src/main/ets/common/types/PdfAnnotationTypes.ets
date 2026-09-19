/**
 * 原生 PDF / 试卷原盘批注系统核心类型定义
 *
 * 核心设计：
 *   1. 归一化点位坐标 (u, v) ∈ [0, 1]：相对于当前页面物理宽高的百分比坐标，
 *      无论页面如何缩放 (0.6x ~ 3.0x)、平移或切换窗口大小，笔迹永远精准咬合在底稿文字上，彻底消除漂移。
 *   2. 分页矢量笔迹结构：按页存储笔画集合，支持轻量级 JSON 序列化与极速增量绘制。
 */

/** 归一化笔迹采样点 */
export interface NormalizedPoint {
  /** X 轴归一化坐标 (0.0 ~ 1.0) */
  u: number;
  /** Y 轴归一化坐标 (0.0 ~ 1.0) */
  v: number;
  /** 压感参数 (可选，0.0 ~ 1.0) */
  pressure?: number;
}

/** 页面矢量墨水笔画 */
export interface PageAnnotationStroke {
  /** 笔画唯一标识 */
  id: string;
  /** 所属页码索引 (0-indexed) */
  pageIndex: number;
  /** 墨水颜色 (十六进制，如 #DC2626) */
  color: string;
  /** 基准线宽 (归一化像素或点数) */
  width: number;
  /** 是否为半透明荧光高亮笔 */
  isHighlighter: boolean;
  /** 是否为橡皮擦笔迹 */
  isEraser: boolean;
  /** 归一化采样点轨迹集合 */
  points: NormalizedPoint[];
}

/** 单页试卷/文档排版段落数据 */
export interface PdfPageSection {
  type: 'header' | 'question' | 'math' | 'blank' | 'footer';
  title?: string;
  text: string;
  score?: string;
  tag?: string;
}

/** 单页排版模型 */
export interface PdfPageModel {
  pageIndex: number;
  pageNumberText: string;
  sections: PdfPageSection[];
}

/** 文档整套批注数据集 */
export interface DocumentAnnotationData {
  version: number;
  pageCount: number;
  pages: Record<number, PageAnnotationStroke[]>;
}

/** 批注工具栏工具模式 */
export type AnnotationTool = 'pen' | 'highlighter' | 'eraser' | 'pan';
