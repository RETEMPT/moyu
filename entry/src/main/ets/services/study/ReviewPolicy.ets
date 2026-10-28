import { NoteItem } from '../../common/types/NoteItem';
import { TodoItem } from '../../common/types/TodoItem';
import { ReviewCard, ReviewDraft, ReviewRating, CourseSummary } from '../../common/types/StudyTypes';
import { StudySourceService } from './StudySourceService';

export class ReviewPolicy {
  static normalize(rows: ReviewCard[]): ReviewCard[] {
    if (!Array.isArray(rows)) { return []; }
    const result: ReviewCard[] = [];
    for (const row of rows) {
      if (!row || typeof row.id !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(row.id) ||
        typeof row.noteId !== 'string' || typeof row.course !== 'string' || typeof row.question !== 'string' ||
        !row.question.trim() || row.question.length > 4000 || typeof row.answer !== 'string' ||
        !row.answer.trim() || row.answer.length > 12000 || typeof row.sourceText !== 'string' || row.sourceText.length > 20000 ||
        !Number.isFinite(row.dueAt) || row.dueAt < 0 || result.some((card: ReviewCard) => card.id === row.id)) { continue; }
      result.push({ id: row.id, noteId: row.noteId, course: row.course, question: row.question, answer: row.answer,
        sourceText: row.sourceText, pageNumber: Number.isInteger(row.pageNumber) && (row.pageNumber || 0) > 0 ? row.pageNumber : undefined,
        dueAt: row.dueAt, intervalDays: Number.isFinite(row.intervalDays) ? Math.max(0, Math.min(180, row.intervalDays)) : 0,
        repetitions: Number.isFinite(row.repetitions) ? Math.max(0, Math.floor(row.repetitions)) : 0,
        reviewCount: Number.isFinite(row.reviewCount) ? Math.max(0, Math.floor(row.reviewCount || 0)) : Math.max(0, row.repetitions || 0),
        lapses: Number.isFinite(row.lapses) ? Math.max(0, Math.floor(row.lapses)) : 0,
        createdAt: Number.isFinite(row.createdAt) ? row.createdAt : 0, updatedAt: Number.isFinite(row.updatedAt) ? row.updatedAt : 0,
        lastRating: row.lastRating === 'again' || row.lastRating === 'hard' || row.lastRating === 'good' ? row.lastRating : undefined });
    }
    return result;
  }

  static create(note: NoteItem, draft: ReviewDraft, now: number = Date.now()): ReviewCard {
    if (!draft.question.trim() || draft.question.length > 4000 || !draft.answer.trim() || draft.answer.length > 12000) {
      throw new Error('请填写问题和参考答案，并控制长度');
    }
    return { id: `card_${now}_${Math.floor(Math.random() * 1000000)}`, noteId: note.id,
      course: note.category || '未分类', question: draft.question.trim(), answer: draft.answer.trim(),
      sourceText: draft.sourceText.slice(0, 20000), pageNumber: draft.pageNumber, dueAt: now,
      intervalDays: 0, repetitions: 0, reviewCount: 0, lapses: 0, createdAt: now, updatedAt: now };
  }

  static rate(card: ReviewCard, rating: ReviewRating, now: number = Date.now()): ReviewCard {
    if (!['again', 'hard', 'good'].includes(rating)) { throw new Error('无效的复习反馈'); }
    const days = rating === 'again' ? 1 : rating === 'hard' ? Math.max(1, Math.min(180, Math.ceil(card.intervalDays * 1.2))) :
      card.repetitions === 0 ? 3 : Math.min(180, Math.max(3, Math.ceil(card.intervalDays * 2)));
    const due = new Date(now);
    // Calendar days preserve local time across timezone/DST changes.
    due.setDate(due.getDate() + days);
    return { id: card.id, noteId: card.noteId, course: card.course, question: card.question, answer: card.answer,
      sourceText: card.sourceText, pageNumber: card.pageNumber, dueAt: due.getTime(), intervalDays: days,
      repetitions: rating === 'again' ? 0 : card.repetitions + 1, lapses: card.lapses + (rating === 'again' ? 1 : 0),
      reviewCount: (card.reviewCount || 0) + 1,
      createdAt: card.createdAt, updatedAt: now, lastRating: rating };
  }

  static edit(card: ReviewCard, draft: ReviewDraft, now: number): ReviewCard {
    if (!draft.question.trim() || draft.question.length > 4000 || !draft.answer.trim() || draft.answer.length > 12000 ||
      draft.sourceText.length > 20000) { throw new Error('请填写问题和参考答案，并控制长度'); }
    // Editing content does not turn into a review or erase the user's feedback/schedule.
    return { id: card.id, noteId: card.noteId, course: card.course, question: draft.question.trim(),
      answer: draft.answer.trim(), sourceText: draft.sourceText, pageNumber: card.pageNumber,
      dueAt: card.dueAt, intervalDays: card.intervalDays, repetitions: card.repetitions, reviewCount: card.reviewCount,
      lapses: card.lapses, createdAt: card.createdAt, updatedAt: now, lastRating: card.lastRating };
  }

  static courses(notes: NoteItem[], cards: ReviewCard[], todos: TodoItem[], now: number = Date.now()): CourseSummary[] {
    const grouped: Map<string, CourseSummary> = new Map();
    const noteCourses: Map<string, string> = new Map();
    for (const note of notes) {
      const name = note.category || '未分类';
      const course = grouped.get(name) || { name: name, noteCount: 0, cardCount: 0, dueCount: 0, todoCount: 0 } as CourseSummary;
      course.noteCount++; grouped.set(name, course); noteCourses.set(note.id, name);
    }
    for (const card of cards) {
      const name = noteCourses.get(card.noteId); const course = name === undefined ? undefined : grouped.get(name);
      if (course) { course.cardCount++; if (card.dueAt <= now) { course.dueCount++; } }
    }
    for (const todo of todos) {
      if (todo.done || !Array.isArray(todo.noteRefs)) { continue; }
      const seen: Set<string> = new Set();
      for (const id of todo.noteRefs) {
        const name = noteCourses.get(id);
        if (name !== undefined && !seen.has(name)) { grouped.get(name)!.todoCount++; seen.add(name); }
      }
    }
    return Array.from(grouped.values()).sort((a: CourseSummary, b: CourseSummary) => b.dueCount - a.dueCount || b.noteCount - a.noteCount);
  }
}
