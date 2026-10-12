import { NoteItem } from '../common/types/NoteItem';
import { SpaceFolder } from '../common/types/SpaceFolder';

export interface GraphTopic { name: string; count: number; }

/** Empty persisted projects remain selectable; note-only categories are also retained. */
export class GraphTopicPolicy {
  static topics(notes: NoteItem[], projects: SpaceFolder[]): GraphTopic[] {
    const counts: Map<string, number> = new Map();
    for (const project of projects) {
      const name = project.name.trim();
      if (name) { counts.set(name, 0); }
    }
    for (const note of notes) {
      const name = note.category?.trim() || '未分类';
      counts.set(name, (counts.get(name) || 0) + 1);
    }
    const result: GraphTopic[] = [];
    counts.forEach((count: number, name: string) => result.push({ name, count }));
    return result;
  }
}
