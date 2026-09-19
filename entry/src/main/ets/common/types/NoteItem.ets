export interface NoteItem {
  id: string;
  title: string;
  category: string;
  type: string;
  previewText: string;
  tag: string;
  tagColor: string;
  updateTime: string;
  contentDetail: string;
  pageInfo?: string;
  extraInfo?: string;
  coverUrl?: string;
  strokes?: string;
  scratchpadStrokes?: string;
  pageAnnotations?: string;
}

