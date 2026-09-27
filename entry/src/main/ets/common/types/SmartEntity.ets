/**
 * AI 提取的实体（人 / 地点 / 时间 / 课程 / 文档 / 概念）
 */
export type SmartEntityType = 'person' | 'location' | 'time' | 'course' | 'concept' | 'document' | 'other';

export interface SmartEntity {
  id: string;
  name: string;
  type: SmartEntityType;
  description?: string;
  confidence?: number;
}
