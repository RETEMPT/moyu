export interface NoteSearchResult {
  noteId: string;
  title: string;
  fileName: string;
  matchedTitle: boolean;
  matchedContent: boolean;
  matchedTags: string[];
  preview: string;
}
