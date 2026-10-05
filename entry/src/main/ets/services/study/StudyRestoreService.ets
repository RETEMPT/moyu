import { NoteItem } from '../../common/types/NoteItem';
import { ReviewCard } from '../../common/types/StudyTypes';

export interface StudyRestorePorts {
  notes: () => NoteItem[];
  cards: () => ReviewCard[];
  create: (note: NoteItem) => Promise<void>;
  saveNotes: (notes: NoteItem[]) => Promise<void>;
  saveCards: (cards: ReviewCard[]) => Promise<void>;
  remove: (note: NoteItem) => Promise<void>;
  publishNotes: (notes: NoteItem[]) => void;
  publishCards: (cards: ReviewCard[]) => void;
}

/** Each note is a separate commit. A card failure leaves a valid note and can be retried by stable IDs. */
export class StudyRestoreService {
  static async commit(note: NoteItem, cards: ReviewCard[], ports: StudyRestorePorts): Promise<void> {
    const previous = ports.notes().slice();
    const existing = previous.find((item: NoteItem) => item.id === note.id);
    const next = existing ? previous : previous.concat([note]);
    try {
      if (!existing) { await ports.create(note); }
      await ports.saveNotes(next);
    } catch {
      let rolledBack = false;
      try { await ports.saveNotes(previous); rolledBack = true; } catch { /* Preserve files when storage outcome is uncertain. */ }
      if (!existing && rolledBack) { try { await ports.remove(note); } catch { /* A retained orphan is safer than deleting original assets. */ } }
      throw new Error('资料保存未完成，原资料保留；请重试或重启后核对');
    }
    ports.publishNotes(next);
    const currentCards = ports.cards();
    const missing = cards.filter((card: ReviewCard) => !currentCards.some((item: ReviewCard) => item.id === card.id));
    if (!missing.length) { return; }
    const nextCards = currentCards.concat(missing);
    try { await ports.saveCards(nextCards); }
    catch { throw new Error('资料已导入，题卡保存失败；再次导入会补齐缺失题卡'); }
    ports.publishCards(nextCards);
  }
}
