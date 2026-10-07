import { Context } from '@kit.AbilityKit';
import { NoteItem } from '../../common/types/NoteItem';
import { ReviewCard } from '../../common/types/StudyTypes';
import { StudyBackup } from '../../common/types/StudyBackup';
import { StudyBackupPolicy } from './StudyBackupPolicy';
import { StudyBackupService } from './StudyBackupService';

export interface StudyImportResult { imported: number; skipped: number; }
export interface StudyImportPorts {
  notes: () => NoteItem[];
  commit: (note: NoteItem, cards: ReviewCard[]) => Promise<void>;
  progress: (message: string) => void;
}

/** File import and nearby reception use the same validation, stable IDs and recovery semantics. */
export class StudyImportService {
  static async restore(context: Context, input: StudyBackup, ports: StudyImportPorts): Promise<StudyImportResult> {
    const backup = StudyBackupPolicy.validate(input);
    let imported = 0; let skipped = 0;
    try {
      for (let i = 0; i < backup.notes.length; i++) {
        const id = StudyBackupPolicy.restoreId(backup, i);
        const existing = ports.notes().find((note: NoteItem) => note.id === id);
        ports.progress(`正在导入 ${i + 1}/${backup.notes.length}…`);
        const note = existing || await StudyBackupService.materialize(context, backup, i, StudyBackupPolicy.restoreTitle(backup, i));
        const cards = backup.cards.filter((card: ReviewCard) => card.noteId === backup.notes[i].id).map((card: ReviewCard, index: number): ReviewCard => ({
          id: `restorecard_${backup.id}_${i}_${index}`, noteId: id, course: note.category || '未分类', question: card.question,
          answer: card.answer, sourceText: card.sourceText, pageNumber: card.pageNumber, dueAt: card.dueAt,
          intervalDays: card.intervalDays, repetitions: card.repetitions, reviewCount: card.reviewCount, lapses: card.lapses,
          createdAt: card.createdAt, updatedAt: card.updatedAt, lastRating: card.lastRating }));
        await ports.commit(note, cards);
        if (existing) { skipped++; } else { imported++; }
      }
      return { imported, skipped };
    } catch (error) {
      throw new Error(`已导入 ${imported} 份。${error instanceof Error ? error.message : '导入中断'}；可重试，已导入资料会跳过。`);
    }
  }
}
