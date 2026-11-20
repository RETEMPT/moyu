import { LearningResult } from '../../common/types/LearningResult';
import { NoteItem } from '../../common/types/NoteItem';
import { ReaderPairPolicy } from '../document/ReaderPairPolicy';
import { LearningResultPolicy, LearningSourceLocation } from './LearningResultPolicy';
import { StudyAssistantFragment, StudyAssistantRequest } from './StudyAssistantGateway';
import { StudySourceService } from './StudySourceService';

interface StudySourceRange { text: string; line: number; pageNumber?: number; }
export interface StudyAssistantSelection {
  request: StudyAssistantRequest;
  locations: LearningSourceLocation[];
}

export class StudyAssistantSource {
  static prepare(note: NoteItem, operation: string, goal: string, start: string, end: string): StudyAssistantSelection {
    const pdf = ReaderPairPolicy.isPdf(note);
    const from = Number(start);
    const to = end.trim() ? Number(end) : from;
    if (!Number.isInteger(from) || !Number.isInteger(to) || from < 1 || to < from) {
      throw new Error(pdf ? '请输入有效的起止页码。' : '请输入有效的起止行号。');
    }
    const texts: StudySourceRange[] = [];
    if (pdf) {
      if (!note.sourceUri || to > (note.pageCount || 0) || to - from >= 12) {
        throw new Error('请选择原文件中有效的页码，每次最多 12 页。');
      }
      const pages = StudySourceService.pages(note);
      for (let page = from; page <= to; page++) {
        const indexed = pages.find(item => item.pageNumber === page);
        if (!indexed?.text.trim()) { throw new Error(`第 ${page} 页缺少校对文字，请先提取并保存。`); }
        texts.push({ text: indexed.text, line: 1, pageNumber: page });
      }
    } else {
      const lines = LearningResultPolicy.normalizeSource(note.contentDetail).split('\n');
      const last = end.trim() ? to : lines.length;
      if (!ReaderPairPolicy.isMarkdown(note) || from > last || last > lines.length) {
        throw new Error('当前资料或行号范围不可用。');
      }
      texts.push({ text: lines.slice(from - 1, last).join('\n'), line: from });
    }
    const sources: StudyAssistantFragment[] = [];
    const locations: LearningSourceLocation[] = [];
    let total = 0;
    for (const entry of texts) {
      const normalized = LearningResultPolicy.normalizeSource(entry.text);
      const text = normalized.trim();
      total += text.length;
      if (total > 12000) { throw new Error('所选文字超过 12000 个字符单元，请缩小范围。'); }
      let offset = 0;
      while (offset < text.length) {
        let next = Math.min(offset + 1200, text.length);
        if (next < text.length) {
          const unit = text.charCodeAt(next - 1);
          if (unit >= 0xD800 && unit <= 0xDBFF) { next--; }
        }
        const slice = text.slice(offset, next);
        const fragment = slice.trim();
        if (fragment.length >= 4) {
          const id = `s${sources.length + 1}`;
          const leading = normalized.length - normalized.trimStart().length + offset + slice.length - slice.trimStart().length;
          sources.push({ id, text: fragment });
          locations.push({ sourceId: id, line: entry.line + normalized.slice(0, leading).split('\n').length - 1,
            pageNumber: entry.pageNumber });
        }
        offset = next;
      }
    }
    if (sources.length < 1 || sources.length > 12) { throw new Error('请选择可用的原文，每次最多 12 个片段。'); }
    const cleanGoal = goal.trim();
    if (!cleanGoal || cleanGoal.length > 800) { throw new Error('请填写有效的学习目标，最多 800 个字符单元。'); }
    return { request: { operation, goal: cleanGoal, sources }, locations };
  }

  static locationLabel(location: LearningSourceLocation): string {
    return location.pageNumber === undefined ? `原文第 ${location.line} 行` : `PDF 第 ${location.pageNumber} 页`;
  }

  static markdown(result: LearningResult, sourceTitle: string, locations: LearningSourceLocation[]): string {
    let body = '# ' + StudyAssistantSource.plain(result.title).replace(/\n/g, ' ') + '\n\n';
    body += '资料 · ' + StudyAssistantSource.plain(sourceTitle).replace(/\n/g, ' ') + '\n\n';
    for (const warning of result.warnings) {
      body += '> ' + StudyAssistantSource.plain(warning).replace(/\n/g, '\n> ') + '\n\n';
    }
    for (const section of result.sections) {
      body += '## ' + StudyAssistantSource.plain(section.heading).replace(/\n/g, ' ') + '\n\n';
      body += StudyAssistantSource.plain(section.body) + '\n\n';
      for (const citation of section.citations) {
        const location = locations.find(item => item.sourceId === citation.source_id);
        if (location) {
          const line = LearningResultPolicy.citationLine(result, citation, location);
          body += '> ' + StudyAssistantSource.locationLabel({ sourceId: location.sourceId, pageNumber: location.pageNumber, line }) + '\n>\n';
        }
        body += '> ' + StudyAssistantSource.plain(citation.quote).replace(/\n/g, '\n> ') + '\n\n';
      }
    }
    return body;
  }

  private static plain(value: string): string {
    return value.replace(/[\\`*_{}\[\]()<>#!|~]/g, (match: string): string => '\\' + match);
  }
}
