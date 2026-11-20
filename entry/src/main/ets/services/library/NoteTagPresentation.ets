import { SourceTextStructure } from '../document/SourceTextStructure';

/** Presentation only. Keep raw Markdown and original line coordinates for editing and citations. */
export class NoteTagPresentation {
  static displayBody(source: string, tags: string[]): string {
    if (!tags.length || !source.includes('#')) { return source; }
    const known = NoteTagPresentation.keys(tags);
    const rows = SourceTextStructure.scan(source);
    let changed = false;
    for (let index = rows.length - 1; index >= 0; index--) {
      const row = rows[index];
      if (row.kind === 'blank') { continue; }
      if (row.kind !== 'text') { break; }
      const text = NoteTagPresentation.stripSuffix(row.text, known);
      if (text === row.text) { break; }
      row.text = text;
      changed = true;
      if (text.trim()) { break; }
    }
    return changed ? rows.map(row => row.text).join('\n') : source;
  }

  static displayTitle(title: string, tags: string[]): string {
    return NoteTagPresentation.stripSuffix(title, NoteTagPresentation.keys(tags));
  }

  private static keys(tags: string[]): Set<string> {
    return new Set(tags.map(tag => tag.trim().replace(/^#/, '').toLocaleLowerCase()));
  }

  private static stripSuffix(line: string, tags: Set<string>): string {
    const pattern = /(?:^|[ \t]+)#([^\s#.,!?;:()[\]{}，。！？；：（）【】《》、*\x60]+)[ \t]*$/;
    let value = line;
    let match = pattern.exec(value);
    while (match && tags.has(match[1].toLocaleLowerCase())) {
      value = value.slice(0, match.index).trimEnd();
      match = pattern.exec(value);
    }
    return value;
  }
}
