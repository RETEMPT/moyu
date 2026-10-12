import { NoteItem } from '../../common/types/NoteItem';
import { StudySourceService } from '../study/StudySourceService';
import { searchTerms } from '../../common/utils/SearchTerms';

/** Searches readable text locally, never binary-note placeholders. */
export class AiReferenceSearch {
  static find(notes: NoteItem[], query: string, excluded: string[] = []): NoteItem[] {
    const terms = searchTerms(query);
    return notes.filter((n: NoteItem) => {
      if (n.deletedAt || excluded.includes(n.id)) { return false; }
      if (!terms.length) { return true; }
      const metadata = `${n.title} ${n.category} ${n.tag} ${(n.tags || []).join(' ')}`.toLocaleLowerCase();
      let remaining = terms.filter((term: string) => !metadata.includes(term));
      if (!remaining.length) { return true; }
      const binary = n.sourceType === 'pdf' || /^(pdf|doc|canvas|handwriting|白纸笔记|稿纸)$/i.test(n.type);
      if (binary) {
        for (const page of StudySourceService.pages(n)) {
          const text = page.text.toLocaleLowerCase();
          remaining = remaining.filter((term: string) => !text.includes(term));
          if (!remaining.length) { return true; }
        }
        return false;
      }
      const text = (n.contentDetail || '').toLocaleLowerCase();
      return remaining.every((term: string) => text.includes(term));
    }).sort((a: NoteItem, b: NoteItem) => {
      const titleA = terms.filter((s: string) => a.title.toLocaleLowerCase().includes(s)).length;
      const titleB = terms.filter((s: string) => b.title.toLocaleLowerCase().includes(s)).length;
      return titleB - titleA || (b.updatedAt || 0) - (a.updatedAt || 0);
    }).slice(0, 40);
  }
}
