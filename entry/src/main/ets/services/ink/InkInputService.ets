export interface InkSample { x: number; y: number; pressure: number; }
export type InkPhase = 'ignore' | 'begin' | 'move' | 'end' | 'cancel';
export interface InkInputBatch { phase: InkPhase; samples: InkSample[]; pen: boolean; }

/** Track the initiating pointer. Palm events must never end or append to a pen stroke. */
export class InkInputService {
  private pointerId: number = -1;
  private pen: boolean = false;
  private palmUntil: number = 0;

  reset(): void { this.pointerId = -1; this.pen = false; }
  isActive(): boolean { return this.pointerId !== -1; }

  read(event: TouchEvent, fingerEnabled: boolean): InkInputBatch {
    const ignored: InkInputBatch = { phase: 'ignore', samples: [], pen: false };
    const pen = event.sourceTool === SourceTool.Pen;
    if (!pen && this.pen) { return ignored; }
    if (!pen && (!fingerEnabled || event.sourceTool !== SourceTool.Finger || Date.now() < this.palmUntil)) { return ignored; }
    if (!pen && event.touches.length > 1) {
      const active = this.pointerId !== -1; this.reset();
      return { phase: active ? 'cancel' : 'ignore', samples: [], pen: false };
    }
    const changed = event.changedTouches.length ? event.changedTouches : event.touches;
    const touch = this.pointerId === -1 || event.type === TouchType.Down ? changed[0] :
      changed.find((point: TouchObject) => point.id === this.pointerId);
    if (event.type === TouchType.Cancel) {
      if (this.pointerId === -1 || (touch && touch.id !== this.pointerId)) { return ignored; }
      this.reset(); return { phase: 'cancel', samples: [], pen };
    }
    if (!touch || !Number.isFinite(touch.x) || !Number.isFinite(touch.y)) { return ignored; }
    if (event.type === TouchType.Down) { this.pointerId = touch.id; this.pen = pen; }
    else if (this.pointerId !== touch.id) { return ignored; }
    if (pen) { this.palmUntil = Date.now() + 700; }
    const samples: InkSample[] = [];
    if (event.type === TouchType.Move) {
      try {
        for (const point of event.getHistoricalPoints()) {
          if (point.touchObject.id === this.pointerId && Number.isFinite(point.touchObject.x) && Number.isFinite(point.touchObject.y)) {
            samples.push({ x: point.touchObject.x, y: point.touchObject.y, pressure: InkInputService.pressure(point.force, true) });
          }
        }
      } catch { /* The current point still works on devices without historical reporting. */ }
    }
    const pressure = touch.pressure !== undefined && touch.pressure > 0 ?
      InkInputService.pressure(touch.pressure, true) : InkInputService.pressure(event.pressure);
    samples.push({ x: touch.x, y: touch.y, pressure });
    let phase: InkPhase = event.type === TouchType.Down ? 'begin' : event.type === TouchType.Up ? 'end' : 'move';
    if (phase === 'end') { this.reset(); }
    return { phase, samples, pen };
  }

  static pressure(value: number | undefined, raw: boolean = false): number {
    if (value === undefined || !Number.isFinite(value)) { return 0.5; }
    return Math.max(0, Math.min(1, raw ? value / 65535 : value));
  }
}
