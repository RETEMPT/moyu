export interface Chunk {
  id: string;
  noteId: string;
  noteTitle: string;
  headingPath: string;
  text: string;
  startLine: number;
  tokenEstimate: number;
}

export interface Citation {
  noteId: string;
  noteTitle: string;
  headingPath: string;
  chunkText: string;
  score: number;
  startLine?: number;
}

export interface RetrievalHit {
  chunk: Chunk;
  score: number;
  source: 'keyword' | 'tag' | 'link' | 'vector';
}
