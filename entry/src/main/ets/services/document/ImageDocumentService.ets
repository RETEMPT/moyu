import { Context } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { NoteItem } from '../../common/types/NoteItem';
import { DocumentTransferResult } from '../../common/types/MarkdownDocument';
import { ImageDocumentPolicy, ImageDocumentInfo } from './ImageDocumentPolicy';

export interface ImageDocumentPreview { pixels: image.PixelMap; info: ImageDocumentInfo; }
export interface ImportedImageDocument { path: string; info: ImageDocumentInfo; }

export class ImageDocumentService {
  static async importFile(context: Context, uri: string, name: string): Promise<ImportedImageDocument> {
    const extension = ImageDocumentPolicy.extension(name);
    if (!extension) { throw new Error('请选择 PNG、JPG、JPEG、WebP、BMP 或 GIF 图片'); }
    const directory = `${context.filesDir}/documents`;
    if (!await fs.access(directory)) { try { await fs.mkdir(directory, true); } catch { if (!await fs.access(directory)) { throw new Error('图片目录无法创建'); } } }
    const target = `${directory}/image_${Date.now()}_${Math.floor(Math.random() * 1000000000)}${extension}`;
    const source = await fs.open(uri, fs.OpenMode.READ_ONLY);
    try {
      const size = fs.statSync(source.fd).size;
      ImageDocumentPolicy.checkBytes(size);
      await fs.copyFile(source.fd, target);
      if (fs.statSync(target).size !== size) { throw new Error('图片复制不完整，请重试'); }
      const copy = await fs.open(target, fs.OpenMode.READ_WRITE);
      try { await fs.fsync(copy.fd); } finally { await fs.close(copy); }
      const preview = await ImageDocumentService.preview(context, target);
      try { return { path: target, info: preview.info }; } finally { await preview.pixels.release(); }
    } catch (error) {
      try { if (await fs.access(target)) { await fs.unlink(target); } } catch {}
      throw new Error(error instanceof Error ? error.message : '图片无法读取或复制失败，请检查原文件');
    } finally { await fs.close(source); }
  }

  static async preview(context: Context, path: string): Promise<ImageDocumentPreview> {
    if (!ImageDocumentPolicy.isManaged(context.filesDir, path)) { throw new Error('图片原件不可用，请重新导入'); }
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    let source: image.ImageSource | null = null;
    try {
      const bytes = fs.statSync(file.fd).size;
      ImageDocumentPolicy.checkBytes(bytes);
      source = image.createImageSource(file.fd);
      const raw = await source.getImageInfo(0);
      const info = ImageDocumentPolicy.info(raw.size.width, raw.size.height, bytes, raw.mimeType, ImageDocumentPolicy.extension(path));
      let orientationValue: string = '1';
      if (raw.mimeType === 'image/jpeg' || raw.mimeType === 'image/png') {
        try { orientationValue = await source.getImageProperty(image.PropertyKey.ORIENTATION, { index: 0, defaultValue: '1' }); } catch {}
      }
      const orientation = ImageDocumentPolicy.orientation(orientationValue);
      const pixels = await source.createPixelMap({ index: 0, editable: true, desiredSize: ImageDocumentPolicy.previewSize(info.width, info.height) });
      try {
        if (orientation.flipHorizontal || orientation.flipVertical) { await pixels.flip(orientation.flipHorizontal, orientation.flipVertical); }
        if (orientation.rotate) { await pixels.rotate(orientation.rotate); }
        const displayInfo: ImageDocumentInfo = { width: orientation.swapAxes ? info.height : info.width,
          height: orientation.swapAxes ? info.width : info.height, bytes: info.bytes, format: info.format };
        return { pixels, info: displayInfo };
      } catch (error) { try { await pixels.release(); } catch {} throw new Error(error instanceof Error ? error.message : '图片方向处理失败，请重试'); }
    } finally {
      if (source !== null) { try { await source.release(); } catch {} }
      try { await fs.close(file); } catch {}
    }
  }

  static async exportOriginal(context: Context, note: NoteItem): Promise<DocumentTransferResult> {
    try {
      const path = note.sourceUri || '';
      if (!ImageDocumentPolicy.isManaged(context.filesDir, path)) { throw new Error('图片原件不可用，请重新导入'); }
      const file = await fs.open(path, fs.OpenMode.READ_ONLY);
      let data: ArrayBuffer;
      try {
        const size = fs.statSync(file.fd).size; ImageDocumentPolicy.checkBytes(size);
        data = new ArrayBuffer(size);
        if (await fs.read(file.fd, data) !== size) { throw new Error('图片未完整读取，请重试'); }
      } finally { await fs.close(file); }
      const extension = ImageDocumentPolicy.extension(path);
      const stem = note.title.replace(/\.(png|jpe?g|webp|bmp|gif)$/i, '').replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').trim().substring(0, 80) || '图片';
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [stem + extension]; options.fileSuffixChoices = [`原始图片|${extension}`];
      const uris = await new picker.DocumentViewPicker(context).save(options);
      if (!uris.length) { return { status: 'cancelled', message: '已取消导出' }; }
      const output = await fs.open(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        if (await fs.write(output.fd, data) !== data.byteLength) { throw new Error('图片未完整写入，请重新选择位置'); }
        await fs.fsync(output.fd);
      } finally { await fs.close(output); }
      return { status: 'exported', message: '原始图片已导出，格式与文件内容保持不变。' };
    } catch (error) { return { status: 'failed', message: error instanceof Error ? error.message : '原图导出失败，请重试' }; }
  }
}
