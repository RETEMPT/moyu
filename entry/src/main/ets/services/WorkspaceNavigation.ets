import { FILTER_ALL, NAV_CHAT, NAV_FAVORITE, NAV_GRAPH, NAV_HOME, NAV_LIBRARY, NAV_SETTINGS, NAV_TODO, NAV_TRASH } from '../common/constants/WorkspaceConstants';
import { ReadingStatus } from './document/ReadingProgressPolicy';

export interface WorkspaceLocation {
  page: string;
  projectId: string;
  query: string;
  filter: string;
  tags: string[];
  readingStatus: ReadingStatus;
}

/** Section switches start a new trail. Links between sections can return to their exact origin. */
export class WorkspaceNavigation {
  static isPage(page: string): boolean {
    return [NAV_HOME, NAV_LIBRARY, NAV_CHAT, NAV_GRAPH, NAV_TODO, NAV_FAVORITE, NAV_TRASH, NAV_SETTINGS].includes(page);
  }

  static location(page: string, projectId: string = '', query: string = '', filter: string = FILTER_ALL,
    tags: string[] = [], readingStatus: ReadingStatus = 'all'): WorkspaceLocation {
    return { page, projectId, query, filter, tags: tags.slice(), readingStatus };
  }

  static trail(history: WorkspaceLocation[], from: WorkspaceLocation, to: WorkspaceLocation,
    returnToOrigin: boolean): WorkspaceLocation[] {
    if (!returnToOrigin) { return []; }
    if (from.page === to.page && from.projectId === to.projectId && from.query === to.query && from.filter === to.filter &&
      from.readingStatus === to.readingStatus && from.tags.length === to.tags.length &&
      from.tags.every((tag: string) => to.tags.includes(tag))) {
      return history;
    }
    return history.concat(from).slice(-12);
  }
}
