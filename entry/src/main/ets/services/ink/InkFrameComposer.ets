/** Replay chronological ink and erase masks offscreen, then publish one completed image. */
export class InkFrameComposer {
  private canvas: OffscreenCanvas | null = null;
  private width: number = 0;
  private height: number = 0;

  render(target: CanvasRenderingContext2D, width: number, height: number,
    paint: (context: OffscreenCanvasRenderingContext2D) => void): void {
    const w = Math.ceil(width); const h = Math.ceil(height);
    if (!Number.isFinite(w) || !Number.isFinite(h) || w <= 0 || h <= 0) { return; }
    if (!this.canvas || this.width !== w || this.height !== h) {
      this.release(); this.canvas = new OffscreenCanvas(w, h); this.width = w; this.height = h;
    }
    const context = this.canvas.getContext('2d', new RenderingContextSettings(true));
    context.clearRect(0, 0, w, h);
    paint(context);
    const frame = this.canvas.transferToImageBitmap();
    try { target.transferFromImageBitmap(frame); }
    finally { frame.close(); }
  }

  release(): void {
    if (this.canvas) { this.canvas.width = 0; this.canvas.height = 0; }
    this.canvas = null; this.width = 0; this.height = 0;
  }
}
