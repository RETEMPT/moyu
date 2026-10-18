import { util } from '@kit.ArkTS';
import { StudyBackup } from '../../common/types/StudyBackup';
import { StudyBackupPolicy } from './StudyBackupPolicy';

/** Parsing, validation and large JSON buffers run outside the UI thread. */
@Concurrent
export function validateBackupData(input: StudyBackup): StudyBackup {
  const backup = StudyBackupPolicy.validate(input);
  if (new util.TextEncoder().encodeInto(JSON.stringify(backup)).length > 32 * 1024 * 1024) {
    throw new Error('资料包超过 32 MB，请减少所选资料后重试');
  }
  return backup;
}

@Concurrent
export function encodeBackupData(backup: StudyBackup): ArrayBuffer {
  const bytes = new util.TextEncoder().encodeInto(JSON.stringify(backup));
  if (bytes.length > 32 * 1024 * 1024) { throw new Error('资料包超过 32 MB'); }
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

@Concurrent
export function decodeBackupData(buffer: ArrayBuffer): StudyBackup {
  const text = new util.TextDecoder().decodeToString(new Uint8Array(buffer));
  return StudyBackupPolicy.validate(JSON.parse(text) as StudyBackup);
}
