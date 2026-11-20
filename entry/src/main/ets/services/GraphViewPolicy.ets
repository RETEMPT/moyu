import { Backlink, LinkGraph, UnresolvedLink } from '../common/types/LinkGraph';
import { NoteItem } from '../common/types/NoteItem';
import { WorkspaceNotePolicy } from './WorkspaceNotePolicy';

export const ALL_GRAPH_TOPICS: string = '__all_topics__';

export interface GraphNode {
  key: string;
  noteId: string;
  label: string;
  category: string;
  canLink: boolean;
  x: number;
  y: number;
  w: number;
  h: number;
  degree: number;
  isRoot: boolean;
}

export interface GraphEdge { a: number; b: number; }

export interface GraphView {
  nodes: GraphNode[];
  edges: GraphEdge[];
  backlinks: Backlink[];
  unresolvedLinks: UnresolvedLink[];
}

export interface GraphScope {
  topic: string;
  focus: string;
  depth: number;
  filter: string;
}

export class GraphViewPolicy {
  static noteKey(id: string): string { return 'note:' + id; }
  static pendingKey(title: string): string { return 'pending:' + title.trim().toLocaleLowerCase(); }
  static build(notes: NoteItem[], graph: LinkGraph, scope: GraphScope): GraphView {
    const nodes: GraphNode[] = [];
    const indices = new Map<string, number>();
    const adjacency: number[][] = [];
    const edges: GraphEdge[] = [];
    const edgeKeys = new Set<string>();
    const backlinks: Backlink[] = [];
    const unresolvedLinks: UnresolvedLink[] = [];

    const addNode = (key: string, noteId: string, label: string, category: string, canLink: boolean): number => {
      const index = nodes.length;
      indices.set(key, index);
      adjacency.push([]);
      nodes.push({
        key, noteId, label, category, canLink,
        x: 0, y: 0, w: Math.max(148, Math.min(208, label.length * 13 + 60)), h: 44, degree: 0, isRoot: false
      });
      return index;
    };
    const addEdge = (a: number, b: number): void => {
      if (a === b) { return; }
      const key = a < b ? `${a}:${b}` : `${b}:${a}`;
      if (edgeKeys.has(key)) { return; }
      edgeKeys.add(key);
      edges.push({ a, b });
      adjacency[a].push(b);
      adjacency[b].push(a);
    };

    for (const note of notes) {
      if (note.deletedAt) { continue; }
      addNode(GraphViewPolicy.noteKey(note.id), note.id, note.title, note.category?.trim() || '未分类',
        WorkspaceNotePolicy.canUpdateBody(note));
    }
    if (scope.filter !== 'unresolved') {
      for (const link of graph.backlinks) {
        const a = indices.get(GraphViewPolicy.noteKey(link.sourceNoteId));
        const b = indices.get(GraphViewPolicy.noteKey(link.targetNoteId));
        if (a === undefined || b === undefined || a === b) { continue; }
        addEdge(a, b);
        backlinks.push(link);
      }
    }
    if (scope.filter !== 'notes') {
      for (const link of graph.unresolvedLinks) {
        const a = indices.get(GraphViewPolicy.noteKey(link.sourceNoteId));
        if (a === undefined || !link.target.trim()) { continue; }
        const key = GraphViewPolicy.pendingKey(link.target);
        const b = indices.get(key) ?? addNode(key, '', link.target.trim(), '', false);
        addEdge(a, b);
        unresolvedLinks.push(link);
      }
    }

    const visible = new Set<number>();
    const focus = scope.focus ? indices.get(scope.focus) : undefined;
    if (focus !== undefined) {
      visible.add(focus);
      let frontier: number[] = [focus];
      for (let hop = 0; hop < scope.depth && frontier.length > 0; hop++) {
        const next: number[] = [];
        for (const index of frontier) {
          for (const neighbor of adjacency[index]) {
            if (visible.has(neighbor)) { continue; }
            visible.add(neighbor);
            next.push(neighbor);
          }
        }
        frontier = next;
      }
    } else {
      for (let index = 0; index < nodes.length; index++) {
        if (scope.topic !== ALL_GRAPH_TOPICS && nodes[index].category !== scope.topic) { continue; }
        if (scope.filter === 'unresolved' && adjacency[index].length === 0) { continue; }
        visible.add(index);
      }
      if (scope.topic !== ALL_GRAPH_TOPICS) {
        // Only expand the original topic members, regardless of edge iteration order.
        const members = Array.from(visible);
        for (const index of members) {
          for (const neighbor of adjacency[index]) { visible.add(neighbor); }
        }
      }
    }

    const mapping = new Map<number, number>();
    const filtered: GraphView = { nodes: [], edges: [], backlinks: [], unresolvedLinks: [] };
    for (const index of visible) {
      mapping.set(index, filtered.nodes.length);
      filtered.nodes.push(nodes[index]);
    }
    for (const edge of edges) {
      const a = mapping.get(edge.a);
      const b = mapping.get(edge.b);
      if (a === undefined || b === undefined) { continue; }
      filtered.edges.push({ a, b });
      filtered.nodes[a].degree++;
      filtered.nodes[b].degree++;
    }
    const shown = (key: string): boolean => {
      const index = indices.get(key);
      return index !== undefined && visible.has(index);
    };
    filtered.backlinks = backlinks.filter(link =>
      shown(GraphViewPolicy.noteKey(link.sourceNoteId)) && shown(GraphViewPolicy.noteKey(link.targetNoteId)));
    filtered.unresolvedLinks = unresolvedLinks.filter(link =>
      shown(GraphViewPolicy.noteKey(link.sourceNoteId)) && shown(GraphViewPolicy.pendingKey(link.target)));
    return filtered;
  }
}
