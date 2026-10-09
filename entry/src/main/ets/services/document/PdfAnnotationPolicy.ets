import { DocumentAnnotationData, NormalizedPoint, PageAnnotationStroke } from '../../common/types/PdfAnnotationTypes';

/** Invalid saved ink is retained intact for recovery. Never silently filter it and write the remainder back. */
export class PdfAnnotationPolicy {
  static read(raw: string | undefined, pageCount: number): DocumentAnnotationData {
    if (raw === undefined || raw === '') { return { version: 1, pageCount: pageCount, pages: {} }; }
    try {
      if (typeof raw !== 'string' || raw.length >= 8000000) { throw new Error('size'); }
      const data = JSON.parse(raw) as DocumentAnnotationData;
      if (!data || data.version !== 1 || !Number.isInteger(data.pageCount) || data.pageCount < 1 ||
        data.pageCount > 10000 || !data.pages || typeof data.pages !== 'object' ||
        Array.isArray(data.pages)) { throw new Error('pages'); }
      let totalStrokes = 0; let totalPoints = 0;
      for (const key of Object.keys(data.pages)) {
        const index = Number(key);
        if (!/^(0|[1-9]\d*)$/.test(key) || !Number.isInteger(index)) { throw new Error('page'); }
        const strokes = data.pages[index];
        if (!Array.isArray(strokes)) { throw new Error('strokes'); }
        // Older single-page notes initialized both pages 0 and 1, leaving an empty page 1 record.
        if (index >= pageCount && strokes.length > 0) { throw new Error('page'); }
        totalStrokes += strokes.length;
        if (totalStrokes > 100000) { throw new Error('stroke count'); }
        for (const stroke of strokes) {
          PdfAnnotationPolicy.requireStroke(stroke, index);
          totalPoints += stroke.points.length;
          if (totalPoints > 500000) { throw new Error('point count'); }
        }
      }
      return data;
    } catch { throw new Error('批注数据无法读取，原记录已保留。可继续阅读原 PDF，请从有效备份恢复批注。'); }
  }

  private static requireStroke(stroke: PageAnnotationStroke, pageIndex: number): void {
    if (!stroke || typeof stroke.id !== 'string' || !stroke.id || stroke.id.length > 200 ||
      stroke.pageIndex !== pageIndex || typeof stroke.color !== 'string' || !stroke.color || stroke.color.length > 64 ||
      !Number.isFinite(stroke.width) || stroke.width <= 0 || stroke.width > 4096 ||
      (stroke.isHighlighter !== undefined && typeof stroke.isHighlighter !== 'boolean') ||
      (stroke.isEraser !== undefined && typeof stroke.isEraser !== 'boolean') || !Array.isArray(stroke.points)) {
      throw new Error('stroke');
    }
    for (const point of stroke.points) { PdfAnnotationPolicy.requirePoint(point); }
  }

  private static requirePoint(point: NormalizedPoint): void {
    if (!point || !Number.isFinite(point.u) || !Number.isFinite(point.v) || point.u < 0 || point.u > 1 ||
      point.v < 0 || point.v > 1 || (point.pressure !== undefined &&
        (!Number.isFinite(point.pressure) || point.pressure < 0 || point.pressure > 1))) { throw new Error('point'); }
  }
}
