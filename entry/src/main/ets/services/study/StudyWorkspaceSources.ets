import { NoteItem } from '../../common/types/NoteItem';
import { LearningCitation, LearningResult } from '../../common/types/LearningResult';
import { ReaderPairPolicy } from '../document/ReaderPairPolicy';
import { LearningResultPolicy, LearningSourceLocation } from './LearningResultPolicy';
import { StudyAssistantFragment, StudyAssistantRequest, StudyChatMessage, StudySourceFocusTarget } from './StudyAssistantGateway';
import { StudySourceService } from './StudySourceService';

interface SourcePart {
  text: string;
  pageNumber?: number;
}

interface SourceExcerpt extends SourcePart {
  offset: number;
  line: number;
  score: number;
  focused?: boolean;
}

export interface StudySourceFocus { noteId: string; quote: string; page?: number; line?: number; }

export interface StudyWorkspaceLocation extends LearningSourceLocation {
  noteId: string;
  title: string;
  offset: number;
}

export interface StudyWorkspaceRequest {
  request: StudyAssistantRequest;
  locations: StudyWorkspaceLocation[];
}

export interface StudyWorkspaceResult {
  result: LearningResult;
  locations: StudyWorkspaceLocation[];
  tools?: string[];
}

export interface StudyChatEvidence { messageIndex: number; entry: StudyWorkspaceResult; }

export class StudyWorkspaceSources {
  static readonly MAX_NOTES: number = 12;

  static searchable(notes: NoteItem[], query: string): NoteItem[] {
    const term = query.trim().toLowerCase();
    return notes.filter((note: NoteItem) =>
      !note.deletedAt && (ReaderPairPolicy.isPdf(note) || ReaderPairPolicy.isMarkdown(note)) &&
      (!term || (note.title + ' ' + note.category).toLowerCase().includes(term)));
  }

  static hasText(note: NoteItem): boolean {
    if (ReaderPairPolicy.isPdf(note)) {
      return !!note.sourceUri && StudySourceService.pages(note).some(page => page.text.trim().length >= 4);
    }
    return ReaderPairPolicy.isMarkdown(note) && (note.contentDetail || '').trim().length >= 4;
  }

  private static parts(note: NoteItem): SourcePart[] {
    if (ReaderPairPolicy.isPdf(note) && note.sourceUri) {
      return StudySourceService.pages(note).map((page): SourcePart => ({
        text: LearningResultPolicy.normalizeSource(page.text), pageNumber: page.pageNumber
      }));
    }
    return ReaderPairPolicy.isMarkdown(note) ?
      [{ text: LearningResultPolicy.normalizeSource(note.contentDetail || '') }] : [];
  }

  private static terms(goal: string): string[] {
    const terms: string[] = goal.toLowerCase().match(/[a-z0-9]{2,}/g) || [];
    const runs: string[] = goal.match(/[\u3400-\u9fff]{2,}/g) || [];
    for (const run of runs) {
      for (let index = 0; index < run.length - 1 && terms.length < 40; index++) {
        const word = run.substring(index, index + 2);
        if (!terms.includes(word)) { terms.push(word); }
      }
    }
    return terms.slice(0, 40);
  }

  /** Keep offsets while ranking contiguous excerpts, so quotes can still open the original page or line. */
  private static excerpts(note: NoteItem, terms: string[], limit: number, focus?: StudySourceFocus): SourceExcerpt[] {
    const best: SourceExcerpt[] = [];
    for (const part of StudyWorkspaceSources.parts(note)) {
      let quoteOffset = -1;
      if (focus && part.pageNumber === focus.page) {
        const lines = part.text.split('\n', focus.line || 1);
        const start = lines.slice(0, -1).reduce((units: number, line: string) => units + line.length + 1, 0);
        const match = part.text.indexOf(focus.quote, start);
        if (match >= 0 && (!focus.line || part.text.slice(0, match).split('\n').length === focus.line)) {
          quoteOffset = match;
        }
      }
      let covered = false;
      let offset = 0;
      let line = 1;
      while (offset < part.text.length) {
        let end = Math.min(offset + 960, part.text.length);
        if (end < part.text.length) {
          const boundary = part.text.lastIndexOf('\n', end - 1);
          if (boundary >= offset + 540) { end = boundary + 1; }
          const lastUnit = part.text.charCodeAt(end - 1);
          if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF) { end--; }
        }
        const raw = part.text.slice(offset, end);
        const snippet = raw.trim();
        if (snippet.length >= 4) {
          const leading = raw.length - raw.trimStart().length;
          const lower = snippet.toLowerCase();
          const focused = !!focus && quoteOffset >= offset + leading && quoteOffset + focus.quote.length <= offset + leading + snippet.length;
          covered = covered || focused;
          const score = focused ? 100 : terms.reduce((value: number, term: string) => value + (lower.includes(term) ? 1 : 0), 0);
          if (best.length < limit || score > best[best.length - 1].score) {
            best.push({ text: snippet, pageNumber: part.pageNumber, offset: offset + leading,
              line: line + raw.slice(0, leading).split('\n').length - 1, score, focused });
            best.sort((left: SourceExcerpt, right: SourceExcerpt) => right.score - left.score);
            if (best.length > limit) { best.pop(); }
          }
        }
        line += raw.split('\n').length - 1;
        offset = end;
      }
      if (focus && quoteOffset >= 0 && !covered) {
        best.unshift({ text: focus.quote, pageNumber: part.pageNumber, offset: quoteOffset,
          line: part.text.slice(0, quoteOffset).split('\n').length, score: 100, focused: true });
        if (best.length > limit) { best.pop(); }
      }
    }
    return best;
  }

  static prepare(notes: NoteItem[], selected: string[], goal: string, operation: string,
    focus?: StudySourceFocus): StudyWorkspaceRequest {
    if (selected.length < 1 || selected.length > StudyWorkspaceSources.MAX_NOTES) {
      throw new Error('请选择 1–12 份资料');
    }
    const cleanGoal = goal.trim();
    if (!cleanGoal || cleanGoal.length > 800) { throw new Error('基于资料的问题最多 800 字'); }
    const sources: StudyAssistantFragment[] = [];
    const locations: StudyWorkspaceLocation[] = [];
    let target: StudySourceFocusTarget | undefined = undefined;
    const terms = operation === 'qa' ? StudyWorkspaceSources.terms(cleanGoal) : [];
    const perNote = Math.floor(StudyWorkspaceSources.MAX_NOTES / selected.length);
    for (const noteId of selected) {
      const note = notes.find((item: NoteItem) => item.id === noteId);
      if (!note || note.deletedAt || !StudyWorkspaceSources.hasText(note)) { throw new Error('资料已移除或缺少正文，请重新选择'); }
      for (const excerpt of StudyWorkspaceSources.excerpts(note, terms, perNote, focus?.noteId === noteId ? focus : undefined)) {
        const id = 's' + (sources.length + 1);
        if (excerpt.focused && focus) { target = { source_id: id, quote: focus.quote }; }
        sources.push({ id, text: excerpt.text });
        locations.push({ sourceId: id, noteId, title: note.title, offset: excerpt.offset,
          pageNumber: excerpt.pageNumber, line: excerpt.line });
      }
    }
    if (!sources.length) { throw new Error('所选资料没有可发送的正文'); }
    const request: StudyAssistantRequest = { operation, goal: cleanGoal, sources };
    if (target) { request.focus = target; }
    return { request, locations };
  }

  /** Reuse grounded turns only when their exact source ranges are in the current preview. */
  static dialogue(messages: StudyChatMessage[], evidence: StudyChatEvidence[], plan?: StudyWorkspaceRequest): StudyChatMessage[] {
    return messages.filter((_message: StudyChatMessage, index: number) => {
      const answerIndex = index % 2 === 0 ? index + 1 : index;
      const saved = evidence.find((item: StudyChatEvidence) => item.messageIndex === answerIndex);
      if (!saved) { return true; }
      if (!plan || !saved.entry.result.sources.length) { return false; }
      return saved.entry.result.sources.every(fragment => {
        const previous = saved.entry.locations.find(item => item.sourceId === fragment.id);
        return plan.locations.some((location: StudyWorkspaceLocation, sourceIndex: number) => previous &&
          location.noteId === previous.noteId && location.pageNumber === previous.pageNumber &&
          location.offset === previous.offset && plan.request.sources[sourceIndex].text === fragment.text);
      });
    });
  }

  static location(entry: StudyWorkspaceResult, citation: LearningCitation, note: NoteItem): LearningSourceLocation | undefined {
    const saved = entry.locations.find((item: StudyWorkspaceLocation) => item.sourceId === citation.source_id && item.noteId === note.id);
    const fragment = entry.result.sources.find(item => item.id === citation.source_id);
    if (!saved || !fragment) { return undefined; }
    const part = StudyWorkspaceSources.parts(note).find((item: SourcePart) => item.pageNumber === saved.pageNumber);
    if (part && part.text.slice(saved.offset, saved.offset + fragment.text.length) === fragment.text) {
      return { sourceId: saved.sourceId, pageNumber: saved.pageNumber,
        line: part.text.slice(0, saved.offset).split('\n').length };
    }
    return LearningResultPolicy.locate(entry.result, note).find(item => item.sourceId === saved.sourceId);
  }

  static markdown(entry: StudyWorkspaceResult): string {
    const parts = [ '# ' + entry.result.title.replace(/\r?\n/g, ' ') ];
    for (const section of entry.result.sections) {
      parts.push('## ' + section.heading.replace(/\r?\n/g, ' ') + '\n\n' + section.body);
      for (const citation of section.citations) {
        const source = entry.locations.find((item: StudyWorkspaceLocation) => item.sourceId === citation.source_id);
        const label = source ? source.title + ' · ' + StudyWorkspaceSources.position(entry, citation, source) : citation.source_id;
        parts.push('> ' + label + '\n> ' + citation.quote.replace(/\r?\n/g, '\n> '));
      }
    }
    return parts.join('\n\n');
  }

  static position(entry: StudyWorkspaceResult, citation: LearningCitation, location: LearningSourceLocation): string {
    return location.pageNumber !== undefined ? `第 ${location.pageNumber} 页` :
      `第 ${LearningResultPolicy.citationLine(entry.result, citation, location)} 行`;
  }
}
