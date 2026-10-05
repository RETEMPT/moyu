export interface PdfTextPage {
  pageNumber: number;
  text: string;
  method: 'text' | 'ocr';
  extractedAt: number;
}

export type ReviewRating = 'again' | 'hard' | 'good';
export interface ReviewCard {
  id: string;
  noteId: string;
  course: string;
  question: string;
  answer: string;
  sourceText: string;
  pageNumber?: number;
  dueAt: number;
  intervalDays: number;
  repetitions: number;
  reviewCount?: number;
  lapses: number;
  createdAt: number;
  updatedAt: number;
  lastRating?: ReviewRating;
}
export interface CourseSummary {
  name: string;
  noteCount: number;
  cardCount: number;
  dueCount: number;
  todoCount: number;
}
export interface ReviewDraft {
  question: string;
  answer: string;
  sourceText: string;
  pageNumber?: number;
}
