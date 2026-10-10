import { CanvasPoint } from '../../common/types/CanvasStroke';

export interface InkStyle { color: string; width: number; highlighter: boolean; eraser: boolean; }
export type InkContext = CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;

/** Identical midpoint curves for live ink and persisted replay; live draws only the newest segment. */
export class InkRenderer {
  static segment(ctx: InkContext, points: CanvasPoint[], index: number, style: InkStyle): void {
    if (index < 0 || index >= points.length) { return; }
    const point = points[index];
    ctx.save();
    ctx.globalCompositeOperation = style.eraser ? 'destination-out' : 'source-over';
    ctx.globalAlpha = 1;
    ctx.strokeStyle = style.color; ctx.fillStyle = style.color; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    const pressure = point.pressure === undefined ? 0.5 : point.pressure;
    ctx.lineWidth = style.highlighter || style.eraser ? style.width : style.width * (0.4 + pressure * 1.2);
    ctx.beginPath();
    if (index === 0) {
      ctx.arc(point.x, point.y, ctx.lineWidth / 2, 0, Math.PI * 2); ctx.fill();
    } else {
      const previous = points[index - 1];
      const before = index > 1 ? points[index - 2] : previous;
      ctx.moveTo((before.x + previous.x) / 2, (before.y + previous.y) / 2);
      ctx.quadraticCurveTo(previous.x, previous.y, (previous.x + point.x) / 2, (previous.y + point.y) / 2);
      ctx.stroke();
    }
    ctx.restore();
  }

  static tail(ctx: InkContext, points: CanvasPoint[], style: InkStyle): void {
    if (points.length < 2) { return; }
    const point = points[points.length - 1]; const previous = points[points.length - 2];
    ctx.save(); ctx.globalCompositeOperation = style.eraser ? 'destination-out' : 'source-over';
    ctx.globalAlpha = 1; ctx.strokeStyle = style.color; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.lineWidth = style.highlighter || style.eraser ? style.width : style.width * (0.4 + (point.pressure ?? 0.5) * 1.2);
    ctx.beginPath(); ctx.moveTo((point.x + previous.x) / 2, (point.y + previous.y) / 2);
    ctx.lineTo(point.x, point.y); ctx.stroke(); ctx.restore();
  }

  static stroke(ctx: InkContext, points: CanvasPoint[], style: InkStyle): void {
    if (!points.length) { return; }
    if (style.highlighter && !style.eraser) {
      ctx.save(); ctx.globalAlpha = 0.35; ctx.strokeStyle = style.color; ctx.fillStyle = style.color;
      ctx.lineWidth = style.width; ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.beginPath();
      if (points.length === 1) { ctx.arc(points[0].x, points[0].y, style.width / 2, 0, Math.PI * 2); ctx.fill(); }
      else {
        ctx.moveTo(points[0].x, points[0].y);
        for (let i = 1; i < points.length; i++) {
          const p = points[i - 1]; const n = points[i];
          ctx.quadraticCurveTo(p.x, p.y, (p.x + n.x) / 2, (p.y + n.y) / 2);
        }
        const last = points[points.length - 1]; ctx.lineTo(last.x, last.y); ctx.stroke();
      }
      ctx.restore(); return;
    }
    for (let i = 0; i < points.length; i++) { InkRenderer.segment(ctx, points, i, style); }
    InkRenderer.tail(ctx, points, style);
  }

  static nearSegment(x: number, y: number, ax: number, ay: number, bx: number, by: number, radius: number): boolean {
    const dx = bx - ax; const dy = by - ay;
    const length = dx * dx + dy * dy;
    const t = length ? Math.max(0, Math.min(1, ((x - ax) * dx + (y - ay) * dy) / length)) : 0;
    const ex = x - ax - t * dx; const ey = y - ay - t * dy;
    return ex * ex + ey * ey <= radius * radius;
  }
}
