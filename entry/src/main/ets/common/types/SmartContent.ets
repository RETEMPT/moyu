/**
 * 本地规则整理结果 (SmartContent)
 *
 * 用户输入图片、PDF、文档或碎片文字后，
 * 保留原文与排版正文，供用户核对后保存笔记和明确待办。
 */
import { SmartTask } from './SmartTask';

export type SmartContentType = 'general';

export interface SmartContent {
  id: string;
  sourceId?: string;
  sourceTitle?: string;
  type: SmartContentType;
  title: string;
  summary: string;
  tags: string[];
  tasks: SmartTask[];
  rawMarkdown?: string;
  /** 排版正文与原文分开保留。 */
  formattedMarkdown?: string;
  processingMode?: 'local';
  processingNotice?: string;
  category?: string;
  createdAt: number;
}
