/**
 * AI 结构化解析核心成果 (SmartContent)
 *
 * 用户输入图片、PDF、文档或碎片文字后，
 * AI 统一输出此结构化数据，闭环转为：知识卡、待办行动、关联图谱。
 */
import { SmartEntity } from './SmartEntity';
import { SmartTask } from './SmartTask';
import { SmartRelation } from './SmartRelation';

export type SmartContentType = 'exam_notice' | 'paper_summary' | 'course_notes' | 'task_memo' | 'concept_card' | 'general';

export interface SmartContent {
  id: string;
  sourceId?: string;
  sourceTitle?: string;
  type: SmartContentType;
  title: string;
  summary: string;
  tags: string[];
  entities: SmartEntity[];
  tasks: SmartTask[];
  relations: SmartRelation[];
  keyPoints?: string[];
  rawMarkdown?: string;
  createdAt: number;
}
