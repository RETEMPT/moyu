/**
 * 画布笔迹的数据模型。
 *
 * 单独成文件而不是留在 HandwritingCanvas.ets 里：示例数据模块（common/seed）
 * 也需要构造笔迹，若类型定义留在 views/ 下，common 就要反向依赖视图层。
 */
export interface CanvasPoint {
  x: number;
  y: number;
}

export interface CanvasStroke {
  points: CanvasPoint[];
  color: string;
  width: number;
  /** 荧光笔：以低透明度宽笔头绘制，用于圈画题干 */
  isHighlighter: boolean;
  isEraser: boolean;
}
