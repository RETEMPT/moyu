export interface NoteSearchResult {
  noteId: string;
  title: string;
  fileName: string;
  matchedTitle: boolean;
  matchedContent: boolean;
  matchedTags: string[];
  preview: string;
  pageNumber?: number;
  sourceLine?: number;
  category?: string;
  format?: string;
}
