import { NoteItem } from './NoteItem';

export interface SpaceFolder {
  id: string;
  name: string;
  count: number;
  isOpen: boolean;
  children: string[];
  color?: string;
  icon?: string;
  description?: string;
  notes?: NoteItem[];
}

