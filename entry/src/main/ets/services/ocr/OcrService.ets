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

  /** 查询底层硬件是否具备鸿蒙原生端侧 NPU 文字识别能力。 */
  static isHardwareSupported(): boolean {
    return canIUse('SystemCapability.AI.OCR.TextRecognition');
  }

  async recognizeTextFromUri(imageUri: string): Promise<string> {
    if (imageUri.trim().length === 0) {
      throw new Error('无效的图片路径');
    }
    if (!canIUse('SystemCapability.AI.OCR.TextRecognition')) {
      throw new Error('此设备不支持系统图片文字识别，可选择含文字层的 PDF 或文字文档');
    }
    let file: fs.File | null = null;
    let source: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    try {
      file = fs.openSync(imageUri, fs.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      // 控制手机解码内存，保持比例与文字细节。
      const longest = Math.max(info.size.width, info.size.height);
      const pixelLimit = Math.sqrt(6000000 / (info.size.width * info.size.height));
      const first = Math.min(1, 3200 / longest, pixelLimit);
      const detailed = Math.min(1, 4000 / longest, pixelLimit);
      const scales = detailed > first ? [first, detailed] : [first];
      for (const ratio of scales) {
        pixelMap = await source.createPixelMap({ editable: false,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredSize: { width: Math.max(1, Math.round(info.size.width * ratio)),
            height: Math.max(1, Math.round(info.size.height * ratio)) } });
        const text = await this.recognizePixelMap(pixelMap);
        if (text) { return text; }
        await pixelMap.release();
        pixelMap = null;
      }
      throw new Error('未识别到文字，请选择更清晰的图片');
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
    const result = await textRecognition.recognizeText({ pixelMap: pixelMap }, { isDirectionDetectionSupported: true });
    return OcrService.resultText(result);
  }

  private static resultText(result: textRecognition.TextRecognitionResult): string {
    const text = result && typeof result.value === 'string' ? result.value.trim() : '';
    if (!result || !Array.isArray(result.blocks)) { return text; }
    const blocks = result.blocks.map((block: textRecognition.TextBlock) => block.value.trim())
      .filter((value: string) => value.length > 0).join('\n\n');
    // Keep the SDK's order. Use paragraph boundaries only if all recognized characters match.
    return !text || blocks.replace(/\s/g, '') === text.replace(/\s/g, '') ? blocks : text;
  }
}
