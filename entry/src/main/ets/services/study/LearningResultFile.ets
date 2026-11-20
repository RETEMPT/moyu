import { Context } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { LearningResult } from '../../common/types/LearningResult';
import { ReviewDraft } from '../../common/types/StudyTypes';
import { LearningResultPolicy } from './LearningResultPolicy';

export class LearningResultFile {
  static async select(context: Context): Promise<LearningResult | null> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.json'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (uris.length === 0) { return null; }
    const file = await fs.open(uris[0], fs.OpenMode.READ_ONLY);
    try {
      const max = LearningResultPolicy.MAX_BYTES;
      const bytes = new Uint8Array(max + 1);
      let size = 0;
      while (size <= max) {
        const buffer = new ArrayBuffer(Math.min(16384, bytes.length - size));
        const count = await fs.read(file.fd, buffer, { offset: size });
        if (count === 0) { break; }
        bytes.set(new Uint8Array(buffer, 0, count), size);
        size += count;
      }
      if (size > max) { throw new Error('学习结果超过 128 KiB。'); }
      if (size >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) {
        throw new Error('请选择 UTF-8 无 BOM 的学习结果。');
      }
      const raw = util.TextDecoder.create('utf-8', { fatal: true }).decodeToString(bytes.subarray(0, size));
      return LearningResultPolicy.parse(raw);
    } finally { await fs.close(file); }
  }

  static async exportText(context: Context, title: string, text: string): Promise<boolean> {
    const options = new picker.DocumentSaveOptions();
    const name = title.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').trim().substring(0, 80) || '原文';
    options.newFileNames = [`${name}.txt`];
    options.fileSuffixChoices = ['UTF-8 文本|.txt'];
    const paths = await new picker.DocumentViewPicker(context).save(options);
    if (!paths.length) { return false; }
    const file = await fs.open(paths[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    const bytes = new util.TextEncoder().encodeInto(text);
    try {
      let offset = 0;
      while (offset < bytes.byteLength) {
        const block = bytes.slice(offset, offset + 65536);
        const count = await fs.write(file.fd, block.buffer as ArrayBuffer);
        if (count <= 0 || count > block.length) { throw new Error('原文未完整写入，请重试。'); }
        offset += count;
      }
      await fs.fsync(file.fd);
      return true;
    } finally { await fs.close(file); }
  }

  static async adoptionKey(draft: ReviewDraft): Promise<string> {
    const text = JSON.stringify([draft.question.trim(), draft.answer.trim(), draft.sourceText,
      String(draft.pageNumber || 0), String(draft.sourceLine || 0)]);
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: new util.TextEncoder().encodeInto(text) });
    const hash = await md.digest();
    return Array.from(hash.data).map((byte: number) => byte.toString(16).padStart(2, '0')).join('');
  }
}
