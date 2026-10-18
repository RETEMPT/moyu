import { Context } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { SerialTaskQueue } from './SerialTaskQueue';

export interface SnapshotWrite { scope: string; json: string; }
interface ChunkedWrite { scope: string; chunks: string[]; }

/** Versioned transactional repository. Chunked rows stay below the platform's 2 MB row limit. */
export class RdbSnapshotRepository {
  static readonly queue: SerialTaskQueue = new SerialTaskQueue();
  private store: relationalStore.RdbStore | null = null;
  private blocked: Set<string> = new Set();

  async open(context: Context): Promise<void> {
    return RdbSnapshotRepository.queue.run<void>(async () => {
      const store = await relationalStore.getRdbStore(context, { name: 'flowmind-v2.db', securityLevel: relationalStore.SecurityLevel.S1 });
      if (store.version > 2) { throw new Error('本地资料库来自更新版本，请使用对应版本打开'); }
      await store.executeSql('CREATE TABLE IF NOT EXISTS snapshot_heads (scope TEXT PRIMARY KEY, parts INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
      await store.executeSql('CREATE TABLE IF NOT EXISTS snapshot_chunks (scope TEXT NOT NULL, ordinal INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(scope, ordinal))');
      await store.executeSql('CREATE TABLE IF NOT EXISTS repository_scopes (scope TEXT PRIMARY KEY)');
      await store.executeSql('CREATE TABLE IF NOT EXISTS domain_heads (scope TEXT PRIMARY KEY, count INTEGER NOT NULL, digest TEXT NOT NULL)');
      await store.executeSql('CREATE TABLE IF NOT EXISTS todo_items (id TEXT PRIMARY KEY, position INTEGER NOT NULL, date TEXT NOT NULL, title TEXT NOT NULL, done INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL)');
      await store.executeSql('CREATE TABLE IF NOT EXISTS todo_note_refs (todo_id TEXT NOT NULL, position INTEGER NOT NULL, note_id TEXT NOT NULL, PRIMARY KEY(todo_id,position))');
      await store.executeSql('CREATE INDEX IF NOT EXISTS idx_todo_date_done ON todo_items(date,done,created_at)');
      await store.executeSql('CREATE INDEX IF NOT EXISTS idx_todo_refs_note ON todo_note_refs(note_id,todo_id)');
      await store.executeSql('CREATE TABLE IF NOT EXISTS day_notes (date TEXT PRIMARY KEY, position INTEGER NOT NULL, text TEXT NOT NULL, updated_at INTEGER NOT NULL)');
      await store.executeSql('CREATE TABLE IF NOT EXISTS review_cards (id TEXT PRIMARY KEY, position INTEGER NOT NULL, note_id TEXT NOT NULL, course TEXT NOT NULL, question TEXT NOT NULL, answer TEXT NOT NULL, source_text TEXT NOT NULL, page_number INTEGER, due_at INTEGER NOT NULL, interval_days REAL NOT NULL, repetitions INTEGER NOT NULL, review_count INTEGER, lapses INTEGER NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, last_rating TEXT)');
      await store.executeSql('CREATE INDEX IF NOT EXISTS idx_cards_note_due ON review_cards(note_id,due_at)');
      await store.executeSql('CREATE INDEX IF NOT EXISTS idx_cards_due ON review_cards(due_at,id)');
      await store.executeSql('CREATE TABLE IF NOT EXISTS memo_drafts (slot TEXT PRIMARY KEY, id TEXT NOT NULL, content TEXT NOT NULL)');
      store.version = 2;
      this.store = store;
    });
  }

  database(): relationalStore.RdbStore { return this.requireStore(); }

  block(scope: string): void { this.blocked.add(scope); }

  static chunks(json: string): string[] {
    if (json.length > 128 * 1024 * 1024) { throw new Error('资料快照较大，请先分库导出'); }
    const chunks: string[] = [];
    for (let start = 0; start < json.length; start += 65536) {
      // Encoding each chunk separately preserves a surrogate pair split at a chunk boundary.
      chunks.push(JSON.stringify(json.substring(start, start + 65536)));
    }
    return chunks;
  }

  read(scope: string): Promise<string | null> {
    return RdbSnapshotRepository.queue.run<string | null>(async () => {
      const store = this.requireStore();
      const transaction = await store.createTransaction();
      try {
        const head = await transaction.querySql('SELECT parts FROM snapshot_heads WHERE scope=?', [scope]);
        let count: number = 0;
        let found: boolean = false;
        try {
          found = head.goToFirstRow();
          if (found) { count = head.getLong(0); }
        } finally { head.close(); }
        if (!found) {
          const state = await transaction.querySql('SELECT scope FROM repository_scopes WHERE scope=? UNION ALL SELECT scope FROM snapshot_chunks WHERE scope=? LIMIT 1', [scope, scope]);
          let initialized: boolean = false;
          try { initialized = state.goToFirstRow(); } finally { state.close(); }
          if (initialized) { throw new Error('已迁移快照的目录缺失'); }
          await transaction.commit(); return null;
        }
        if (!Number.isInteger(count) || count <= 0 || count > 4096) { throw new Error('快照目录无效'); }
        const rows = await transaction.querySql('SELECT ordinal,payload FROM snapshot_chunks WHERE scope=? ORDER BY ordinal', [scope]);
        const pieces: string[] = [];
        try {
          while (rows.goToNextRow()) {
            if (rows.getLong(0) !== pieces.length) { throw new Error('快照分片缺失'); }
            const part = JSON.parse(rows.getString(1)) as string;
            if (typeof part !== 'string' || part.length > 65536) { throw new Error('快照分片无效'); }
            pieces.push(part);
          }
        } finally { rows.close(); }
        if (pieces.length !== count) { throw new Error('快照分片不完整'); }
        await transaction.commit();
        return pieces.join('');
      } catch (error) {
        console.error('关系数据库读取失败：' + (error instanceof Error ? error.message : '未知原因'));
        this.block(scope);
        try { await transaction.rollback(); } catch { /* Keep the original database unchanged. */ }
        throw new Error('本地关系数据库读取异常，原库已保留，已阻止覆盖');
      }
    });
  }

  write(scope: string, json: string): Promise<void> {
    return this.writeMany([{ scope, json }]);
  }

  /** A workspace transition either commits every collection or leaves all of them unchanged. */
  writeMany(writes: SnapshotWrite[]): Promise<void> {
    const captured: ChunkedWrite[] = writes.map((write: SnapshotWrite): ChunkedWrite =>
      ({ scope: write.scope, chunks: RdbSnapshotRepository.chunks(write.json) }));
    if (new Set(captured.map((write: ChunkedWrite) => write.scope)).size !== captured.length) { throw new Error('重复的资料集合'); }
    return RdbSnapshotRepository.queue.run<void>(async () => {
      for (const write of captured) {
        if (this.blocked.has(write.scope)) { throw new Error('本地资料库需要恢复，已阻止覆盖原记录'); }
      }
      const transaction = await this.requireStore().createTransaction();
      try {
        for (const write of captured) {
          const scope = write.scope, chunks = write.chunks;
          await transaction.execute('DELETE FROM snapshot_chunks WHERE scope=?', [scope]);
          for (let index = 0; index < chunks.length; index++) {
            await transaction.execute('INSERT INTO snapshot_chunks(scope,ordinal,payload) VALUES(?,?,?)', [scope, index, chunks[index]]);
          }
          await transaction.execute('INSERT INTO snapshot_heads(scope,parts,updated_at) VALUES(?,?,?) ON CONFLICT(scope) DO UPDATE SET parts=excluded.parts,updated_at=excluded.updated_at', [scope, chunks.length, Date.now()]);
          await transaction.execute('INSERT OR IGNORE INTO repository_scopes(scope) VALUES(?)', [scope]);
        }
        await transaction.commit();
      } catch (error) {
        try { await transaction.rollback(); } catch { for (const write of captured) { this.block(write.scope); } }
        throw new Error('本地关系数据库保存未完成，请重试并保留当前内容');
      }
    });
  }

  private requireStore(): relationalStore.RdbStore {
    if (this.store === null) { throw new Error('本地资料库尚未初始化'); }
    return this.store;
  }
}
