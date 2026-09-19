export interface Backlink {
  sourceNoteId: string;
  sourceTitle: string;
  targetNoteId: string;
  targetTitle: string;
  label: string;
}

export interface UnresolvedLink {
  sourceNoteId: string;
  sourceTitle: string;
  target: string;
  label: string;
}

export interface LinkGraph {
  backlinks: Backlink[];
  unresolvedLinks: UnresolvedLink[];
}
