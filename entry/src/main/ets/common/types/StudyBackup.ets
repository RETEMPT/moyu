import { NoteItem } from './NoteItem';
import { ReviewCard } from './StudyTypes';

export interface BackupAsset { noteId: string; kind: 'pdf' | 'image' | 'cover'; data: string; extension?: string; }
export interface StudyBackup {
  schemaVersion: number;
  id: string;
  createdAt: number;
  notes: NoteItem[];
  cards: ReviewCard[];
  assets: BackupAsset[];
}
