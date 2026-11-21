/**
 * 原文提取并转化的待办行动 (SmartTask)
 */
export interface SmartTask {
  id: string;
  title: string;
  deadline?: string;
  priority: 'high' | 'medium' | 'low';
  sourceTitle?: string;
  sourceUri?: string;
  /** 1-based line in rawMarkdown; optional for drafts from older versions. */
  sourceLine?: number;
  sourceText?: string;
  reminderTime?: string;
  completed?: boolean;
}
