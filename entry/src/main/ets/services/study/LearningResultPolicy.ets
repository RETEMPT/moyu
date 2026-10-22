import { LearningResult, LearningSource, LearningCitation } from '../../common/types/LearningResult';
import { ReviewDraft } from '../../common/types/StudyTypes';

/** Dormant preparation layer: no UI, network, storage, application IDs or automatic adoption. */
export class LearningResultPolicy {
  static readonly MAX_BYTES: number = 131072;

  private static keys(value: Object, expected: string): void {
    if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).sort().join(' ') !== expected.split(' ').sort().join(' ')) {
      throw new Error('学习结果字段不符合约定');
    }
  }

  private static utf8Bytes(value: string): number {
    let size = 0;
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (code >= 0xD800 && code <= 0xDBFF) {
        const next = value.charCodeAt(++index);
        if (!(next >= 0xDC00 && next <= 0xDFFF)) { throw new Error('学习结果含无效 Unicode'); }
        size += 4;
      } else if (code >= 0xDC00 && code <= 0xDFFF) { throw new Error('学习结果含无效 Unicode'); }
      else { size += code < 0x80 ? 1 : code < 0x800 ? 2 : 3; }
    }
    return size;
  }

  private static text(value: string, maximum: number, minimum: number = 1): void {
    if (typeof value !== 'string' || value.length < minimum || value.length > maximum || !value.trim()) {
      throw new Error('学习结果文字长度或类型无效');
    }
    LearningResultPolicy.utf8Bytes(value);
  }

  private static count<T>(value: T[], minimum: number, maximum: number): void {
    if (!Array.isArray(value) || value.length < minimum || value.length > maximum) {
      throw new Error('学习结果列表长度无效');
    }
  }

  private static integer(value: number): void {
    if (!Number.isInteger(value) || value < 1 || value > 2147483647) { throw new Error('学习结果版本或行号无效'); }
  }

  private static citations(values: LearningCitation[], sources: LearningSource[]): void {
    LearningResultPolicy.count(values, 1, 6);
    for (const citation of values) {
      LearningResultPolicy.keys(citation, 'source_id quote');
      LearningResultPolicy.text(citation.source_id, 100);
      LearningResultPolicy.text(citation.quote, 480, 4);
      const source = sources.find((item: LearningSource) => item.id === citation.source_id);
      if (!source || !source.text.includes(citation.quote)) { throw new Error('引用缺失或不在资料片段内'); }
    }
  }

  static parse(raw: string): LearningResult {
    if (typeof raw !== 'string' || raw.length > LearningResultPolicy.MAX_BYTES ||
      LearningResultPolicy.utf8Bytes(raw) > LearningResultPolicy.MAX_BYTES) { throw new Error('学习结果超过 128 KiB'); }
    const value = JSON.parse(raw) as LearningResult;
    LearningResultPolicy.keys(value, 'format version job_id operation title sources sections cards warnings');
    if (value.format !== 'moyu.learning-result' || value.version !== 1) { throw new Error('不支持的学习结果格式或版本'); }
    if (!['summary', 'qa', 'quiz', 'report', 'plan'].includes(value.operation)) { throw new Error('不支持的学习任务'); }
    LearningResultPolicy.text(value.job_id, 80);
    if (/[^A-Za-z0-9_-]/.test(value.job_id)) { throw new Error('任务标识无效'); }
    LearningResultPolicy.text(value.title, 200);
    LearningResultPolicy.count(value.sources, 1, 12);
    const ids: Set<string> = new Set();
    for (const source of value.sources) {
      LearningResultPolicy.keys(source, 'id name text revision digest line_start line_end');
      LearningResultPolicy.text(source.id, 100);
      if (/[^A-Za-z0-9_-]/.test(source.id) || ids.has(source.id)) { throw new Error('资料标识无效或重复'); }
      ids.add(source.id);
      LearningResultPolicy.text(source.name, 480);
      LearningResultPolicy.text(source.text, 2400);
      if (typeof source.digest !== 'string' || source.digest.length !== 64 || /[^a-f0-9]/.test(source.digest)) {
        throw new Error('资料摘要格式无效');
      }
      LearningResultPolicy.integer(source.revision);
      LearningResultPolicy.integer(source.line_start);
      LearningResultPolicy.integer(source.line_end);
      if (source.line_end < source.line_start) { throw new Error('资料行号范围无效'); }
    }
    LearningResultPolicy.count(value.sections, 1, 8);
    for (const section of value.sections) {
      LearningResultPolicy.keys(section, 'heading body citations');
      LearningResultPolicy.text(section.heading, 300);
      LearningResultPolicy.text(section.body, 4000);
      LearningResultPolicy.citations(section.citations, value.sources);
    }
    LearningResultPolicy.count(value.cards, 0, 8);
    if ((value.operation === 'quiz') !== (value.cards.length > 0)) { throw new Error('题卡与任务类型不一致'); }
    for (const card of value.cards) {
      LearningResultPolicy.keys(card, 'question answer citations');
      LearningResultPolicy.text(card.question, 300);
      LearningResultPolicy.text(card.answer, 4000);
      LearningResultPolicy.citations(card.citations, value.sources);
    }
    LearningResultPolicy.count(value.warnings, 0, 16);
    for (const warning of value.warnings) { LearningResultPolicy.text(warning, 1000); }
    return value;
  }

  /** Caller must explicitly select the live local fragment; never infer a local note or PDF page. */
  static cardDraft(raw: string, index: number, sourceId: string, selectedText: string): ReviewDraft {
    const value = LearningResultPolicy.parse(raw);
    if (!Number.isInteger(index) || index < 0 || index >= value.cards.length) { throw new Error('题卡索引无效'); }
    const source = value.sources.find((item: LearningSource) => item.id === sourceId);
    if (!source || source.text !== selectedText) { throw new Error('所选本地片段与结果来源不一致，请重新核对'); }
    const card = value.cards[index];
    if (card.citations.some((citation: LearningCitation) => citation.source_id !== sourceId)) {
      throw new Error('跨资料题卡需要分别核对来源，不能自动归属到单份资料');
    }
    return { question: card.question, answer: card.answer,
      sourceText: card.citations.map((citation: LearningCitation) => citation.quote).join('\n\n') };
  }
}
