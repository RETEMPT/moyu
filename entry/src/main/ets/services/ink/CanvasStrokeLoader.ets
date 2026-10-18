import { taskpool } from '@kit.ArkTS';
import { CanvasStroke } from '../../common/types/CanvasStroke';
import { CanvasStrokePolicy } from './CanvasStrokePolicy';

@Concurrent
export function decodeCanvasStrokes(raw: string): CanvasStroke[] {
  return CanvasStrokePolicy.parse(raw);
}

/** Keep JSON decoding and point validation out of the UI thread when opening a canvas. */
export class CanvasStrokeLoader {
  static async load(raw: string | undefined): Promise<CanvasStroke[]> {
    if (raw === undefined || raw === '' || raw === '[]') { return []; }
    return await taskpool.execute(decodeCanvasStrokes, raw) as CanvasStroke[];
  }
}
