import { SMART_INPUT_LIMIT } from '../../common/constants/ContentLimits';

interface MarkerMarkdownResponse { success?: boolean; format?: string; output?: string; markdown?: string; error?: string; }

/** Interoperates with Marker CLI Markdown and the official server's Markdown JSON response. */
export class MarkerImportPolicy {
  static parse(raw: string, json: boolean): string {
    if (raw.length > 1024 * 1024) { throw new Error('结果文件过大，请在 Marker 中分段导出'); }
    let text = raw.replace(/^\uFEFF/, '');
    if (json) {
      const value = JSON.parse(text) as MarkerMarkdownResponse;
      if (!value || typeof value !== 'object' || Array.isArray(value) || (value.success !== undefined && value.success !== true)) {
        throw new Error('Marker 未返回成功结果，请检查转换后重新导出');
      }
      if (value.format && value.format !== 'markdown') { throw new Error('请使用 Marker 的 markdown 输出格式；结构 JSON 不会当成正文导入'); }
      text = typeof value.output === 'string' ? value.output : typeof value.markdown === 'string' ? value.markdown : '';
    }
    if (!text.trim()) { throw new Error('没有可导入的文字，请选择 Marker Markdown 或其成功响应 JSON'); }
    if (text.length > SMART_INPUT_LIMIT) { throw new Error(`文字超过 ${SMART_INPUT_LIMIT} 字，请分段导出，原输入已保留`); }
    return text.replace(/\r\n?/g, '\n');
  }
}
