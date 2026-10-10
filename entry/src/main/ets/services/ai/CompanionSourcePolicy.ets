import { NoteItem } from '../../common/types/NoteItem';
import { StudySourceService } from '../study/StudySourceService';

export class CompanionSourcePolicy {
  static binary(note: NoteItem): boolean { return note.sourceType === 'pdf' || /^(pdf|doc|handwriting|canvas|白纸笔记|稿纸)$/i.test(note.type); }
  static snapshot(note: NoteItem, page: number, currentPageOnly: boolean): NoteItem {
    const copy = JSON.parse(JSON.stringify(note)) as NoteItem;
    if (CompanionSourcePolicy.binary(copy)) {
      // Imported metadata and blank canvas descriptions are not evidence.
      copy.contentDetail = '';
      copy.pdfTextJson = JSON.stringify(StudySourceService.pages(note).filter((p) => !currentPageOnly || p.pageNumber === page));
    }
    return copy;
  }
  static readable(note: NoteItem): boolean {
    return CompanionSourcePolicy.binary(note) ? StudySourceService.pages(note).some((p) => p.text.trim().length > 0) : (note.contentDetail || '').trim().length > 0;
  }
}
