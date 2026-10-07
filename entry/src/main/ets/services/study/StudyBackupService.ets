import { Context } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { NoteItem } from '../../common/types/NoteItem';
import { ReviewCard } from '../../common/types/StudyTypes';
import { StudyBackup, BackupAsset } from '../../common/types/StudyBackup';
import { StudyBackupPolicy } from './StudyBackupPolicy';
import { NoteCoverService } from '../NoteCoverService';
import { PdfDocumentService } from '../document/PdfDocumentService';

const MAX_BYTES: number = 32 * 1024 * 1024;

export class StudyBackupService {
  static async exportFile(context: Context, notes: NoteItem[], cards: ReviewCard[]): Promise<boolean> {
    const backup = await StudyBackupService.create(context, notes, cards);
    const content = JSON.stringify(backup);
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [`墨语学习备份_${new Date().toISOString().slice(0, 10)}.flowmind.json`];
    options.fileSuffixChoices = ['墨语学习备份|.json'];
    const uris = await new picker.DocumentViewPicker(context).save(options);
    if (!uris.length) { return false; }
    const file = await fs.open(uris[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      const expected = new util.TextEncoder().encodeInto(content).length;
      if (await fs.write(file.fd, content) !== expected) { throw new Error('备份未完整写入，请重试'); }
      await fs.fsync(file.fd);
    } finally { await fs.close(file); }
    return true;
  }

  /** Shared by file export and explicit nearby transfer; attachments are never silently dropped. */
  static async create(context: Context, notes: NoteItem[], cards: ReviewCard[]): Promise<StudyBackup> {
    const assets: BackupAsset[] = [];
    let total = 0;
    for (const note of notes) {
      if (note.sourceType === 'pdf' && !note.sourceUri && !note.id.startsWith('note-seed-')) { throw new Error(`《${note.title}》缺少原 PDF，请重新导入后备份`); }
      const paths: string[] = [note.sourceType === 'pdf' ? note.sourceUri || '' : '', note.coverUrl || ''];
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
          assets.push({ noteId: note.id, kind: kind === 0 ? 'pdf' : 'cover', data: new util.Base64Helper().encodeToStringSync(new Uint8Array(buffer)) });
        } finally { await fs.close(file); }
      }
    }
    const backup: StudyBackup = { schemaVersion: 1, id: `${Date.now().toString(36)}${Math.floor(Math.random() * 1000000).toString(36)}`,
      createdAt: Date.now(), notes: notes.map((note: NoteItem) => StudyBackupPolicy.note(note)),
      cards: cards.filter((card: ReviewCard) => notes.some((note: NoteItem) => note.id === card.noteId)), assets: assets };
    const content = JSON.stringify(StudyBackupPolicy.validate(backup));
    if (new util.TextEncoder().encodeInto(content).length > MAX_BYTES) { throw new Error('备份超过 32 MB，请按课程分批导出'); }
    return StudyBackupPolicy.validate(backup);
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
      const raw = new util.TextDecoder().decodeToString(new Uint8Array(buffer));
      return StudyBackupPolicy.validate(JSON.parse(raw) as StudyBackup);
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
        const directory = `${context.filesDir}/${asset.kind === 'pdf' ? 'documents' : 'covers'}`;
        if (!fs.accessSync(directory)) { fs.mkdirSync(directory); }
        const target = `${directory}/${note.id}_${Date.now()}${asset.kind === 'pdf' ? '.pdf' : '.img'}`;
        const bytes = new util.Base64Helper().decodeSync(asset.data);
        const file = await fs.open(target, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        created.push(target);
        try {
          const buffer = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
          if (await fs.write(file.fd, buffer) !== bytes.length) { throw new Error('附件写入不完整'); }
          await fs.fsync(file.fd);
        } finally { await fs.close(file); }
        if (asset.kind === 'pdf') {
          note.pageCount = (await PdfDocumentService.getInstance().getPdfInfo(target)).pageCount;
          note.sourceUri = target; note.sourceType = 'pdf';
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
