import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { SerialTaskQueue } from './SerialTaskQueue';

/** Write beside the destination first. A short write never truncates the last valid document. */
export class AtomicTextFile {
  private static queue: SerialTaskQueue = new SerialTaskQueue();

  write(path: string, content: string): Promise<void> {
    return AtomicTextFile.queue.run<void>(async () => {
      const temporary = path + '.pending';
      try {
        const file = await fileIo.open(temporary, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
        try {
          const expected = new util.TextEncoder().encodeInto(content).length;
          if (await fileIo.write(file.fd, content) !== expected) { throw new Error('正文未完整写入'); }
          await fileIo.fsync(file.fd);
        } finally { await fileIo.close(file); }
        await fileIo.rename(temporary, path);
      } catch (error) {
        try { if (await fileIo.access(temporary)) { await fileIo.unlink(temporary); } } catch { /* Preserve destination. */ }
        throw new Error(error instanceof Error ? error.message : '正文保存失败');
      }
    });
  }
}
