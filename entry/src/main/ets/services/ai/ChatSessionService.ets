/**
 * 对话会话持久化服务
 *
 * 与 NoteStorageService 同范式：Preferences JSON 快照。
 * 每次会话变更立即落盘（消息量可控，不拆文件）。
 */
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ChatSession } from '../../common/types/ChatSession';
import { ChatSessionSanitizer } from './ChatSessionSanitizer';
import { SerialTaskQueue } from '../storage/SerialTaskQueue';
import { SnapshotStore } from '../storage/SnapshotStore';

const PREFERENCES_NAME: string = 'flowmind_chat';
const SESSIONS_KEY: string = 'sessions';
const MAX_SESSIONS: number = 200;

export class ChatSessionService {
  private static instance: ChatSessionService | null = null;
  private prefs: preferences.Preferences | null = null;
  private mutations: SerialTaskQueue = new SerialTaskQueue();
  private snapshots: SnapshotStore = new SnapshotStore();

  static getInstance(): ChatSessionService {
    if (ChatSessionService.instance === null) {
      ChatSessionService.instance = new ChatSessionService();
    }
    return ChatSessionService.instance;
  }

  async init(context: Context): Promise<void> {
    if (this.prefs !== null) {
      return;
    }
    this.prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
  }

  /** 读取全部会话，按 updatedAt 倒序 */
  async loadSessions(): Promise<ChatSession[]> {
    return this.mutations.run<ChatSession[]>(() => this.readSessions());
  }

  private async readSessions(): Promise<ChatSession[]> {
    const prefs: preferences.Preferences = await this.ensureInit();
    const parsed = await this.snapshots.read<ChatSession[]>(prefs, SESSIONS_KEY, (rows: ChatSession[]) =>
      Array.isArray(rows) && rows.every((row: ChatSession) => row !== null && typeof row.id === 'string' && Array.isArray(row.messages)));
    return ChatSessionSanitizer.normalize(parsed || []);
  }

  /** 保存全部会话 */
  async saveSessions(sessions: ChatSession[]): Promise<void> {
    const snapshot = JSON.parse(JSON.stringify(sessions)) as ChatSession[];
    await this.mutations.run<void>(() => this.writeSessions(snapshot));
  }

  private async writeSessions(sessions: ChatSession[]): Promise<void> {
    const prefs: preferences.Preferences = await this.ensureInit();
    // 限制数量，优先保留置顶
    let trimmed: ChatSession[] = ChatSessionSanitizer.normalize(sessions);
    if (trimmed.length > MAX_SESSIONS) {
      const pinned: ChatSession[] = trimmed.filter((s: ChatSession) => s.pinned);
      const unpinned: ChatSession[] = trimmed.filter((s: ChatSession) => !s.pinned)
        .sort((a: ChatSession, b: ChatSession) => b.updatedAt - a.updatedAt);
      const keep: ChatSession[] = [...pinned.slice(0, MAX_SESSIONS), ...unpinned.slice(0, Math.max(0, MAX_SESSIONS - pinned.length))];
      trimmed = keep;
    }
    await this.snapshots.write(prefs, SESSIONS_KEY, JSON.stringify(trimmed));
  }

  /** upsert 单个会话 */
  async saveSession(session: ChatSession): Promise<void> {
    const snapshot = JSON.parse(JSON.stringify(session)) as ChatSession;
    await this.mutations.run<void>(async () => {
      const sessions: ChatSession[] = await this.readSessions();
      let found: boolean = false;
      for (let i = 0; i < sessions.length; i++) {
        if (sessions[i].id === snapshot.id) {
          sessions[i] = snapshot;
          found = true;
          break;
        }
      }
      if (!found) { sessions.unshift(snapshot); }
      await this.writeSessions(sessions);
    });
  }

  /** 删除会话 */
  async deleteSession(id: string): Promise<void> {
    await this.mutations.run<void>(async () => {
      const sessions: ChatSession[] = await this.readSessions();
      const filtered: ChatSession[] = sessions.filter((s: ChatSession) => s.id !== id);
      await this.writeSessions(filtered);
    });
  }

  /** 清空全部 */
  async clearAll(): Promise<void> {
    await this.saveSessions([]);
  }

  /** 按关键词搜索会话标题和消息内容 */
  async search(query: string): Promise<ChatSession[]> {
    const sessions: ChatSession[] = await this.loadSessions();
    const q: string = query.trim().toLowerCase();
    if (q.length === 0) {
      return sessions;
    }
    return sessions.filter((s: ChatSession) => {
      if (s && s.title && s.title.toLowerCase().includes(q)) {
        return true;
      }
      for (const m of (s && s.messages ? s.messages : [])) {
        if (m && m.text && m.text.toLowerCase().includes(q)) {
          return true;
        }
      }
      return false;
    });
  }

  private async ensureInit(): Promise<preferences.Preferences> {
    if (this.prefs === null) {
      throw new Error('ChatSessionService 尚未初始化，请先调用 init(context)');
    }
    return this.prefs;
  }
}
