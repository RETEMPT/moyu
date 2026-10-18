import { CanvasPoint } from '../../common/types/CanvasStroke';

/** Shapes use ordinary ink paths, keeping history, erasing and existing backups compatible. */
export class InkShapePolicy {
  static isShape(tool: string): boolean { return ['line', 'rectangle', 'ellipse', 'arrow'].includes(tool); }

  static points(tool: string, start: CanvasPoint, end: CanvasPoint): CanvasPoint[] {
    if (!InkShapePolicy.isShape(tool) || ![start.x, start.y, end.x, end.y].every((v: number) => Number.isFinite(v))) { return []; }
    const dx = end.x - start.x; const dy = end.y - start.y;
    const length = Math.hypot(dx, dy);
    if (length < 0.5) { return []; }
    const a: CanvasPoint = { x: start.x, y: start.y, pressure: 0.5 };
    const b: CanvasPoint = { x: end.x, y: end.y, pressure: 0.5 };
    if (tool === 'line') { return [a, b]; }
    if (tool === 'rectangle') {
      const c: CanvasPoint = { x: end.x, y: start.y, pressure: 0.5 };
      const d: CanvasPoint = { x: start.x, y: end.y, pressure: 0.5 };
      // Duplicated corners retain sharp turns with the shared midpoint smoothing renderer.
      return [a, a, c, c, b, b, d, d, a, a];
    }
    if (tool === 'ellipse') {
      const points: CanvasPoint[] = [];
      for (let i = 0; i <= 64; i++) {
        const angle = i * Math.PI * 2 / 64;
        points.push({ x: (start.x + end.x) / 2 + Math.abs(dx) / 2 * Math.cos(angle),
          y: (start.y + end.y) / 2 + Math.abs(dy) / 2 * Math.sin(angle), pressure: 0.5 });
      }
      return points;
    }
    const head = Math.min(length * 0.25, 32);
    const ux = dx / length; const uy = dy / length;
    const left: CanvasPoint = { x: end.x - head * ux - head * 0.55 * uy, y: end.y - head * uy + head * 0.55 * ux, pressure: 0.5 };
    const right: CanvasPoint = { x: end.x - head * ux + head * 0.55 * uy, y: end.y - head * uy - head * 0.55 * ux, pressure: 0.5 };
    return [a, a, b, b, left, left, b, b, right, right];
  }
}
