import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';

/** 使用端侧 OCR；无文字或设备不支持时返回明确错误。 */
export class OcrService {
  private static instance: OcrService | null = null;

  static getInstance(): OcrService {
    if (OcrService.instance === null) {
      OcrService.instance = new OcrService();
    }
    return OcrService.instance;
  }

  async recognizeTextFromUri(imageUri: string): Promise<string> {
    if (imageUri.trim().length === 0) {
      throw new Error('无效的图片路径');
    }
    if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) {
      throw new Error('此设备未提供系统文字识别，可粘贴文字完成本地排版');
    }
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    try {
      file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      // 控制手机解码内存，保持比例与文字细节。
      const ratio = Math.min(1, 3200 / Math.max(info.size.width, info.size.height));
      pixelMap = await source.createPixelMap({ editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: { width: Math.max(1, Math.round(info.size.width * ratio)),
          height: Math.max(1, Math.round(info.size.height * ratio)) } });
      const result = await textRecognition.recognizeText({ pixelMap: pixelMap });
      const text = OcrService.resultText(result);
      if (text.length === 0) {
        throw new Error('未识别到文字，请选择清晰图片或手动粘贴文字');
      }
      return text;
    } finally {
      if (pixelMap !== null) {
        try { await pixelMap.release(); } catch { /* 已释放 */ }
      }
      if (source !== null) {
        try { await source.release(); } catch { /* 已释放 */ }
      }
      if (file !== null) {
        try { fs.closeSync(file); } catch { /* 已关闭 */ }
      }
    }
  }

  /** Caller retains ownership of a rendered PDF page and must release it. */
  async recognizePixelMap(pixelMap: image.PixelMap): Promise<string> {
    if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) { throw new Error('此设备未提供系统文字识别'); }
    const result = await textRecognition.recognizeText({ pixelMap: pixelMap });
    return OcrService.resultText(result);
  }

  private static resultText(result: textRecognition.TextRecognitionResult): string {
    const text = result && typeof result.value === 'string' ? result.value.trim() : '';
    if (text.length === 0 || !Array.isArray(result.blocks)) { return text; }
    const blocks = result.blocks.map((block: textRecognition.TextBlock) => block.value.trim())
      .filter((value: string) => value.length > 0).join('\n\n');
    // Keep the SDK's order. Use paragraph boundaries only if all recognized characters match.
    return blocks.replace(/\s/g, '') === text.replace(/\s/g, '') ? blocks : text;
  }
}
