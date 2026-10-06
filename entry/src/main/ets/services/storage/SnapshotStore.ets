import { preferences } from '@kit.ArkData';
import { SerialTaskQueue } from './SerialTaskQueue';

/** Protect legacy JSON snapshots without changing their on-disk schema. */
export class SnapshotStore {
  private static queue: SerialTaskQueue = new SerialTaskQueue();
  private blocked: Set<string> = new Set();
  private cacheUnsafe: boolean = false;

  block(key: string): void { this.blocked.add(key); }

  read<T>(prefs: preferences.Preferences, key: string, valid: (value: T) => boolean): Promise<T | null> {
    return SnapshotStore.queue.run<T | null>(async () => {
      try {
        const raw = await prefs.get(key, '');
        if (raw === '') { return null; }
        if (typeof raw !== 'string') { throw new Error('invalid snapshot'); }
        const value = JSON.parse(raw) as T;
        if (!valid(value)) { throw new Error('invalid snapshot'); }
        return value;
      } catch {
        this.block(key);
        throw new Error('本地数据格式异常，原数据已保留；请先导出可读取的资料，勿继续覆盖');
      }
    });
  }

  write(prefs: preferences.Preferences, key: string, json: string): Promise<void> {
    // json is captured before entering the queue, so callers cannot mutate a pending snapshot.
    return SnapshotStore.queue.run<void>(async () => {
      if (this.cacheUnsafe || this.blocked.has(key)) { throw new Error('本地数据需要恢复，已阻止覆盖原快照'); }
      const previous = await prefs.get(key, '');
      try {
        await prefs.put(key, json);
        await prefs.flush();
      } catch (error) {
        try { await prefs.put(key, previous); }
        catch { this.cacheUnsafe = true; }
        throw new Error('数据保存未完成，请重试并在重启后核对');
      }
    });
  }
}
