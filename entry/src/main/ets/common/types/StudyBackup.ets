import { NoteItem } from './NoteItem';
import { ReviewCard } from './StudyTypes';

export const STUDY_PACKAGE_UTD: string = 'general.json';
export const STUDY_PACKAGE_SUFFIX: string = '.flowmind.json';

export interface BackupAsset { noteId: string; kind: 'pdf' | 'image' | 'cover'; data: string; extension?: string; }
export interface StudyBackup {
  schemaVersion: number;
  id: string;
  createdAt: number;
  notes: NoteItem[];
  cards: ReviewCard[];
  assets: BackupAsset[];
}
