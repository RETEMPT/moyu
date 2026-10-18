import { NoteItem } from '../../common/types/NoteItem';

/** Keep the existing filename mapping, but reject ambiguous identities before any write. */
export class NoteIdentity {
  static fileName(id: string): string {
    if (typeof id !== 'string' || !id.trim() || id.length > 251) { throw new Error('资料身份无效，已阻止写入'); }
    return id.replace(/[^a-zA-Z0-9_-]/g, '_');
  }

  static validNotes(notes: NoteItem[]): boolean {
    if (!Array.isArray(notes)) { return false; }
    const ids: Set<string> = new Set();
    const files: Set<string> = new Set();
    for (const note of notes) {
      if (!note || typeof note.title !== 'string' || typeof note.contentDetail !== 'string') { return false; }
      let file = '';
      try { file = NoteIdentity.fileName(note.id); } catch { return false; }
      if (ids.has(note.id) || files.has(file)) { return false; }
      ids.add(note.id); files.add(file);
    }
    return true;
  }

  static requireNotes(notes: NoteItem[]): void {
    if (!NoteIdentity.validNotes(notes)) { throw new Error('资料身份重复或内容格式异常，原数据已保留，已阻止覆盖'); }
  }
}
