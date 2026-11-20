import { util, xml } from '@kit.ArkTS';
import { zlib } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { OfficeZip } from './OfficeZip';

const MAX_FILE_BYTES: number = 24 * 1024 * 1024;
const MAX_MARKDOWN: number = 240000;
const MAX_SLIDES: number = 150;

/** Imports a text reading copy of a Word document or slide deck using local system libraries. */
export class OfficeDocumentService {
  static async read(uri: string, slides: boolean): Promise<string> {
    const archive = new OfficeZip(await OfficeDocumentService.readFile(uri));
    if (!slides) {
      const content = OfficeDocumentService.paragraphs(await OfficeDocumentService.readPart(archive, 'word/document.xml'));
      if (!content) { throw new Error('DOCX 中没有可导入的正文文字。图文版请先导出为 PDF。'); }
      return content;
    }

    const manifest = await OfficeDocumentService.readPart(archive, 'ppt/presentation.xml');
    const relations = await OfficeDocumentService.readPart(archive, 'ppt/_rels/presentation.xml.rels');
    const targets = OfficeDocumentService.slideTargets(manifest, relations);
    const sections: string[] = [];
    let length = 0;
    let hasText = false;
    for (let index = 0; index < targets.length; index++) {
      const content = OfficeDocumentService.paragraphs(await OfficeDocumentService.readPart(archive, targets[index]));
      hasText = hasText || !!content;
      const section = `## 第 ${index + 1} 张幻灯片\n\n${content || '（此页未提取到文字）'}`;
      length += section.length + 2;
      if (length > MAX_MARKDOWN) { throw new Error('幻灯片文字过多，请拆分文件后重新导入。'); }
      sections.push(section);
    }
    if (!hasText) { throw new Error('PPTX 中没有可导入的文字。图文版请先导出为 PDF。'); }
    return sections.join('\n\n');
  }

  private static async readFile(uri: string): Promise<ArrayBuffer> {
    const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
    try {
      const size = (await fileIo.stat(file.fd)).size;
      if (!Number.isInteger(size) || size < 22 || size > MAX_FILE_BYTES) {
        throw new Error('请选择完整且不超过 24 MiB 的 Office 文件。');
      }
      const result = new Uint8Array(size);
      let offset = 0;
      while (offset < size) {
        const chunk = new ArrayBuffer(Math.min(65536, size - offset));
        const count = await fileIo.read(file.fd, chunk, { offset });
        if (count <= 0 || count > chunk.byteLength) { throw new Error('未读完 Office 文件，请重新选择原件。'); }
        result.set(new Uint8Array(chunk, 0, count), offset);
        offset += count;
      }
      return result.buffer as ArrayBuffer;
    } finally {
      await fileIo.close(file);
    }
  }

  private static async readPart(archive: OfficeZip, path: string): Promise<string> {
    const part = archive.part(path);
    let bytes = part.data;
    if (part.method === 8) {
      const zip = await zlib.createZip();
      const stream: zlib.ZStream = {};
      if (await zip.inflateInit2(stream, -15) !== zlib.ReturnStatus.OK) { throw new Error('无法初始化 Office 解压。'); }
      try {
        bytes = new ArrayBuffer(part.size + 1);
        stream.nextIn = part.data;
        stream.availableIn = part.data.byteLength;
        stream.nextOut = bytes;
        stream.availableOut = bytes.byteLength;
        const status = await zip.inflate(stream, zlib.CompressFlushMode.FINISH);
        const state = await zip.getZStream();
        if (status !== zlib.ReturnStatus.STREAM_END || state.totalOut !== part.size || state.totalIn !== part.data.byteLength) {
          throw new Error('Office 正文的压缩数据不完整。');
        }
        bytes = bytes.slice(0, part.size);
      } finally {
        await zip.inflateEnd({});
      }
    }
    const checksum = await zlib.createChecksum();
    if (bytes.byteLength !== part.size || ((await checksum.crc32(0, bytes)) >>> 0) !== part.crc) {
      throw new Error('Office 正文校验失败。');
    }
    const text = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(new Uint8Array(bytes));
    if (/<!\s*(?:DOCTYPE|ENTITY)\b/i.test(text)) { throw new Error('Office 正文包含不支持的 XML 声明。'); }
    return text;
  }

  private static slideTargets(manifest: string, relations: string): string[] {
    const paths = new Map<string, string>();
    for (const match of relations.matchAll(/<(?:[\w.-]+:)?Relationship\b([^>]*?)\/?\s*>/g)) {
      const attrs = OfficeDocumentService.attributes(match[1]);
      const id = attrs.get('Id');
      const target = attrs.get('Target') || '';
      const type = attrs.get('Type') || '';
      if (!id || !type.endsWith('/slide') || attrs.get('TargetMode') === 'External') { continue; }
      if (paths.has(id) || !/^(?:\/ppt\/)?slides\/slide[0-9]+\.xml$/.test(target)) {
        throw new Error('PPTX 中有无法定位的幻灯片。');
      }
      paths.set(id, target.startsWith('/') ? target.slice(1) : 'ppt/' + target);
    }
    const list = manifest.match(/<(?:[\w.-]+:)?sldIdLst\b[^>]*>([\s\S]*?)<\/(?:[\w.-]+:)?sldIdLst\s*>/);
    const ordered: string[] = [];
    for (const match of (list?.[1] || '').matchAll(/<(?:[\w.-]+:)?sldId\b([^>]*?)\/?\s*>/g)) {
      const attrs = OfficeDocumentService.attributes(match[1]);
      let target = '';
      attrs.forEach((value: string, key: string) => {
        if (key.endsWith(':id')) { target = paths.get(value) || ''; }
      });
      if (!target || ordered.includes(target)) { throw new Error('PPTX 的幻灯片顺序记录不完整。'); }
      ordered.push(target);
      if (ordered.length > MAX_SLIDES) { throw new Error('每次最多导入 150 张幻灯片，请拆分文件。'); }
    }
    if (!ordered.length) { throw new Error('PPTX 中找不到幻灯片。'); }
    return ordered;
  }

  private static attributes(value: string): Map<string, string> {
    const result = new Map<string, string>();
    for (const match of value.matchAll(/([\w.:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) {
      result.set(match[1], match[2] ?? match[3]);
    }
    return result;
  }

  private static paragraphs(source: string): string {
    const bytes = new util.TextEncoder().encodeInto(source);
    const parser = new xml.XmlPullParser(bytes.buffer as ArrayBuffer, 'UTF-8');
    const paragraphs: string[] = [];
    let text = '';
    let inText = false;
    let length = 0;
    parser.parseXml({
      supportDoctype: false,
      tokenValueCallbackFunction: (event: xml.EventType, info: xml.ParseInfo): boolean => {
        if (event === xml.EventType.START_TAG) {
          const tag = info.getName().split(':').pop() || '';
          if (tag === 't') { inText = true; }
          else if (tag === 'tab' || tag === 'br') { text += ' '; }
        } else if (event === xml.EventType.END_TAG) {
          const tag = info.getName().split(':').pop() || '';
          if (tag === 't') { inText = false; }
          if (tag === 'p') {
            const paragraph = text.replace(/\s+/g, ' ').trim();
            if (paragraph) {
              paragraphs.push(OfficeDocumentService.escape(paragraph));
              length += paragraphs[paragraphs.length - 1].length + 2;
              if (length > MAX_MARKDOWN) { throw new Error('Office 正文过长，请拆分文件。'); }
            }
            text = '';
          }
        } else if (inText && (event === xml.EventType.TEXT || event === xml.EventType.CDSECT ||
          event === xml.EventType.ENTITY_REFERENCE)) { text += info.getText(); }
        return true;
      }
    });
    return paragraphs.join('\n\n');
  }

  private static escape(text: string): string {
    return text.replace(/[\\`*_\[\]<>|#!~$]/g, '\\$&').replace(/^(\d+)([.)])(?=\s)/, '$1\\$2');
  }
}
