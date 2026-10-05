import { NoteItem } from '../../common/types/NoteItem';
import { StudyBackup, BackupAsset } from '../../common/types/StudyBackup';
import { ReviewPolicy } from './ReviewPolicy';
import { StudySourceService } from './StudySourceService';
import { isCoverPreset } from '../../common/types/NoteCover';
import { MarkdownParserService } from '../MarkdownParserService';

export class StudyBackupPolicy {
  static note(note: NoteItem): NoteItem {
    if (!note || typeof note.id !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(note.id) || typeof note.title !== 'string' || note.title.length > 500 ||
      typeof note.contentDetail !== 'string' || note.contentDetail.length > 2000000 || typeof note.category !== 'string' ||
      note.category.length > 500 || typeof note.type !== 'string') { throw new Error('备份笔记格式无效'); }
    if ([note.strokes, note.scratchpadStrokes, note.pageAnnotations].some((value: string | undefined) => typeof value === 'string' && value.length >= 8000000)) {
      throw new Error('单份笔迹数据较大，请先导出原资料或缩小笔记后备份');
    }
    return { id: note.id, title: note.title, category: note.category, type: note.type,
      previewText: typeof note.previewText === 'string' ? note.previewText.slice(0, 2000) : '',
      tag: typeof note.tag === 'string' ? note.tag.slice(0, 2000) : '',
      tagColor: typeof note.tagColor === 'string' && /^#[0-9a-f]{6}$/i.test(note.tagColor) ? note.tagColor : '#2563EB',
      updateTime: typeof note.updateTime === 'string' ? note.updateTime.slice(0, 100) : '',
      contentDetail: note.contentDetail, favorite: note.favorite === true, isPinned: note.isPinned === true,
      tags: Array.isArray(note.tags) ? note.tags.filter((tag: string) => typeof tag === 'string' && tag.length < 200).slice(0, 100) : [],
      createdAt: Number.isFinite(note.createdAt) ? note.createdAt : 0, updatedAt: Number.isFinite(note.updatedAt) ? note.updatedAt : 0,
      strokes: typeof note.strokes === 'string' && note.strokes.length < 8000000 ? note.strokes : undefined,
      scratchpadStrokes: typeof note.scratchpadStrokes === 'string' && note.scratchpadStrokes.length < 8000000 ? note.scratchpadStrokes : undefined,
      pageAnnotations: typeof note.pageAnnotations === 'string' && note.pageAnnotations.length < 8000000 ? note.pageAnnotations : undefined,
      sourceType: note.sourceType === 'pdf' ? 'pdf' : undefined,
      pageCount: Number.isInteger(note.pageCount) && (note.pageCount || 0) > 0 && (note.pageCount || 0) <= 10000 ? note.pageCount : undefined,
      coverUrl: typeof note.coverUrl === 'string' && isCoverPreset(note.coverUrl) ? note.coverUrl : undefined,
      pdfTextJson: JSON.stringify(StudySourceService.pages(note)) };
  }
  static validate(input: StudyBackup): StudyBackup {
    if (!input || input.schemaVersion !== 1 || typeof input.id !== 'string' || !/^[a-zA-Z0-9]{1,24}$/.test(input.id) ||
      !Number.isFinite(input.createdAt) || !Array.isArray(input.notes) || input.notes.length > 2000 ||
      !Array.isArray(input.cards) || input.cards.length > 10000 || !Array.isArray(input.assets) || input.assets.length > 4000) {
      throw new Error('此文件不是支持的墨语学习备份');
    }
    const notes = input.notes.map((note: NoteItem) => StudyBackupPolicy.note(note));
    if (new Set(notes.map((note: NoteItem) => note.id)).size !== notes.length) { throw new Error('备份含重复笔记 ID'); }
    const cards = ReviewPolicy.normalize(input.cards);
    if (cards.length !== input.cards.length || cards.some((card) => !notes.some((note: NoteItem) => note.id === card.noteId))) {
      throw new Error('备份复习记录或关联资料无效');
    }
    const assets: BackupAsset[] = [];
    for (const asset of input.assets) {
      if (!asset || !notes.some((note: NoteItem) => note.id === asset.noteId) || !['pdf', 'cover'].includes(asset.kind) ||
        typeof asset.data !== 'string' || asset.data.length > 24 * 1024 * 1024 || !asset.data.length ||
        asset.data.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(asset.data) ||
        assets.some((item: BackupAsset) => item.noteId === asset.noteId && item.kind === asset.kind)) { throw new Error('备份附件无效'); }
      assets.push({ noteId: asset.noteId, kind: asset.kind, data: asset.data });
    }
    if (notes.some((note: NoteItem) => note.sourceType === 'pdf' && !note.id.startsWith('note-seed-') &&
      !assets.some((asset: BackupAsset) => asset.noteId === note.id && asset.kind === 'pdf'))) {
      throw new Error('备份缺少原 PDF，无法完整恢复阅读资料');
    }
    return { schemaVersion: 1, id: input.id, createdAt: input.createdAt, notes: notes, cards: cards, assets: assets };
  }
  static restoreId(backup: StudyBackup, noteIndex: number): string {
    const note = backup.notes[noteIndex];
    // The existing reader identifies bundled examples by this prefix. Do not turn a sample into a broken real-PDF entry.
    const example = note.id.startsWith('note-seed-') && !backup.assets.some((asset: BackupAsset) => asset.noteId === note.id && asset.kind === 'pdf');
    return `${example ? 'note-seed-' : ''}restore_${backup.id}_${noteIndex}`;
  }
  static restoreTitle(backup: StudyBackup, noteIndex: number): string {
    const title = backup.notes[noteIndex].title;
    const repeated = title.length > 450 || backup.notes.filter((note: NoteItem) => note.title === title).length > 1;
    return `${title.slice(0, 450)}（备份恢复${repeated ? ` ${noteIndex + 1}` : ''}）`;
  }
  /** Remap only unambiguous links within the package. External and code-block text stay intact. */
  static restoreContent(backup: StudyBackup, noteIndex: number): string {
    const note = backup.notes[noteIndex];
    const counts = new Map<string, number>();
    const titles = new Map<string, string>();
    backup.notes.forEach((item: NoteItem) => { counts.set(item.title, (counts.get(item.title) || 0) + 1); });
    backup.notes.forEach((item: NoteItem, index: number) => {
      const repeated = item.title.length > 450 || (counts.get(item.title) || 0) > 1;
      titles.set(item.title, `${item.title.slice(0, 450)}（备份恢复${repeated ? ` ${index + 1}` : ''}）`);
    });
    const links = new MarkdownParserService().parse({ id: note.id, title: note.title, fileName: '', filePath: '',
      content: note.contentDetail, updatedAt: 0 }).links;
    const lines = new Set(links.map((link) => link.line));
    return note.contentDetail.split('\n').map((line: string, index: number) => {
      if (!lines.has(index + 1)) { return line; }
      return line.replace(/\[\[([^\]|#]+)(?:\|([^\]]+))?\]\]/g, (match: string, target: string, label: string | undefined): string => {
        const key = target.trim();
        return counts.get(key) === 1 ? `[[${titles.get(key)}|${label === undefined ? key : label}]]` : match;
      });
    }).join('\n');
  }
}
