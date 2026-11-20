import { CanvasPoint } from '../../common/types/CanvasStroke';

/** Shapes use ordinary ink paths, keeping history, erasing and existing backups compatible. */
export class InkShapePolicy {
  static isShape(tool: string): boolean {
    return [
      'line', 'rectangle', 'ellipse', 'arrow',
      'double_arrow', 'triangle', 'right_triangle',
      'parallelogram', 'pentagon', 'star'
    ].includes(tool);
  }

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
    if (tool === 'arrow') {
      const left: CanvasPoint = { x: end.x - head * ux - head * 0.55 * uy, y: end.y - head * uy + head * 0.55 * ux, pressure: 0.5 };
      const right: CanvasPoint = { x: end.x - head * ux + head * 0.55 * uy, y: end.y - head * uy - head * 0.55 * ux, pressure: 0.5 };
      return [a, a, b, b, left, left, b, b, right, right];
    }
    if (tool === 'double_arrow') {
      const leftEnd: CanvasPoint = { x: end.x - head * ux - head * 0.55 * uy, y: end.y - head * uy + head * 0.55 * ux, pressure: 0.5 };
      const rightEnd: CanvasPoint = { x: end.x - head * ux + head * 0.55 * uy, y: end.y - head * uy - head * 0.55 * ux, pressure: 0.5 };
      const leftStart: CanvasPoint = { x: start.x + head * ux - head * 0.55 * uy, y: start.y + head * uy + head * 0.55 * ux, pressure: 0.5 };
      const rightStart: CanvasPoint = { x: start.x + head * ux + head * 0.55 * uy, y: start.y + head * uy - head * 0.55 * ux, pressure: 0.5 };
      return [leftStart, leftStart, a, a, rightStart, rightStart, a, a, b, b, leftEnd, leftEnd, b, b, rightEnd, rightEnd];
    }
    if (tool === 'triangle') {
      const top: CanvasPoint = { x: (start.x + end.x) / 2, y: start.y, pressure: 0.5 };
      const br: CanvasPoint = { x: end.x, y: end.y, pressure: 0.5 };
      const bl: CanvasPoint = { x: start.x, y: end.y, pressure: 0.5 };
      return [top, top, br, br, bl, bl, top, top];
    }
    if (tool === 'right_triangle') {
      const p1: CanvasPoint = { x: start.x, y: start.y, pressure: 0.5 };
      const p2: CanvasPoint = { x: end.x, y: end.y, pressure: 0.5 };
      const p3: CanvasPoint = { x: start.x, y: end.y, pressure: 0.5 };
      return [p1, p1, p2, p2, p3, p3, p1, p1];
    }
    if (tool === 'parallelogram') {
      const skew = dx * 0.25;
      const p1: CanvasPoint = { x: start.x + skew, y: start.y, pressure: 0.5 };
      const p2: CanvasPoint = { x: end.x, y: start.y, pressure: 0.5 };
      const p3: CanvasPoint = { x: end.x - skew, y: end.y, pressure: 0.5 };
      const p4: CanvasPoint = { x: start.x, y: end.y, pressure: 0.5 };
      return [p1, p1, p2, p2, p3, p3, p4, p4, p1, p1];
    }
    if (tool === 'pentagon') {
      const cx = (start.x + end.x) / 2;
      const cy = (start.y + end.y) / 2;
      const rx = Math.abs(dx) / 2;
      const ry = Math.abs(dy) / 2;
      const pts: CanvasPoint[] = [];
      for (let i = 0; i < 5; i++) {
        const angle = -Math.PI / 2 + i * 2 * Math.PI / 5;
        const pt: CanvasPoint = { x: cx + rx * Math.cos(angle), y: cy + ry * Math.sin(angle), pressure: 0.5 };
        pts.push(pt, pt);
      }
      pts.push(pts[0], pts[0]);
      return pts;
    }
    if (tool === 'star') {
      const cx = (start.x + end.x) / 2;
      const cy = (start.y + end.y) / 2;
      const rx = Math.abs(dx) / 2;
      const ry = Math.abs(dy) / 2;
      const pts: CanvasPoint[] = [];
      for (let i = 0; i < 10; i++) {
        const r = (i % 2 === 0) ? 1.0 : 0.42;
        const angle = -Math.PI / 2 + i * Math.PI / 5;
        const pt: CanvasPoint = { x: cx + rx * r * Math.cos(angle), y: cy + ry * r * Math.sin(angle), pressure: 0.5 };
        pts.push(pt, pt);
      }
      pts.push(pts[0], pts[0]);
      return pts;
    }
    return [];
  }
}
