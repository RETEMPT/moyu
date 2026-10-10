import { CanvasPoint, CanvasStroke } from '../../common/types/CanvasStroke';
import { CanvasViewport } from './CanvasViewport';

/** Hit the swept eraser path, including fast movement across sparsely sampled strokes. */
export class CanvasStrokeEraser {
  private static distance(x: number, y: number, a: CanvasPoint, b: CanvasPoint): number {
    const dx = b.x - a.x; const dy = b.y - a.y;
    const t = dx * dx + dy * dy ? Math.max(0, Math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / (dx * dx + dy * dy))) : 0;
    return Math.pow(x - a.x - t * dx, 2) + Math.pow(y - a.y - t * dy, 2);
  }

  static hit(stroke: CanvasStroke, from: CanvasPoint, to: CanvasPoint, radius: number): boolean {
    if (stroke.isEraser || !stroke.points.length) { return false; }
    const scale = CanvasViewport.scale(stroke);
    const padding = radius + stroke.width * scale;
    const bounds = CanvasViewport.bounds(stroke);
    if (Math.max(from.x, to.x) + radius < bounds.left || Math.min(from.x, to.x) - radius > bounds.right ||
      Math.max(from.y, to.y) + radius < bounds.top || Math.min(from.y, to.y) - radius > bounds.bottom) { return false; }
    for (let i = 0; i < stroke.points.length; i++) {
      const p = stroke.points[i]; const q = stroke.points[Math.max(0, i - 1)];
      const a: CanvasPoint = { x: p.x * scale, y: p.y * scale };
      const b: CanvasPoint = { x: q.x * scale, y: q.y * scale };
      const dx = to.x - from.x; const dy = to.y - from.y;
      const ex = b.x - a.x; const ey = b.y - a.y;
      const cross = dx * ey - dy * ex;
      if (Math.abs(cross) > 0.000001) {
        const t = ((a.x - from.x) * ey - (a.y - from.y) * ex) / cross;
        const u = ((a.x - from.x) * dy - (a.y - from.y) * dx) / cross;
        if (t >= 0 && t <= 1 && u >= 0 && u <= 1) { return true; }
      }
      if (Math.min(CanvasStrokeEraser.distance(from.x, from.y, a, b), CanvasStrokeEraser.distance(to.x, to.y, a, b),
        CanvasStrokeEraser.distance(a.x, a.y, from, to), CanvasStrokeEraser.distance(b.x, b.y, from, to)) <= padding * padding) { return true; }
    }
    return false;
  }
}
