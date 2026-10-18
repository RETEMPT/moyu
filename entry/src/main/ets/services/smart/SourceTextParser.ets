import { SmartContent } from '../../common/types/SmartContent';
import { LocalTextFormatter } from './LocalTextFormatter';
import { SourceTextStructure } from '../document/SourceTextStructure';
import { ExplicitTaskExtractor } from './ExplicitTaskExtractor';

/** 只提取原文明示的标题和任务，不补写事实或猜测日期。 */
export class SourceTextParser {
  static fromSource(text: string, fallbackTitle: string = '已提取知识'): SmartContent {
    const now = Date.now();
    const normalized = LocalTextFormatter.normalize(text);
    const lines = normalized.split('\n').map((s: string) => s.trim()).filter((s: string) => s.length > 0);
    const rows = SourceTextStructure.scan(normalized);
    const first = rows.find(row => row.kind === 'text' || row.kind === 'heading');
    const label = first ? first.text.trim() : '';
    const bracket = label.match(/^[【《]([^】》]+)[】》]$/);
    const firstLine = bracket ? bracket[1] : label.replace(/^#{1,6}\s+/, '').replace(/\s+#+\s*$/, '');
    const title = firstLine.length > 0 && firstLine.length <= 60 ? firstLine : fallbackTitle;
    const tasks = ExplicitTaskExtractor.extract(rows, now);
    return { id: `smart-${now}`, type: 'general', title: title,
      summary: (lines[0] || '').slice(0, 160), tags: [], tasks: tasks, rawMarkdown: normalized,
      formattedMarkdown: /^#\s/.test(normalized) ? normalized : `# ${title}\n\n${normalized}`,
      processingMode: 'local', createdAt: now };
  }

}
