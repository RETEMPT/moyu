import { SmartTask } from '../../common/types/SmartTask';
import { SourceTextLine } from '../document/SourceTextStructure';

/** GFM checkboxes and explicit actions only; every candidate retains its source line.
 * These rules intentionally prefer missed suggestions over invented obligations.
 */
export class ExplicitTaskExtractor {
  static extract(rows: SourceTextLine[], now: number): SmartTask[] {
    const tasks: SmartTask[] = []; const seen = new Set<string>();
    for (const row of rows) {
      if (row.kind !== 'text' && row.kind !== 'list') { continue; }
      const text = row.text.trim();
      const checkbox = text.match(/^(?:[-*+]|\d+[.)])\s+\[([ xX])\](?:\s+|$)/);
      if (checkbox && checkbox[1].toLowerCase() === 'x') { continue; }
      const explicit = checkbox !== null || /^(?:待办|行动|任务)[：:]/.test(text);
      const content = text.replace(/^(?:[-*+•▪●·]|\d+[.)、])\s+/, '')
        .replace(/^\[ \]\s*/, '').replace(/^(?:待办|行动|任务)[：:]\s*/, '');
      const clauses = content.split(/[。；;！？!?]/);
      for (let part = 0; part < clauses.length; part++) {
        const title = clauses[part].trim();
        if (!title || /(?:无需|不需要|不用|不必|取消|不要|禁止|已(?:经)?(?:完成|提交|报名|准备|整理|交付|安排|联系))/.test(title)) { continue; }
        if (!explicit && (!ExplicitTaskExtractor.action(title) ||
          /是指|指的是|表示|意味着|用于|例如|比如|示例|算法|复杂度|(?:如何|怎么|是否)/.test(title))) { continue; }
        const key = title.replace(/\s+/g, ' ');
        if (seen.has(key)) { continue; } seen.add(key);
        const dates: string[] = title.match(/\d{4}-\d{1,2}-\d{1,2}|(?:\d{4}年)?\d{1,2}月\d{1,2}日|(?:本周|下周|周)[一二三四五六日天]|今天|明天|后天/g) || [];
        const uniqueDates = dates.filter((value: string, index: number) => dates.indexOf(value) === index);
        tasks.push({ id: `task-${now}-${row.line}-${part}`, title,
          deadline: uniqueDates.join(' / '), priority: 'medium', sourceLine: row.line, sourceText: row.text });
      }
    }
    return tasks;
  }

  private static action(text: string): boolean {
    const withoutDate = text.replace(/^(?:请)?(?:于|在)?\s*(?:\d{4}-\d{1,2}-\d{1,2}|(?:\d{4}年)?\d{1,2}月\d{1,2}日|(?:本周|下周|周)[一二三四五六日天]|今天|明天|后天)(?:之前|前|内)?[，,:：\s]*/, '');
    return /^(?:请|需要|务必|记得|必须|应当|须|计划|打算|我要|我们要)?\s*(?:提交|完成|交付|整理|准备|安排|联系|报名|写一篇)\S/.test(withoutDate) &&
      !/^(?:提交|完成|准备|整理|安排|联系|报名)(?:后|时|的|度|率|状态|情况|阶段|过程|函数|操作)/.test(withoutDate);
  }
}
