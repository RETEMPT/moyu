import { SmartContent } from '../../common/types/SmartContent';
import { SmartTask } from '../../common/types/SmartTask';
import { LocalTextFormatter, LocalTextLine } from '../smart/LocalTextFormatter';

/** 只提取原文明示的标题和任务，不补写事实或猜测日期。 */
export class SourceTextParser {
  static fromSource(text: string, fallbackTitle: string = '已提取知识'): SmartContent {
    const now = Date.now();
    const normalized = LocalTextFormatter.normalize(text);
    const lines = normalized.split('\n').map((s: string) => s.trim()).filter((s: string) => s.length > 0);
    const bracket = (lines[0] || '').match(/^[【《]([^】》]+)[】》]$/);
    const firstLine = bracket ? bracket[1] : (lines[0] || '').replace(/^#+\s*/, '');
    const title = firstLine.length > 0 && firstLine.length <= 60 ? firstLine : fallbackTitle;
    const tasks: SmartTask[] = [];
    const sentences = LocalTextFormatter.lines(normalized).filter((line: LocalTextLine) => !line.protected)
      .map((line: LocalTextLine) => line.text).filter((line: string) => !/^\s*[-*+]\s*\[[xX]\]/.test(line))
      .join('\n').split(/[\n。；;]/).map((s: string) => s.trim());
    for (const sentence of sentences) {
      if (!/(提交|完成|交付|整理|准备|安排|联系|报名|写一篇)/.test(sentence) ||
        /(已完成|已经完成|已提交|已经提交|已报名|已经报名|无需|不需要|不用|不必|取消|不要|禁止)/.test(sentence)) {
        continue;
      }
      const deadline = sentence.match(/\d{4}-\d{1,2}-\d{1,2}|(?:\d{4}年)?\d{1,2}月\d{1,2}日|(?:本周|下周|周)[一二三四五六日天]|今天|明天|后天/);
      const taskTitle = sentence.replace(/^(?:[-*]\s*\[\s*\]\s*|待办[：:]|行动[：:])\s*/, '');
      if (!tasks.some((t: SmartTask) => t.title === taskTitle)) {
        tasks.push({ id: `task-${now}-${tasks.length}`, title: taskTitle,
          deadline: deadline ? deadline[0] : '', priority: 'medium' });
      }
    }
    return { id: `smart-${now}`, type: 'general', title: title,
      summary: (lines[0] || '').slice(0, 160), tags: [], entities: [], tasks: tasks, relations: [],
      keyPoints: [], rawMarkdown: normalized,
      formattedMarkdown: /^#\s/.test(normalized) ? normalized : `# ${title}\n\n${normalized}`,
      processingMode: 'local', createdAt: now };
  }

}
