import { Context } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { taskpool, util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { NoteItem } from '../../common/types/NoteItem';
import { ReviewCard } from '../../common/types/StudyTypes';
import { StudyBackup, BackupAsset } from '../../common/types/StudyBackup';
import { StudyBackupPolicy } from './StudyBackupPolicy';
import { NoteCoverService } from '../NoteCoverService';
import { PdfDocumentService } from '../document/PdfDocumentService';
import { ImageDocumentPolicy } from '../document/ImageDocumentPolicy';
import { ImageDocumentService } from '../document/ImageDocumentService';
import { validateBackupData, encodeBackupData, decodeBackupData } from './BackupCodec';

const MAX_BYTES: number = 32 * 1024 * 1024;

export class StudyBackupService {
  static async validate(input: StudyBackup): Promise<StudyBackup> {
    return await taskpool.execute(validateBackupData, input) as StudyBackup;
  }
  static async exportFile(context: Context, notes: NoteItem[], cards: ReviewCard[]): Promise<boolean> {
    const backup = await StudyBackupService.create(context, notes, cards);
    const buffer = await taskpool.execute(encodeBackupData, backup) as ArrayBuffer;
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`墨语学习备份_${new Date().toISOString().slice(0, 10)}.flowmind.json`];
    options.fileSuffixChoices = ['墨语学习备份|.json'];
    const uris = await new picker.DocumentViewPicker(context).save(options);
    if (!uris.length) { return false; }
    const file = await fs.open(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let closed = false;
    try {
      let offset = 0;
      while (offset < buffer.byteLength) {
        const written = await fs.write(file.fd, buffer.slice(offset, Math.min(offset + 512 * 1024, buffer.byteLength)));
        if (written <= 0) { throw new Error('备份未完整写入，请重试'); }
        offset += written;
      }
      await fs.fsync(file.fd);
    } catch (error) {
      try { await fs.close(file); closed = true; } catch { /* Best effort. */ }
      try { await fs.unlink(uris[0]); } catch { /* Leave the partial file for manual cleanup if unlink fails. */ }
      throw error instanceof Error ? error : new Error('备份写入失败');
    } finally { if (!closed) { await fs.close(file); } }
    return true;
  }

  /** Shared by file export and explicit nearby transfer; attachments are never silently dropped. */
  static async create(context: Context, notes: NoteItem[], cards: ReviewCard[]): Promise<StudyBackup> {
    const assets: BackupAsset[] = [];
    let total = 0;
    for (const note of notes) {
      if (note.sourceType === 'pdf' && !note.sourceUri && !note.id.startsWith('note-seed-')) { throw new Error(`《${note.title}》缺少原 PDF，请重新导入后备份`); }
      if (note.sourceType === 'image' && !note.sourceUri) { throw new Error(`《${note.title}》缺少原始图片，请重新导入后备份`); }
      const paths: string[] = [note.sourceType === 'pdf' || note.sourceType === 'image' ? note.sourceUri || '' : '', note.coverUrl || ''];
      for (let kind = 0; kind < paths.length; kind++) {
        const source = paths[kind];
        const allowed = kind === 0 ? StudyBackupService.documentPath(context, source) : NoteCoverService.isManaged(context, source);
        if (!source || source.startsWith('cover:')) { continue; }
        if (!allowed) { throw new Error(`《${note.title}》的附件不在应用目录，请重新导入后备份`); }
        const file = await fs.open(source, fs.OpenMode.READ_ONLY);
        try {
          const size = fs.statSync(file.fd).size;
          total += size;
          if (size <= 0 || size > 16 * 1024 * 1024 || total > 22 * 1024 * 1024) { throw new Error('附件较大，请按课程分批备份；单个附件上限 16 MB'); }
          const buffer = new ArrayBuffer(size);
          const read = await fs.read(file.fd, buffer);
          if (read !== size) { throw new Error('附件未完整读取，请重试'); }
          assets.push({ noteId: note.id, kind: kind === 0 ? note.sourceType === 'image' ? 'image' : 'pdf' : 'cover',
            extension: kind === 0 && note.sourceType === 'image' ? ImageDocumentPolicy.extension(source) : undefined,
            data: await new util.Base64Helper().encodeToString(new Uint8Array(buffer)) });
        } finally { await fs.close(file); }
      }
    }
    const backup: StudyBackup = { schemaVersion: 1, id: `${Date.now().toString(36)}${Math.floor(Math.random() * 1000000).toString(36)}`,
      createdAt: Date.now(), notes: notes,
      cards: cards.filter((card: ReviewCard) => notes.some((note: NoteItem) => note.id === card.noteId)), assets: assets };
    return await StudyBackupService.validate(backup);
  }

  static async createShareFile(context: Context, notes: NoteItem[], cards: ReviewCard[]): Promise<string> {
    if (notes.length === 0) { throw new Error('请先选择要发送的资料'); }
    const backup = await StudyBackupService.create(context, notes, cards);
    const buffer = await taskpool.execute(encodeBackupData, backup) as ArrayBuffer;
    const directory = context.cacheDir + '/study-share';
    if (!await fs.access(directory)) { await fs.mkdir(directory); }
    for (const name of await fs.listFile(directory)) {
      const match = /^study_(\d+)_([a-zA-Z0-9]+)\.flowmind\.json$/.exec(name);
      if (match && Date.now() - Number(match[1]) > 86400000) {
        try { await fs.unlink(directory + '/' + name); } catch { /* A file in use stays available to its receiver. */ }
      }
    }
    const target = directory + '/study_' + Date.now() + '_' + backup.id + '.flowmind.json';
    const file = await fs.open(target, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    let complete = false;
    try {
      let offset = 0;
      while (offset < buffer.byteLength) {
        const written = await fs.write(file.fd, buffer.slice(offset, Math.min(offset + 512 * 1024, buffer.byteLength)));
        if (written <= 0) { throw new Error('资料包未完整写入，请重试'); }
        offset += written;
      }
      await fs.fsync(file.fd); complete = true;
    } finally {
      try { await fs.close(file); }
      finally { if (!complete) { try { await fs.unlink(target); } catch { /* Only this failed package is eligible for cleanup. */ } } }
    }
    return target;
  }
  static async selectFile(context: Context): Promise<StudyBackup | null> {
    const options = new picker.DocumentSelectOptions(); options.maxSelectNumber = 1; options.fileSuffixFilters = ['.json'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (!uris.length) { return null; }
    const file = await fs.open(uris[0], fs.OpenMode.READ_ONLY);
    try {
      const size = fs.statSync(file.fd).size;
      if (size > MAX_BYTES) { throw new Error('备份文件超过 32 MB'); }
      const buffer = new ArrayBuffer(size);
      if (await fs.read(file.fd, buffer) !== size) { throw new Error('备份文件未完整读取'); }
      return await taskpool.execute(decodeBackupData, buffer) as StudyBackup;
    } finally { await fs.close(file); }
  }

  static async materialize(context: Context, backup: StudyBackup, index: number, title: string): Promise<NoteItem> {
    const note = StudyBackupPolicy.note(backup.notes[index]);
    note.id = StudyBackupPolicy.restoreId(backup, index); note.title = title; note.updateTime = '从备份恢复';
    note.updatedAt = Date.now();
    note.contentDetail = StudyBackupPolicy.restoreContent(backup, index);
    const created: string[] = [];
    try {
      for (const asset of backup.assets.filter((item: BackupAsset) => item.noteId === backup.notes[index].id)) {
        const directory = `${context.filesDir}/${asset.kind === 'pdf' || asset.kind === 'image' ? 'documents' : 'covers'}`;
        if (!fs.accessSync(directory)) { fs.mkdirSync(directory); }
        const target = `${directory}/${note.id}_${Date.now()}${asset.kind === 'image' ? asset.extension : asset.kind === 'pdf' ? '.pdf' : '.img'}`;
        const bytes = await new util.Base64Helper().decode(asset.data);
        const file = await fs.open(target, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        created.push(target);
        try {
          const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
          if (await fs.write(file.fd, buffer) !== bytes.length) { throw new Error('附件写入不完整'); }
          await fs.fsync(file.fd);
        } finally { await fs.close(file); }
        if (asset.kind === 'pdf') {
          note.pageCount = (await PdfDocumentService.getInstance().validateImport(target)).pageCount;
          note.sourceUri = target; note.sourceFileName = target.split('/').pop(); note.sourceType = 'pdf';
        } else if (asset.kind === 'image') {
          const preview = await ImageDocumentService.preview(context, target);
          try { note.documentMeta = JSON.stringify(preview.info); } finally { await preview.pixels.release(); }
          note.type = 'Image'; note.sourceType = 'image'; note.sourceUri = target; note.sourceFileName = target.split('/').pop(); note.pageCount = 1;
        } else {
          const source = image.createImageSource(target);
          try { await source.getImageInfo(); } finally { await source.release(); }
          note.coverUrl = target;
        }
      }
      return note;
    } catch (error) {
      for (const filename of created) { try { await fs.unlink(filename); } catch { /* Retry cleanup on next backup; existing notes were never changed. */ } }
      throw new Error(error instanceof Error ? error.message : '附件恢复失败');
    }
  }
  private static documentPath(context: Context, source: string): boolean {
    const prefix = `${context.filesDir}/documents/`;
    const name = source.startsWith(prefix) ? source.substring(prefix.length) : '';
    return name.length > 0 && name !== '.' && name !== '..' && !name.includes('/') && !name.includes('\\');
  }
}
