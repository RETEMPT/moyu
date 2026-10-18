import { SMART_INPUT_LIMIT } from '../../common/constants/ContentLimits';

/** Plain text only. Format-specific service responses are outside the current product scope. */
export class TextImportPolicy {
  static parse(raw: string): string {
    if (raw.length > 1024 * 1024) { throw new Error('文字文件过大，请分段导出'); }
    const text = raw.replace(/^\uFEFF/, '').replace(/\r\n?/g, '\n');
    if (!text.trim()) { throw new Error('没有可导入的文字，请选择非空的 Markdown 或 TXT 文件'); }
    if (text.length > SMART_INPUT_LIMIT) { throw new Error(`文字超过 ${SMART_INPUT_LIMIT} 字，请分段导出，原输入已保留`); }
    return text;
  }
}
