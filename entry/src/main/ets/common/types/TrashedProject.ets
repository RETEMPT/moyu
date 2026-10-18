import { SpaceFolder } from './SpaceFolder';

export interface TrashedProject {
  id: string;
  project: SpaceFolder;
  noteIds: string[];
  deletedAt: number;
}
