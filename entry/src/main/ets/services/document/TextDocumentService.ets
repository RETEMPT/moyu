import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';

export class TextDocumentService {
  static async read(uri: string, maxBytes: number = Number.MAX_SAFE_INTEGER): Promise<string> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = (await fileIo.stat(file.fd)).size;
      if (size > maxBytes) { throw new Error('文件太大，请分段后再导入'); }
      const decoder = util.TextDecoder.create('utf-8');
      const buffer = new ArrayBuffer(Math.min(65536, size));
      const parts: string[] = [];
      let offset = 0;
      while (offset < size) {
        const count = await fileIo.read(file.fd, buffer, { offset, length: Math.min(buffer.byteLength, size - offset) });
        if (count <= 0 || count > size - offset || count > buffer.byteLength) {
          throw new Error('文件读取中断，请重新选择原件');
        }
        offset += count;
        parts.push(decoder.decodeToString(new Uint8Array(buffer, 0, count), { stream: offset < size }));
      }
      return parts.join('');
    } finally {
      await fileIo.close(file);
    }
  }
}
