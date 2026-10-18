export interface ImageDocumentInfo { width: number; height: number; bytes: number; format: string; }
export interface ImagePreviewSize { width: number; height: number; }
export interface ImageOrientation { rotate: number; flipHorizontal: boolean; flipVertical: boolean; swapAxes: boolean; }

/** Raster-only imports. Original bytes remain immutable; previews have a bounded pixel budget. */
export class ImageDocumentPolicy {
  static readonly MAX_BYTES: number = 16 * 1024 * 1024;
  static readonly SUFFIXES: string[] = ['.png', '.jpg', '.jpeg', '.webp', '.bmp', '.gif'];
  static extension(name: string): string {
    const match = name.toLowerCase().match(/\.(png|jpe?g|webp|bmp|gif)$/);
    return match === null ? '' : match[0];
  }
  static mime(extension: string): string {
    return extension === '.jpg' || extension === '.jpeg' ? 'image/jpeg' : extension ? `image/${extension.substring(1)}` : '';
  }
  static checkBytes(bytes: number): void {
    if (!Number.isInteger(bytes) || bytes <= 0 || bytes > ImageDocumentPolicy.MAX_BYTES) { throw new Error('请选择非空且不超过 16 MB 的图片'); }
  }
  static info(width: number, height: number, bytes: number, mime: string, extension: string): ImageDocumentInfo {
    ImageDocumentPolicy.checkBytes(bytes);
    if (!Number.isInteger(width) || !Number.isInteger(height) || width <= 0 || height <= 0 ||
      width > 32768 || height > 32768 || width * height > 32 * 1024 * 1024) { throw new Error('图片尺寸过大或无效，请使用 3200 万像素以内的图片'); }
    const actual = mime === 'image/x-ms-bmp' || mime === 'image/x-bmp' ? 'image/bmp' : mime;
    if (!extension || actual !== ImageDocumentPolicy.mime(extension)) { throw new Error('图片实际格式与文件后缀不一致，或当前设备无法解码'); }
    return { width, height, bytes, format: extension === '.jpeg' ? 'JPG' : extension.substring(1).toUpperCase() };
  }
  static previewSize(width: number, height: number): ImagePreviewSize {
    const scale = Math.min(1, 4096 / Math.max(width, height), Math.sqrt(8 * 1024 * 1024 / (width * height)));
    return { width: Math.max(1, Math.floor(width * scale)), height: Math.max(1, Math.floor(height * scale)) };
  }
  static orientation(raw: string): ImageOrientation {
    const names = ['Top-left', 'Top-right', 'Bottom-right', 'Bottom-left', 'Left-top', 'Right-top', 'Right-bottom', 'Left-bottom'];
    const number = /^[1-8]$/.test(raw.trim()) ? Number(raw.trim()) : names.indexOf(raw.trim()) + 1;
    return { rotate: number === 3 ? 180 : number === 5 || number === 8 ? 270 : number === 6 || number === 7 ? 90 : 0,
      flipHorizontal: number === 2 || number === 5 || number === 7, flipVertical: number === 4, swapAxes: number >= 5 && number <= 8 };
  }
  static isManaged(filesDir: string, source: string): boolean {
    const prefix = `${filesDir}/documents/`;
    const name = source.startsWith(prefix) ? source.substring(prefix.length) : '';
    return name.length > 0 && !/[\\/\u0000-\u001f]/.test(name) && ImageDocumentPolicy.extension(name).length > 0;
  }
}
