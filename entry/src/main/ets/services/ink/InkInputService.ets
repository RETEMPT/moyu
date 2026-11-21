export interface InkSample { x: number; y: number; pressure: number; }
export type InkPhase = 'ignore' | 'begin' | 'move' | 'end' | 'cancel';
export interface InkInputBatch { phase: InkPhase; samples: InkSample[]; pen: boolean; }

/** Track the initiating pointer. Palm events must never end or append to a pen stroke. */
export class InkInputService {
  private pointerId: number = -1;
  private pen: boolean = false;
  private palmUntil: number = 0;
  private lastTime: number = 0;

  reset(): void { this.pointerId = -1; this.pen = false; this.lastTime = 0; }
  isActive(): boolean { return this.pointerId !== -1; }
  isPenActive(): boolean { return this.pointerId !== -1 && this.pen; }

  read(event: TouchEvent, fingerEnabled: boolean): InkInputBatch {
    const ignored: InkInputBatch = { phase: 'ignore', samples: [], pen: false };
    const pen = event.sourceTool === SourceTool.Pen;
    if (!pen && this.pen) { return ignored; }
    const pointer = event.sourceTool === SourceTool.Finger || event.sourceTool === SourceTool.MOUSE || event.sourceTool === SourceTool.TOUCHPAD;
    if (!pen && (!fingerEnabled || !pointer || Date.now() < this.palmUntil)) { return ignored; }
    if (!pen && event.touches.length > 1) {
      const active = this.pointerId !== -1; this.reset();
      return { phase: active ? 'cancel' : 'ignore', samples: [], pen: false };
    }
    const changed = event.changedTouches.length ? event.changedTouches : event.touches;
    const touch = this.pointerId === -1 || event.type === TouchType.Down ? changed[0] :
      changed.find((point: TouchObject) => point.id === this.pointerId);
    if (event.type === TouchType.Cancel) {
      if (this.pointerId === -1 || (changed.length > 0 && !touch)) { return ignored; }
      this.reset(); return { phase: 'cancel', samples: [], pen };
    }
    if (event.type === TouchType.Up) {
      const owned = this.pointerId !== -1 && (event.changedTouches.some((point: TouchObject) => point.id === this.pointerId) ||
        (event.changedTouches.length === 0 && event.touches.length === 0));
      if (!owned) { return ignored; }
      if (pen) { this.palmUntil = Date.now() + 700; }
      this.reset();
      // A release packet can carry a fallback coordinate. Commit the last actual ink sample.
      return { phase: 'end', samples: [], pen };
    }
    if (!touch || !Number.isFinite(touch.x) || !Number.isFinite(touch.y)) { return ignored; }
    // Repeated Down packets and unrelated pen contacts must not restart a live stroke.
    // A real pen may take over a finger contact (palm rejection), but keeps its own ID thereafter.
    if (event.type === TouchType.Down && this.pointerId !== -1 && (!pen || this.pen)) { return ignored; }
    if (event.type === TouchType.Down) { this.pointerId = touch.id; this.pen = pen; this.lastTime = 0; }
    else if (this.pointerId !== touch.id) { return ignored; }
    if (pen) { this.palmUntil = Date.now() + 700; }
    const samples: InkSample[] = [];
    if (event.type === TouchType.Move && event.timestamp > 0 && event.timestamp <= this.lastTime) { return ignored; }
    if (event.type === TouchType.Move) {
      try {
        for (const point of event.getHistoricalPoints()) {
          if (point.touchObject.id === this.pointerId && Number.isFinite(point.touchObject.x) && Number.isFinite(point.touchObject.y) &&
            (!point.timestamp || (point.timestamp > this.lastTime && (!event.timestamp || point.timestamp < event.timestamp)))) {
            samples.push({ x: point.touchObject.x, y: point.touchObject.y,
              pressure: pen ? InkInputService.pressure(point.force, true) : 0.5 });
            if (point.timestamp > 0) { this.lastTime = point.timestamp; }
          }
        }
      } catch { /* The current point still works on devices without historical reporting. */ }
    }
    const pressure = !pen ? 0.5 : touch.pressure !== undefined && touch.pressure > 0 ?
      InkInputService.pressure(touch.pressure, true) : InkInputService.pressure(event.pressure);
    samples.push({ x: touch.x, y: touch.y, pressure });
    if (event.timestamp > 0) { this.lastTime = event.timestamp; }
    return { phase: event.type === TouchType.Down ? 'begin' : 'move', samples, pen };
  }

  static pressure(value: number | undefined, raw: boolean = false): number {
    if (value === undefined || !Number.isFinite(value)) { return 0.5; }
    return Math.max(0, Math.min(1, raw ? value / 65535 : value));
  }
}
