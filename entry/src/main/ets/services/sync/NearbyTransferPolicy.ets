import { StudyBackup } from '../../common/types/StudyBackup';
import { StudyBackupPolicy } from '../study/StudyBackupPolicy';

export interface TransferManifest {
  version: number; id: string; createdAt: number; chunks: number; characters: number; sha256: string;
}
export interface TransferPart { key: string; value: string; }
export interface TransferPacket { manifest: TransferManifest; parts: TransferPart[]; }
export type TransferDigest = (content: string) => Promise<string>;

/** A transfer is immutable, expires after 15 minutes, and always imports as a copy. */
export class NearbyTransferPolicy {
  static readonly MAX_CHARACTERS: number = 8 * 1024 * 1024;
  static readonly CHUNK_CHARACTERS: number = 32 * 1024;
  static readonly LIFETIME: number = 15 * 60 * 1000;

  static prefix(id: string): string {
    if (!/^[a-zA-Z0-9]{1,24}$/.test(id)) { throw new Error('请填写发送端显示的完整传递码'); }
    return `transfer_${id}:`;
  }

  static async pack(input: StudyBackup, digest: TransferDigest, now: number = Date.now()): Promise<TransferPacket> {
    const backup = StudyBackupPolicy.validate(input);
    const content = JSON.stringify(backup);
    if (!backup.notes.length) { throw new Error('请先选择有资料的课程'); }
    if (content.length > NearbyTransferPolicy.MAX_CHARACTERS) { throw new Error('资料超过附近传递容量，请按课程缩小范围或使用文件备份'); }
    const parts: TransferPart[] = [];
    const prefix = NearbyTransferPolicy.prefix(backup.id);
    for (let offset = 0; offset < content.length; offset += NearbyTransferPolicy.CHUNK_CHARACTERS) {
      // JSON escaping preserves surrogate pairs even when a pair crosses a chunk boundary.
      parts.push({ key: prefix + parts.length, value: JSON.stringify(content.slice(offset, offset + NearbyTransferPolicy.CHUNK_CHARACTERS)) });
    }
    const manifest: TransferManifest = { version: 1, id: backup.id, createdAt: now, chunks: parts.length,
      characters: content.length, sha256: await digest(content) };
    if (!/^[a-f0-9]{64}$/.test(manifest.sha256)) { throw new Error('传递校验无法生成'); }
    return { manifest, parts };
  }

  static async unpack(id: string, rawManifest: string, parts: TransferPart[], digest: TransferDigest,
    now: number = Date.now()): Promise<StudyBackup> {
    const prefix = NearbyTransferPolicy.prefix(id);
    if (rawManifest.length > 2048) { throw new Error('传递清单过大'); }
    let manifest: TransferManifest;
    try { manifest = JSON.parse(rawManifest) as TransferManifest; } catch { throw new Error('传递清单无法读取，请重新发送'); }
    if (!manifest || manifest.version !== 1 || manifest.id !== id || !Number.isFinite(manifest.createdAt) ||
      manifest.createdAt > now + 60000 || now - manifest.createdAt > NearbyTransferPolicy.LIFETIME ||
      !Number.isInteger(manifest.characters) || manifest.characters < 1 || manifest.characters > NearbyTransferPolicy.MAX_CHARACTERS ||
      !Number.isInteger(manifest.chunks) || manifest.chunks !== Math.ceil(manifest.characters / NearbyTransferPolicy.CHUNK_CHARACTERS) ||
      typeof manifest.sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(manifest.sha256)) {
      throw new Error('传递码已过期或清单不受支持，请在发送端重新生成');
    }
    const values = new Map<string, string>();
    if (parts.length !== manifest.chunks) { throw new Error('资料分片重复或尚未完整接收'); }
    for (const part of parts) {
      if (!part || typeof part.key !== 'string' || typeof part.value !== 'string' || values.has(part.key) ||
        part.value.length > NearbyTransferPolicy.CHUNK_CHARACTERS * 6 + 2) { throw new Error('传递分片重复、过大或无效'); }
      let decoded: string;
      try { decoded = JSON.parse(part.value) as string; } catch { throw new Error('传递分片无法解析'); }
      if (typeof decoded !== 'string' || decoded.length > NearbyTransferPolicy.CHUNK_CHARACTERS) { throw new Error('传递分片过大或无效'); }
      values.set(part.key, decoded);
    }
    if (values.size !== manifest.chunks) { throw new Error('资料尚未完整接收，请核对两端连接'); }
    const chunks: string[] = [];
    for (let i = 0; i < manifest.chunks; i++) {
      const value = values.get(prefix + i);
      const expected = Math.min(NearbyTransferPolicy.CHUNK_CHARACTERS, manifest.characters - i * NearbyTransferPolicy.CHUNK_CHARACTERS);
      if (value === undefined || value.length !== expected) { throw new Error('资料分片缺失或长度异常，请重新发送'); }
      chunks.push(value);
    }
    const content = chunks.join('');
    if (await digest(content) !== manifest.sha256) { throw new Error('资料完整性校验失败，尚未导入任何内容'); }
    const backup = StudyBackupPolicy.validate(JSON.parse(content) as StudyBackup);
    if (backup.id !== id) { throw new Error('传递码与资料不匹配'); }
    return backup;
  }
}
