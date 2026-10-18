import { common } from '@kit.AbilityKit';
import { UIContext } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { DocumentTransferResult } from '../../common/types/MarkdownDocument';

/** Captures only the mounted document viewport, without application chrome. */
export class ReaderOutputService {
  static async saveScreenshot(context: common.UIAbilityContext, ui: UIContext, componentId: string, title: string): Promise<DocumentTransferResult> {
    let pixels: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      pixels = await ui.getComponentSnapshot().get(componentId, { scale: 1, waitUntilRenderFinished: true });
      const info = await pixels.getImageInfo();
      if (info.size.width * info.size.height > 16 * 1024 * 1024) { throw new Error('当前截图区域过大，请缩小窗口后重试'); }
      packer = image.createImagePacker();
      const data = await packer.packing(pixels, { format: 'image/png', quality: 100 });
      await packer.release(); packer = null;
      await pixels.release(); pixels = null;
      const options = new picker.DocumentSaveOptions();
      const name = title.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').trim().substring(0, 80) || '笔记';
      options.newFileNames = [`${name}-正文截图.png`];
      options.fileSuffixChoices = ['PNG 图片|.png'];
      const uris = await new picker.DocumentViewPicker(context).save(options);
      if (uris.length === 0) { return { status: 'cancelled', message: '已取消保存，未写入图片' }; }
      const file = await fileIo.open(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        let offset: number = 0;
        while (offset < data.byteLength) {
          const written = await fileIo.write(file.fd, data.slice(offset));
          if (written <= 0 || written > data.byteLength - offset) { throw new Error('图片未能完整写入，请重新选择位置保存'); }
          offset += written;
        }
        await fileIo.fsync(file.fd);
      } finally { await fileIo.close(file); }
      return { status: 'exported', message: '正文截图已保存到所选位置（PNG）。' };
    } catch (error) {
      return { status: 'failed', message: error instanceof Error ? error.message : '截图保存失败，请检查页面是否加载完成后重试' };
    } finally {
      if (packer !== null) { try { await packer.release(); } catch {} }
      if (pixels !== null) { try { await pixels.release(); } catch {} }
    }
  }
}
