import { Context } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { isCoverPreset } from '../common/types/NoteCover';

/** Gallery grants are temporary; copy a selected image before saving its reference. */
export class NoteCoverService {
  static async prepare(context: Context, noteId: string, source: string): Promise<string> {
    if (source.length === 0 || isCoverPreset(source) || NoteCoverService.isManaged(context, source)) { return source; }
    if (source.startsWith('cover:')) { throw new Error('封面样式不存在'); }
    const directory = `${context.filesDir}/covers`;
    if (!fs.accessSync(directory)) { fs.mkdirSync(directory); }
    const file = fs.openSync(source, fs.OpenMode.READ_ONLY);
    const target = `${directory}/${noteId.replace(/[^a-zA-Z0-9_-]/g, '_')}_${Date.now()}.img`;
    try {
      const size = fs.statSync(file.fd).size;
      if (size <= 0 || size > 12 * 1024 * 1024) { throw new Error('请选择 12 MB 以内的图片'); }
      await fs.copyFile(file.fd, target);
      return target;
    } catch {
      try { fs.unlinkSync(target); } catch { /* Nothing copied. */ }
      throw new Error('封面图片保存失败，请检查文件或存储空间');
    } finally { fs.closeSync(file); }
  }

  static isManaged(context: Context, source: string): boolean {
    const prefix = `${context.filesDir}/covers/`;
    if (!source.startsWith(prefix)) { return false; }
    const name = source.substring(prefix.length);
    return name.length > 0 && name !== '.' && name !== '..' && !name.includes('/') && !name.includes('\\');
  }

  static async removeManaged(context: Context, source: string): Promise<void> {
    if (NoteCoverService.isManaged(context, source) && await fs.access(source)) { await fs.unlink(source); }
  }
}
