import { SmartContent, SmartContentType } from '../../common/types/SmartContent';
import { SmartEntity, SmartEntityType } from '../../common/types/SmartEntity';
import { SmartTask } from '../../common/types/SmartTask';
import { SmartRelation } from '../../common/types/SmartRelation';

/** 模型输出经过字段校验；离线处理只摘录原文，不生成示例事实。 */
export class AiParser {
  static parseSmartContent(text: string, fallbackTitle: string = '已提取知识'): SmartContent {
    try {
      return AiParser.parseModelContent(text, fallbackTitle);
    } catch {
      return AiParser.fromSource(text, fallbackTitle);
    }
  }

  static parseModelContent(text: string, fallbackTitle: string = '已提取知识'): SmartContent {
    const trimmed = text.trim();
    const fence = trimmed.match(/^```(?:json)?\s*([\s\S]*)\s*```$/i);
    const candidate = fence ? fence[1] : trimmed.substring(trimmed.indexOf('{'), trimmed.lastIndexOf('}') + 1);
    const obj = JSON.parse(candidate) as Record<string, Object>;
    if (obj === null || typeof obj !== 'object' || Array.isArray(obj) ||
      (AiParser.stringOf(obj['title']).length === 0 && AiParser.stringOf(obj['formattedMarkdown']).length === 0)) {
      throw new Error('模型未返回有效的排版结果');
    }
    const now = Date.now();
    const allowedTypes: string[] = ['exam_notice', 'paper_summary', 'course_notes', 'task_memo', 'concept_card', 'general'];
    const typeText = AiParser.stringOf(obj['type']);
    const tasks: SmartTask[] = [];
    for (const row of AiParser.rowsOf(obj['tasks'])) {
      const title = AiParser.stringOf(row['title']);
      if (title.length === 0 || tasks.some((t: SmartTask) => t.title === title)) {
        continue;
      }
      const priority = AiParser.stringOf(row['priority']);
      tasks.push({ id: `task-${now}-${tasks.length}`, title: title,
        deadline: AiParser.stringOf(row['deadline']),
        priority: priority === 'high' ? 'high' : (priority === 'low' ? 'low' : 'medium') });
    }
    const entities: SmartEntity[] = [];
    const entityTypes: string[] = ['person', 'location', 'time', 'course', 'concept', 'document', 'other'];
    for (const row of AiParser.rowsOf(obj['entities'])) {
      const name = AiParser.stringOf(row['name']);
      const entityType = AiParser.stringOf(row['type']);
      if (name.length > 0) {
        entities.push({ id: `entity-${now}-${entities.length}`, name: name,
          type: entityTypes.includes(entityType) ? entityType as SmartEntityType : 'other',
          description: AiParser.stringOf(row['description']) });
      }
    }
    const relations: SmartRelation[] = [];
    for (const row of AiParser.rowsOf(obj['relations'])) {
      const target = AiParser.stringOf(row['targetTitle']).replace(/[\[\]\r\n]/g, '').trim();
      if (target.length > 0 && !relations.some((r: SmartRelation) => r.targetTitle === target)) {
        relations.push({ id: `relation-${now}-${relations.length}`,
          sourceTitle: AiParser.stringOf(row['sourceTitle']), targetTitle: target,
          relationType: 'related', reason: AiParser.stringOf(row['reason']) });
      }
    }
    return {
      id: `smart-${now}`, type: allowedTypes.includes(typeText) ? typeText as SmartContentType : 'general',
      title: AiParser.stringOf(obj['title']) || fallbackTitle,
      summary: AiParser.stringOf(obj['summary']), tags: AiParser.stringsOf(obj['tags']),
      keyPoints: AiParser.stringsOf(obj['keyPoints']), entities: entities, tasks: tasks, relations: relations,
      formattedMarkdown: AiParser.stringOf(obj['formattedMarkdown']), createdAt: now, processingMode: 'ai'
    };
  }

  static fromSource(text: string, fallbackTitle: string = '已提取知识'): SmartContent {
    const now = Date.now();
    const normalized = text.replace(/\r\n?/g, '\n').trim();
    const lines = normalized.split('\n').map((s: string) => s.trim()).filter((s: string) => s.length > 0);
    const bracket = (lines[0] || '').match(/^[【《]([^】》]+)[】》]$/);
    const firstLine = bracket ? bracket[1] : (lines[0] || '').replace(/^#+\s*/, '');
    const title = firstLine.length > 0 && firstLine.length <= 60 ? firstLine : fallbackTitle;
    const tasks: SmartTask[] = [];
    const sentences = normalized.split(/[\n。；;，,]/).map((s: string) => s.trim());
    for (const sentence of sentences) {
      if (!/(提交|完成|交付|整理|准备|安排|联系|报名|写一篇)/.test(sentence) ||
        /(已完成|已经完成|已提交|已经提交|无需|不需要|不用|取消)/.test(sentence)) {
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

  private static stringOf(value: Object): string {
    return typeof value === 'string' ? value.trim() : '';
  }

  private static stringsOf(value: Object): string[] {
    const result: string[] = [];
    if (Array.isArray(value)) {
      for (const item of value as Object[]) {
        const text = AiParser.stringOf(item);
        if (text.length > 0 && !result.includes(text)) {
          result.push(text);
        }
      }
    }
    return result;
  }

  private static rowsOf(value: Object): Record<string, Object>[] {
    const result: Record<string, Object>[] = [];
    if (Array.isArray(value)) {
      for (const item of value as Object[]) {
        if (item !== null && typeof item === 'object' && !Array.isArray(item)) {
          result.push(item as Record<string, Object>);
        }
      }
    }
    return result;
  }
}
