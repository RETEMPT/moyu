import BuildProfile from 'BuildProfile';
import { Context } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

export interface DebugPdfPage {
  pixelMap: image.PixelMap;
  aspectRatio: number;
}

/** Exact renders of our own bundled PDFs; never substitutes pages for another document. */
export class DebugPdfPreviewService {
  private context: Context | null = null;

  bindContext(context: Context): void { this.context = context; }

  private kindOf(filePath: string): string {
    if (!BuildProfile.DEBUG || this.context === null ||
      !filePath.startsWith(`${this.context.filesDir}/documents/`)) { return ''; }
    const name = filePath.substring(`${this.context.filesDir}/documents/`.length);
    if (!name || name.includes('/') || name.includes('\\')) { return ''; }
    for (const kind of ['course', 'snapshot']) {
      const expected = this.context.resourceManager.getRawFileContentSync(`example-${kind}.pdf`);
      if (fs.statSync(filePath).size !== expected.byteLength) { continue; }
      const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      try {
        const buffer = new ArrayBuffer(expected.byteLength);
        if (fs.readSync(file.fd, buffer) !== expected.byteLength) { continue; }
        const actual = new Uint8Array(buffer);
        let same: boolean = true;
        for (let i = 0; i < expected.byteLength; i++) {
          if (actual[i] !== expected[i]) { same = false; break; }
        }
        if (same) { return kind; }
      } finally { fs.closeSync(file); }
    }
    return '';
  }

  pageCount(filePath: string): number { return this.kindOf(filePath) ? 2 : 0; }

  renderPage(filePath: string, pageIndex: number): DebugPdfPage | null {
    const kind = this.kindOf(filePath);
    if (!kind || this.context === null) { return null; }
    if (!Number.isInteger(pageIndex) || pageIndex < 0 || pageIndex >= 2) { throw new Error('PDF 页码超出范围'); }
    const bytes = this.context.resourceManager.getRawFileContentSync(`debug-pdf-preview/${kind}-${pageIndex + 1}.png`);
    const source = image.createImageSource(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength));
    try {
      const info = source.getImageInfoSync();
      const pixelMap = source.createPixelMapSync({ editable: false, desiredPixelFormat: image.PixelMapFormat.RGBA_8888 });
      return { pixelMap: pixelMap, aspectRatio: info.size.width / info.size.height };
    } finally { source.release().catch(() => {}); }
  }
}
