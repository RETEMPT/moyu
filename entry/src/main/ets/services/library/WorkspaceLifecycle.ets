import { NoteItem } from '../../common/types/NoteItem';
import { SpaceFolder } from '../../common/types/SpaceFolder';
import { TrashedProject } from '../../common/types/TrashedProject';
import { copyNote } from '../../common/utils/NoteSnapshot';

export interface WorkspaceState {
  notes: NoteItem[];
  projects: SpaceFolder[];
  trash: NoteItem[];
  trashedProjects: TrashedProject[];
}

/** Immutable plans; the caller must persist the entire plan before publishing any of it. */
export class WorkspaceLifecycle {
  static deleteProject(state: WorkspaceState, name: string, now: number): WorkspaceState {
    const registered = state.projects.find((project: SpaceFolder) => project.name === name);
    const members = state.notes.filter((note: NoteItem) => note.category === name);
    if (!registered && members.length === 0) { throw new Error('项目已不存在'); }
    const project: SpaceFolder = { id: registered?.id || `space-${name}`, name,
      count: 0, isOpen: false, children: [], color: registered?.color, icon: registered?.icon, description: registered?.description };
    const ids = new Set(members.map((note: NoteItem) => note.id));
    const deleted = members.map((note: NoteItem): NoteItem => { const copy = copyNote(note); copy.deletedAt = now; return copy; });
    const group: TrashedProject = { id: `${project.id}-${now}`, project, noteIds: Array.from(ids), deletedAt: now };
    return { notes: state.notes.filter((note: NoteItem) => !ids.has(note.id)),
      projects: state.projects.filter((item: SpaceFolder) => item.name !== name),
      trash: deleted.concat(state.trash.filter((note: NoteItem) => !ids.has(note.id))),
      trashedProjects: [group].concat(state.trashedProjects) };
  }

  static restoreProject(state: WorkspaceState, id: string): WorkspaceState {
    const group = state.trashedProjects.find((item: TrashedProject) => item.id === id);
    if (!group) { throw new Error('回收站项目已不存在'); }
    if (state.projects.some((project: SpaceFolder) => project.name === group.project.name || project.id === group.project.id) ||
      state.notes.some((note: NoteItem) => note.category === group.project.name && !group.noteIds.includes(note.id))) {
      throw new Error('已有同名项目，请先重命名现有项目再恢复');
    }
    const ids = new Set(group.noteIds);
    const members = state.trash.filter((note: NoteItem) => ids.has(note.id) && note.deletedAt === group.deletedAt);
    const restoring = new Set(members.map((note: NoteItem) => note.id));
    const restored = members.map((note: NoteItem): NoteItem => {
      if (state.notes.some((item: NoteItem) => item.id === note.id)) { throw new Error('资料身份冲突，已保留回收站原记录'); }
      const copy = copyNote(note); copy.deletedAt = undefined; copy.category = group.project.name; return copy;
    });
    return { notes: restored.concat(state.notes), projects: state.projects.concat([group.project]),
      trash: state.trash.filter((note: NoteItem) => !restoring.has(note.id)),
      trashedProjects: state.trashedProjects.filter((item: TrashedProject) => item.id !== id) };
  }

  static deleteNote(state: WorkspaceState, id: string, now: number): WorkspaceState {
    const note = state.notes.find((item: NoteItem) => item.id === id);
    if (!note) { throw new Error('目标资料已不存在'); }
    const copy = copyNote(note); copy.deletedAt = now;
    return { notes: state.notes.filter((item: NoteItem) => item.id !== id), projects: state.projects,
      trash: [copy].concat(state.trash.filter((item: NoteItem) => item.id !== id)), trashedProjects: state.trashedProjects };
  }

  static restoreNote(state: WorkspaceState, id: string): WorkspaceState {
    const note = state.trash.find((item: NoteItem) => item.id === id);
    if (!note) { throw new Error('回收站资料已不存在'); }
    if (state.notes.some((item: NoteItem) => item.id === id)) { throw new Error('资料身份冲突，已保留回收站原记录'); }
    const copy = copyNote(note); copy.deletedAt = undefined;
    return { notes: [copy].concat(state.notes), projects: state.projects,
      trash: state.trash.filter((item: NoteItem) => item.id !== id),
      trashedProjects: state.trashedProjects };
  }

  static renameProject(state: WorkspaceState, oldName: string, name: string): WorkspaceState {
    if (!name.trim() || name === oldName) { throw new Error('请输入新的项目名称'); }
    if (state.projects.some((project: SpaceFolder) => project.name === name) || state.notes.some((note: NoteItem) => note.category === name)) {
      throw new Error('已有同名项目，请使用其他名称');
    }
    return { notes: state.notes.map((note: NoteItem): NoteItem => {
      if (note.category !== oldName) { return note; }
      const copy = copyNote(note); copy.category = name; return copy;
    }), projects: state.projects.map((project: SpaceFolder): SpaceFolder => project.name !== oldName ? project :
      { id: project.id, name, count: 0, isOpen: project.isOpen, children: [], color: project.color, icon: project.icon, description: project.description }),
      trash: state.trash, trashedProjects: state.trashedProjects };
  }
}
