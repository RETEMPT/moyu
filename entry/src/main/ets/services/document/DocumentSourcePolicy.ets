import { ImageDocumentPolicy } from './ImageDocumentPolicy';

export type DocumentSourceKind = 'pdf' | 'image';

/** The source fields shared by library notes and recycle-bin entries. */
export interface DocumentSourceNote {
  sourceUri?: string;
  sourceFileName?: string;
  sourceType?: string;
  type?: string;
}

export interface DocumentSourceLocation {
  path: string;
  fileName: string;
  kind: DocumentSourceKind;
}

/**
 * Pure rules for repairing stored PDF/image originals after a sandbox path change.
 *
 * A filename is only a hint for an exact path inside the current managed
 * `documents` directory. The policy never lists the directory, never compares
 * titles or page counts, and never guesses another file when the stored
 * reference is missing.
 */
export class DocumentSourcePolicy {
  static readonly LEGACY_DOCUMENTS_MARKER: string = '/files/documents/';

  /** Missing sourceType/type is normal legacy data, not a reason to crash or guess a kind. */
  static kind(note: DocumentSourceNote): DocumentSourceKind | null {
    const sourceType: string = DocumentSourcePolicy.token(note.sourceType);
    if (sourceType === 'pdf') { return 'pdf'; }
    if (sourceType === 'image') { return 'image'; }
    const type: string = DocumentSourcePolicy.token(note.type);
    if (type === 'pdf') { return 'pdf'; }
    if (type === 'image') { return 'image'; }
    return null;
  }

  /** Stored paths are used verbatim; only validation throws them away. */
  static sourceValue(value: string | undefined): string {
    return typeof value === 'string' ? value : '';
  }

  static isSafeFileName(name: string): boolean {
    return name.length > 0 && name !== '.' && name !== '..' &&
      !/[\\/\u0000-\u001f]/.test(name);
  }

  static matchesKind(name: string, kind: DocumentSourceKind): boolean {
    return kind === 'pdf' ? /\.pdf$/i.test(name) : ImageDocumentPolicy.extension(name).length > 0;
  }

  static isManagedPath(filesDir: string, sourceUri: string): boolean {
    return sourceUri.startsWith(`${filesDir}/documents/`);
  }

  static managedFileName(filesDir: string, sourceUri: string): string {
    const prefix: string = `${filesDir}/documents/`;
    return sourceUri.startsWith(prefix) ? sourceUri.substring(prefix.length) : '';
  }

  /** Recover just the basename of an old absolute sandbox path; the caller still stats that exact name. */
  static legacyFileName(sourceUri: string): string {
    if (!sourceUri.startsWith('/')) { return ''; }
    const marker: string = DocumentSourcePolicy.LEGACY_DOCUMENTS_MARKER;
    const index: number = sourceUri.lastIndexOf(marker);
    if (index < 0) { return ''; }
    return sourceUri.substring(index + marker.length).split('?')[0].split('#')[0];
  }

  /**
   * Exact candidates in priority order:
   *   1. a sourceUri already inside this sandbox's documents directory;
   *   2. the persisted local copy filename;
   *   3. the basename of an old documents path.
   * The caller must verify existence/readability; this method never assumes a candidate is present.
   */
  static localCandidates(filesDir: string, note: DocumentSourceNote,
    kind: DocumentSourceKind): DocumentSourceLocation[] {
    const candidates: DocumentSourceLocation[] = [];
    const sourceUri: string = DocumentSourcePolicy.sourceValue(note.sourceUri);
    DocumentSourcePolicy.addCandidate(candidates, filesDir,
      DocumentSourcePolicy.managedFileName(filesDir, sourceUri), kind);
    DocumentSourcePolicy.addCandidate(candidates, filesDir,
      DocumentSourcePolicy.sourceValue(note.sourceFileName), kind);
    DocumentSourcePolicy.addCandidate(candidates, filesDir,
      DocumentSourcePolicy.legacyFileName(sourceUri), kind);
    return candidates;
  }

  private static token(value: string | undefined): string {
    return typeof value === 'string' ? value.trim().toLowerCase() : '';
  }

  private static addCandidate(candidates: DocumentSourceLocation[], filesDir: string,
    name: string, kind: DocumentSourceKind): void {
    if (!DocumentSourcePolicy.isSafeFileName(name) || !DocumentSourcePolicy.matchesKind(name, kind)) { return; }
    const path: string = `${filesDir}/documents/${name}`;
    for (const candidate of candidates) {
      if (candidate.path === path) { return; }
    }
    candidates.push({ path: path, fileName: name, kind: kind });
  }
}
