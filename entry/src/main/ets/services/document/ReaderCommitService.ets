import { NoteItem } from '../../common/types/NoteItem';
import { ReaderSaveKind } from '../../common/types/ReaderSaveKind';
import { SerialTaskQueue } from '../storage/SerialTaskQueue';

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
    const snapshot = JSON.parse(JSON.stringify(input)) as NoteItem;
    snapshot.contentDetail = content;
    return this.queue.run<void>(async () => {
      const existing = ports.notes().find((note: NoteItem) => note.id === snapshot.id);
      if (!existing) { throw new Error('目标笔记已移除，请先恢复资料再保存'); }
      let merged = this.merge(existing, snapshot, kind);
      if (writeDocument) { await ports.saveDocument(merged, merged.contentDetail); }
      const current = ports.notes();
      const latest = current.find((note: NoteItem) => note.id === snapshot.id);
      if (!latest) { throw new Error('目标笔记已移除，请先恢复资料再保存'); }
      merged = this.merge(latest, snapshot, kind);
      const next = current.map((note: NoteItem) => note.id === snapshot.id ? merged : note);
      await ports.saveNotes(next);
      ports.publish(next, merged);
    });
  }

  private merge(current: NoteItem, input: NoteItem, kind: ReaderSaveKind): NoteItem {
    const result = JSON.parse(JSON.stringify(current)) as NoteItem;
    if (kind === 'markdown') { result.title = input.title; result.contentDetail = input.contentDetail; result.previewText = input.previewText; }
    else if (kind === 'pdf') { result.pageAnnotations = input.pageAnnotations; }
    else if (kind === 'pdf-source') {
      result.sourceUri = input.sourceUri; result.sourceFileName = input.sourceFileName; result.sourceType = input.sourceType;
      result.pageCount = input.pageCount; result.type = input.type; result.pdfTextJson = input.pdfTextJson;
      result.pageInfo = input.pageInfo; result.documentMeta = input.documentMeta;
    }
    else if (kind === 'scratchpad') { result.scratchpadStrokes = input.scratchpadStrokes; }
    else {
      result.strokes = input.strokes;
      const type = current.type.toLowerCase();
      if (['canvas', '白板', '白纸笔记', 'handwriting', '稿纸'].includes(type)) {
        result.title = input.title; result.contentDetail = input.contentDetail; result.previewText = input.previewText;
      }
    }
    result.updateTime = input.updateTime; result.updatedAt = Date.now();
    if (result.createdAt === undefined) { result.createdAt = result.updatedAt; }
    return result;
  }
}
