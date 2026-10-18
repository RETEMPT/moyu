import { NoteItem } from '../../common/types/NoteItem';
import { ReaderSaveKind } from '../../common/types/ReaderSaveKind';
import { SerialTaskQueue } from '../storage/SerialTaskQueue';
import { ReaderCommitPolicy } from './ReaderCommitPolicy';
import { copyNote } from '../../common/utils/NoteSnapshot';

export interface ReaderCommitPorts {
  notes: () => NoteItem[];
  saveDocument: (note: NoteItem, content: string) => Promise<void>;
  saveNotes: (notes: NoteItem[]) => Promise<void>;
  publish: (notes: NoteItem[], note: NoteItem) => void;
}

/** Serialize reader autosave and exit-save; publish only after the snapshot is persisted. */
export class ReaderCommitService {
  private queue: SerialTaskQueue = new SerialTaskQueue();

  commit(input: NoteItem, content: string, ports: ReaderCommitPorts, writeDocument: boolean = false,
    kind: ReaderSaveKind = 'markdown'): Promise<void> {
    const snapshot = copyNote(input);
    snapshot.contentDetail = content;
    return this.queue.run<void>(async () => {
      const existing = ports.notes().find((note: NoteItem) => note.id === snapshot.id);
      if (!existing) { throw new Error('目标笔记已移除，请先恢复资料再保存'); }
      const now = Date.now();
      let merged = ReaderCommitPolicy.merge(existing, snapshot, kind, now);
      if (writeDocument) { await ports.saveDocument(merged, merged.contentDetail); }
      const current = ports.notes();
      const latest = current.find((note: NoteItem) => note.id === snapshot.id);
      if (!latest) { throw new Error('目标笔记已移除，请先恢复资料再保存'); }
      merged = ReaderCommitPolicy.merge(latest, snapshot, kind, now);
      const next = current.map((note: NoteItem) => note.id === snapshot.id ? merged : note);
      try { await ports.saveNotes(next); }
      catch (error) {
        if (writeDocument) {
          const committed = ports.notes().find((note: NoteItem) => note.id === snapshot.id);
          // Restore only an extant record's committed body; never recreate a removed note.
          if (committed) {
            try { await ports.saveDocument(copyNote(committed), committed.contentDetail); }
            catch { throw new Error('资料索引保存失败，正文回退未完成；请保留当前内容并重试'); }
          }
        }
        throw new Error(error instanceof Error ? error.message : '资料索引保存失败，请重试');
      }
      ports.publish(next, merged);
    });
  }

}
