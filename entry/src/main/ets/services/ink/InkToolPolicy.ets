export class InkToolPolicy {
  static label(tool: string): string {
    return tool === 'eraser' ? '橡皮' : tool === 'highlighter' ? '荧光笔' : tool === 'pan' ? '浏览' : '普通笔';
  }
  static min(tool: string): number { return tool === 'eraser' ? 8 : tool === 'highlighter' ? 6 : 1; }
  static max(tool: string): number { return tool === 'eraser' ? 64 : tool === 'highlighter' ? 32 : 16; }
  static width(tool: string, value: number): number {
    return Math.round(Math.max(InkToolPolicy.min(tool), Math.min(InkToolPolicy.max(tool), Number.isFinite(value) ? value : InkToolPolicy.min(tool))));
  }
}
