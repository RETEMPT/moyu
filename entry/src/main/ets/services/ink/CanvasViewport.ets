import { CanvasPoint, CanvasStroke } from '../../common/types/CanvasStroke';
export interface InkBounds { left: number; top: number; right: number; bottom: number; }
export class CanvasViewport {
  static readonly REFERENCE_WIDTH: number = 1200;
  static scale(stroke: CanvasStroke): number { return CanvasViewport.REFERENCE_WIDTH / (stroke.referenceWidth || CanvasViewport.REFERENCE_WIDTH); }
  static world(x: number, y: number, zoom: number, panX: number, panY: number): CanvasPoint {
    return { x: (x - panX) / zoom, y: (y - panY) / zoom };
  }
  static bounds(stroke: CanvasStroke): InkBounds {
    const scale = CanvasViewport.scale(stroke); const padding = stroke.width * scale;
    let left = Infinity; let top = Infinity; let right = -Infinity; let bottom = -Infinity;
    for (const p of stroke.points) { left = Math.min(left, p.x * scale); top = Math.min(top, p.y * scale); right = Math.max(right, p.x * scale); bottom = Math.max(bottom, p.y * scale); }
    return { left: left - padding, top: top - padding, right: right + padding, bottom: bottom + padding };
  }
  static visible(bounds: InkBounds, width: number, height: number, zoom: number, panX: number, panY: number): boolean {
    const start = CanvasViewport.world(0, 0, zoom, panX, panY); const end = CanvasViewport.world(width, height, zoom, panX, panY);
    return bounds.right >= start.x && bounds.left <= end.x && bounds.bottom >= start.y && bounds.top <= end.y;
  }
}
