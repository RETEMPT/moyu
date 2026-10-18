import { Context } from '@kit.AbilityKit';
import { relationalStore, preferences } from '@kit.ArkData';
import { TodoItem, DayNote } from '../../common/types/TodoItem';
import { ReviewCard, ReviewRating } from '../../common/types/StudyTypes';
import { MemoDraft } from '../library/QuickMemoService';
import { RdbSnapshotRepository } from './RdbSnapshotRepository';
import { SerialTaskQueue } from './SerialTaskQueue';
import { SnapshotStore } from './SnapshotStore';
import { ReviewPolicy } from '../study/ReviewPolicy';

/** All domain records share flowmind-v2.db. Preferences are only read during migration. */
export class DomainStorage {
  private static queue: SerialTaskQueue = new SerialTaskQueue();
  private repository: RdbSnapshotRepository = new RdbSnapshotRepository();
  private snapshots: SnapshotStore = new SnapshotStore();
  private ready: boolean = false;
  private blocked: Set<string> = new Set();

  load<T>(context: Context, scope: string, name: string, key: string, valid: (value: T) => boolean): Promise<T | null> {
    return DomainStorage.queue.run<T | null>(() => this.read<T>(context, scope, name, key, valid));
  }

  save<T>(context: Context, scope: string, name: string, key: string, value: T, valid: (value: T) => boolean): Promise<void> {
    const json = JSON.stringify(value);
    return DomainStorage.queue.run<void>(async () => {
      if (this.blocked.has(scope)) { throw new Error('本地数据需要恢复，已阻止覆盖'); }
      // Never replace unread legacy data or a corrupted initialized table on a write-first path.
      await this.read<T>(context, scope, name, key, valid);
      const captured = JSON.parse(json) as T;
      if (!valid(captured)) { throw new Error('数据格式无效，已阻止保存'); }
      await this.write(scope, json);
    });
  }

  private async read<T>(context: Context, scope: string, name: string, key: string, valid: (value: T) => boolean): Promise<T | null> {
    try {
      if (!this.ready) { await this.repository.open(context); this.ready = true; }
      const json = await this.readRows(scope);
      if (json !== null) {
        if (scope === 'draft' && json === 'null') { return null; }
        const value = JSON.parse(json) as T;
        if (!valid(value)) { throw new Error('领域记录格式异常'); }
        return value;
      }
      const prefs = await preferences.getPreferences(context, { name });
      const legacy = await this.snapshots.read<T>(prefs, key, valid);
      // Mark even a previously missing key as migrated; old Preferences never become authoritative again.
      await this.write(scope, JSON.stringify(legacy === null ? scope === 'draft' ? null : [] : legacy));
      return legacy;
    } catch (error) {
      this.blocked.add(scope);
      throw new Error('本地数据读取或迁移失败，原数据已保留，已阻止覆盖');
    }
  }

  /** Detect accidental row/field loss, including missing references. This is not a cryptographic signature. */
  private digest(json: string): string {
    let hash = 2166136261;
    for (let index = 0; index < json.length; index++) { hash = Math.imul(hash ^ json.charCodeAt(index), 16777619); }
    return (hash >>> 0).toString(16);
  }

  private readRows(scope: string): Promise<string | null> {
    return RdbSnapshotRepository.queue.run<string | null>(async () => {
      const tx = await this.repository.database().createTransaction();
      try {
        const head = await tx.querySql('SELECT count,digest FROM domain_heads WHERE scope=?', [scope]);
        let found = false, count = 0, digest = '';
        try { found = head.goToFirstRow(); if (found) { count = head.getLong(0); digest = head.getString(1); } } finally { head.close(); }
        const json = await this.select(tx, scope);
        const value = JSON.parse(json) as Object;
        const actual = Array.isArray(value) ? value.length : value === null ? 0 : 1;
        if (!found) {
          const marker = await tx.querySql('SELECT scope FROM repository_scopes WHERE scope=?', ['domain:' + scope]);
          let migrated = false;
          try { migrated = marker.goToFirstRow(); } finally { marker.close(); }
          if (migrated) { throw new Error('已迁移领域目录缺失'); }
          if (actual > 0) { throw new Error('领域记录迁移目录缺失'); }
          await tx.commit(); return null;
        }
        if (count !== actual || digest !== this.digest(json)) { throw new Error('领域记录不完整'); }
        await tx.commit(); return json;
      } catch (error) { try { await tx.rollback(); } catch { /* The read caller blocks this scope. */ } throw new Error(error instanceof Error ? error.message : '本地领域数据读取失败'); }
    });
  }

  private write(scope: string, json: string): Promise<void> {
    return RdbSnapshotRepository.queue.run<void>(async () => {
      const tx = await this.repository.database().createTransaction();
      try {
        await this.replace(tx, scope, json);
        // Canonical digest is made from the same SQL reader used after restart.
        const canonical = await this.select(tx, scope);
        const value = JSON.parse(canonical) as Object;
        const count = Array.isArray(value) ? value.length : value === null ? 0 : 1;
        await tx.execute('INSERT INTO domain_heads(scope,count,digest) VALUES(?,?,?) ON CONFLICT(scope) DO UPDATE SET count=excluded.count,digest=excluded.digest',
          [scope, count, this.digest(canonical)]);
        await tx.execute('INSERT OR IGNORE INTO repository_scopes(scope) VALUES(?)', ['domain:' + scope]);
        await tx.commit();
      } catch (error) {
        try { await tx.rollback(); } catch { this.blocked.add(scope); }
        throw new Error('本地关系数据保存失败，请保留当前内容后重试');
      }
    });
  }

  private async replace(tx: relationalStore.Transaction, scope: string, json: string): Promise<void> {
    if (scope === 'todos') {
      const todos = JSON.parse(json) as TodoItem[];
      await tx.execute('DELETE FROM todo_note_refs'); await tx.execute('DELETE FROM todo_items');
      for (let index = 0; index < todos.length; index++) {
        const item = todos[index];
        await tx.execute('INSERT INTO todo_items VALUES(?,?,?,?,?,?,?)', [item.id, index, item.date, item.title, item.done ? 1 : 0, item.createdAt || 0, item.updatedAt || 0]);
        const refs = item.noteRefs || [];
        for (let position = 0; position < refs.length; position++) {
          await tx.execute('INSERT INTO todo_note_refs VALUES(?,?,?)', [item.id, position, refs[position]]);
        }
      }
    } else if (scope === 'daynotes') {
      const notes = JSON.parse(json) as DayNote[]; await tx.execute('DELETE FROM day_notes');
      for (let index = 0; index < notes.length; index++) {
        const note = notes[index]; await tx.execute('INSERT INTO day_notes VALUES(?,?,?,?)', [note.date, index, note.text, note.updatedAt || 0]);
      }
    } else if (scope === 'cards') {
      const original = JSON.parse(json) as ReviewCard[];
      const cards = ReviewPolicy.normalize(original);
      if (cards.length !== original.length) { throw new Error('题卡记录无效，已保留原记录'); }
      await tx.execute('DELETE FROM review_cards');
      for (let index = 0; index < cards.length; index++) {
        const card = cards[index];
        await tx.execute('INSERT INTO review_cards VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [card.id, index, card.noteId, card.course, card.question,
          card.answer, card.sourceText, card.pageNumber ?? null, card.dueAt, card.intervalDays, card.repetitions, card.reviewCount ?? null,
          card.lapses, card.createdAt, card.updatedAt, card.lastRating ?? null]);
      }
    } else if (scope === 'draft') {
      const draft = JSON.parse(json) as MemoDraft | null; await tx.execute('DELETE FROM memo_drafts WHERE slot=?', ['quick']);
      if (draft) { await tx.execute('INSERT INTO memo_drafts VALUES(?,?,?)', ['quick', draft.id, draft.content]); }
    } else { throw new Error('未知领域集合'); }
  }

  private async select(tx: relationalStore.Transaction, scope: string): Promise<string> {
    if (scope === 'todos') {
      const refs = await tx.querySql('SELECT todo_id,note_id FROM todo_note_refs ORDER BY todo_id,position');
      const byId: Map<string, string[]> = new Map();
      try { while (refs.goToNextRow()) { const id = refs.getString(0), list = byId.get(id) || []; list.push(refs.getString(1)); byId.set(id, list); } } finally { refs.close(); }
      const rows = await tx.querySql('SELECT id,date,title,done,created_at,updated_at FROM todo_items ORDER BY position');
      const items: TodoItem[] = [];
      try { while (rows.goToNextRow()) { const id = rows.getString(0); items.push({ id, date: rows.getString(1), title: rows.getString(2),
        done: rows.getLong(3) === 1, noteRefs: byId.get(id) || [], createdAt: rows.getLong(4), updatedAt: rows.getLong(5) }); byId.delete(id); } } finally { rows.close(); }
      if (byId.size > 0) { throw new Error('孤立待办关联'); }
      return JSON.stringify(items);
    }
    if (scope === 'daynotes') {
      const rows = await tx.querySql('SELECT date,text,updated_at FROM day_notes ORDER BY position'); const items: DayNote[] = [];
      try { while (rows.goToNextRow()) { items.push({ date: rows.getString(0), text: rows.getString(1), updatedAt: rows.getLong(2) }); } } finally { rows.close(); }
      return JSON.stringify(items);
    }
    if (scope === 'cards') {
      const rows = await tx.querySql("SELECT id,note_id,course,question,answer,source_text,COALESCE(page_number,0),due_at,interval_days,repetitions,COALESCE(review_count,-1),lapses,created_at,updated_at,COALESCE(last_rating,'') FROM review_cards ORDER BY position");
      const items: ReviewCard[] = [];
      try { while (rows.goToNextRow()) {
        const page = rows.getLong(6), count = rows.getLong(10), rating = rows.getString(14);
        items.push({ id: rows.getString(0), noteId: rows.getString(1), course: rows.getString(2), question: rows.getString(3),
          answer: rows.getString(4), sourceText: rows.getString(5), pageNumber: page > 0 ? page : undefined,
          dueAt: rows.getLong(7), intervalDays: rows.getDouble(8), repetitions: rows.getLong(9), reviewCount: count >= 0 ? count : undefined,
          lapses: rows.getLong(11), createdAt: rows.getLong(12), updatedAt: rows.getLong(13), lastRating: rating ? rating as ReviewRating : undefined });
      } } finally { rows.close(); }
      return JSON.stringify(items);
    }
    if (scope === 'draft') {
      const rows = await tx.querySql('SELECT id,content FROM memo_drafts WHERE slot=?', ['quick']);
      try { const draft: MemoDraft | null = rows.goToFirstRow() ? { id: rows.getString(0), content: rows.getString(1) } : null; return JSON.stringify(draft); }
      finally { rows.close(); }
    }
    throw new Error('未知领域集合');
  }
}
