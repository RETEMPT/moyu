import { NoteItem } from './NoteItem';
import { ReviewCard } from './StudyTypes';

export interface BackupAsset { noteId: string; kind: 'pdf' | 'cover'; data: string; }
export interface StudyBackup {
  schemaVersion: number;
  id: string;
  createdAt: number;
  notes: NoteItem[];
  cards: ReviewCard[];
  assets: BackupAsset[];
}
