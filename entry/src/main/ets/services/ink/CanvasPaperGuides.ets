export interface PaperGuide { x1: number; y1: number; x2: number; y2: number; }

/** Visible paper guides follow world pan/zoom and never become persisted or erasable ink. */
export class CanvasPaperGuides {
  static lines(width: number, height: number, zoom: number, panX: number, panY: number, style: string): PaperGuide[] {
    if (style !== 'grid' && style !== 'ruled') { return []; }
    if (![width, height, zoom, panX, panY].every((value: number) => Number.isFinite(value)) ||
      width <= 0 || height <= 0 || zoom <= 0) { return []; }
    const rawSpacing = (style === 'ruled' ? 96 : 64) * zoom;
    const extent = style === 'grid' ? width + height : height;
    const multiplier = Math.max(1, Math.ceil((style === 'ruled' ? 24 : 16) / rawSpacing), Math.ceil(extent / rawSpacing / 160));
    const spacing = rawSpacing * multiplier;
    const guides: PaperGuide[] = [];
    if (style === 'grid') {
      const firstX = ((panX % spacing) + spacing) % spacing;
      for (let x = firstX; x < width && guides.length < 162; x += spacing) {
        guides.push({ x1: x, y1: 0, x2: x, y2: height });
      }
    }
    const firstY = ((panY % spacing) + spacing) % spacing;
    for (let y = firstY; y < height && guides.length < 162; y += spacing) {
      guides.push({ x1: 0, y1: y, x2: width, y2: y });
    }
    return guides;
  }
}
