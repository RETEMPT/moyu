import { image } from '@kit.ImageKit';

export interface NativePdfResult {
  pageCount: number;
  fileSize: number;
  pixelMap?: image.PixelMap;
  aspectRatio?: number;
  text?: string;
  texts?: string[];
  unavailable?: boolean;
}

/** Load the optional native Kit inside TaskPool, after capability detection. */
@Concurrent
export async function readNativePdf(filePath: string, action: string, pageIndex: number,
  endPage: number = -1): Promise<NativePdfResult> {
  const backend = await import('./PdfKitDocument').catch(() => null);
  if (backend === null) { return { pageCount: 0, fileSize: 0, unavailable: true }; }
  return backend.readPdfKitDocument(filePath, action, pageIndex, endPage);
}
