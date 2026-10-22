import { NoteItem } from '../../common/types/NoteItem';
import { LearningOverview, MaterialLearningProgress, ReviewCard } from '../../common/types/StudyTypes';
import { ReadingProgressPolicy } from '../document/ReadingProgressPolicy';

/** Local, deterministic projection; callers pass committed records and an explicit clock. */
export class LearningProgressPolicy {
  static notes(notes: NoteItem[], course: string): NoteItem[] {
    return notes.filter((note: NoteItem) => !note.deletedAt && (!course || (note.category || '未分类') === course));
  }

  static cards(notes: NoteItem[], cards: ReviewCard[], course: string): ReviewCard[] {
    const ids = new Set(LearningProgressPolicy.notes(notes, course).map((note: NoteItem) => note.id));
    return cards.filter((card: ReviewCard) => ids.has(card.noteId));
  }

  static weak(card: ReviewCard): boolean { return card.lastRating === 'again' || card.lastRating === 'hard'; }

  static queue(notes: NoteItem[], cards: ReviewCard[], course: string, now: number, weakOnly: boolean = false): ReviewCard[] {
    return LearningProgressPolicy.cards(notes, cards, course)
      .filter((card: ReviewCard) => card.dueAt <= now && (!weakOnly || LearningProgressPolicy.weak(card)))
      .sort((a: ReviewCard, b: ReviewCard) => Number(LearningProgressPolicy.weak(b)) - Number(LearningProgressPolicy.weak(a)) ||
        a.dueAt - b.dueAt || a.id.localeCompare(b.id));
  }

  static overview(notes: NoteItem[], cards: ReviewCard[], course: string, now: number): LearningOverview {
    const available = LearningProgressPolicy.notes(notes, course);
    const grouped: Map<string, MaterialLearningProgress> = new Map();
    const result: LearningOverview = { noteCount: available.length, openedCount: 0, cardCount: 0,
      dueCount: 0, newCount: 0, weakCount: 0, weakDueCount: 0, goodCount: 0, materials: [] };
    for (const note of available) {
      if (ReadingProgressPolicy.hasRead(note)) { result.openedCount++; }
      grouped.set(note.id, { noteId: note.id, title: note.title, course: note.category || '未分类',
        readingLabel: ReadingProgressPolicy.label(note), cardCount: 0, dueCount: 0, newCount: 0, weakCount: 0, goodCount: 0 });
    }
    for (const card of cards) {
      const material = grouped.get(card.noteId);
      if (!material) { continue; }
      material.cardCount++; result.cardCount++;
      if (card.dueAt <= now) { material.dueCount++; result.dueCount++; }
      if (LearningProgressPolicy.weak(card)) {
        material.weakCount++; result.weakCount++;
        if (card.dueAt <= now) { result.weakDueCount++; }
      } else if (card.lastRating === 'good') { material.goodCount++; result.goodCount++; }
      else if (!(card.reviewCount || card.repetitions)) { material.newCount++; result.newCount++; }
    }
    result.materials = Array.from(grouped.values()).sort((a: MaterialLearningProgress, b: MaterialLearningProgress) =>
      b.dueCount - a.dueCount || b.weakCount - a.weakCount || a.title.localeCompare(b.title) || a.noteId.localeCompare(b.noteId));
    return result;
  }

  static suggestion(overview: LearningOverview): string {
    if (overview.dueCount > 0) {
      return `先完成 ${overview.dueCount} 道到期题卡，其中 ${overview.weakDueCount} 道上次反馈为不会或模糊。`;
    }
    if (overview.cardCount === 0) { return '从一份正在研读的资料手动建立题卡，再用自测反馈安排复习。'; }
    if (overview.weakCount > 0) { return `当前没有到期题卡，可先回看 ${overview.weakCount} 道待巩固题的原文。`; }
    return '当前没有到期题卡，可继续研读资料，或为新内容建立题卡。';
  }
}
