/**
 * AI 提取并转化的待办行动 (SmartTask)
 */
export interface SmartTask {
  id: string;
  title: string;
  deadline?: string;
  priority: 'high' | 'medium' | 'low';
  sourceTitle?: string;
  sourceUri?: string;
  reminderTime?: string;
  completed?: boolean;
}
