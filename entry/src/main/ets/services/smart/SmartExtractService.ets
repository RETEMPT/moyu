import { SmartContent } from '../../common/types/SmartContent';
import { SourceTextParser } from './SourceTextParser';
import { LocalTextFormatter } from './LocalTextFormatter';
import { SMART_INPUT_LIMIT } from '../../common/constants/ContentLimits';
export type SmartLayoutStyle = 'faithful' | 'study';
export { SMART_INPUT_LIMIT };
/** Source-preserving local formatting and explicit task extraction. */
export class SmartExtractService {
  private static instance: SmartExtractService = new SmartExtractService();
  static getInstance(): SmartExtractService { return SmartExtractService.instance; }
  async extract(rawInput: string, fallbackTitle: string = '整理笔记',
    style: SmartLayoutStyle = 'faithful', mergeWrappedLines: boolean = false): Promise<SmartContent> {
    const raw = LocalTextFormatter.normalize(rawInput);
    if (!raw.trim()) { throw new Error('输入内容不能为空'); }
    if (raw.length > SMART_INPUT_LIMIT) { throw new Error(`内容超过 ${SMART_INPUT_LIMIT} 字，请分段整理`); }
    const result = SourceTextParser.fromSource(raw, fallbackTitle);
    result.formattedMarkdown = LocalTextFormatter.format(raw, result.title, style, mergeWrappedLines);
    result.processingNotice = `本地整理：${style === 'study' ? '按明确标题和项目符号整理层级' : '保留原文顺序和段落'}。${mergeWrappedLines ? '已合并部分正文断行，请对照原文核对。' : ''}待办建议 ${result.tasks.length} 项，可对照原文位置逐项选择。`;
    return result;
  }
}
