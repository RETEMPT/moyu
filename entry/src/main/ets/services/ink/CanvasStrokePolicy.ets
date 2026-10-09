import { CanvasStroke } from '../../common/types/CanvasStroke';

/** Reject the entire snapshot on corruption; dropping individual strokes would make the next save destructive. */
export class CanvasStrokePolicy {
  static parse(raw: string | undefined): CanvasStroke[] {
    if (raw === undefined || raw === '') { return []; }
    if (typeof raw !== 'string' || raw.length > 32 * 1024 * 1024) { throw new Error('白板笔迹数据格式无效或过大'); }
    const strokes = JSON.parse(raw) as CanvasStroke[];
    if (!Array.isArray(strokes) || strokes.length > 50000) { throw new Error('白板笔迹不是有效的笔画列表'); }
    let count = 0;
    for (const stroke of strokes) {
      if (!stroke || typeof stroke !== 'object' || !Array.isArray(stroke.points) ||
        typeof stroke.color !== 'string' || !stroke.color.trim() || stroke.color.length > 128 ||
        !Number.isFinite(stroke.width) || stroke.width <= 0 || stroke.width > 4096 ||
        (stroke.referenceWidth !== undefined && (!Number.isFinite(stroke.referenceWidth) || stroke.referenceWidth <= 0 || stroke.referenceWidth > 65536)) ||
        (stroke.isHighlighter !== undefined && typeof stroke.isHighlighter !== 'boolean') ||
        (stroke.isEraser !== undefined && typeof stroke.isEraser !== 'boolean')) {
        throw new Error('白板笔画结构无效');
      }
      count += stroke.points.length;
      if (count > 1000000) { throw new Error('白板笔迹点数较大，暂时无法完整读取'); }
      for (const point of stroke.points) {
        if (!point || typeof point !== 'object' || !Number.isFinite(point.x) || !Number.isFinite(point.y) ||
          Math.abs(point.x) > 100000000 || Math.abs(point.y) > 100000000 ||
          (point.pressure !== undefined && (!Number.isFinite(point.pressure) || point.pressure < 0 || point.pressure > 1))) {
          throw new Error('白板笔迹坐标或压力无效');
        }
      }
      // Earlier versions did not persist pressure or tool flags; missing flags remain false in the renderer.
    }
    return strokes;
  }
}
