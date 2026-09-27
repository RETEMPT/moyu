/**
 * 对话会话持久化服务
 *
 * 与 NoteStorageService 同范式：Preferences JSON 快照。
 * 每次会话变更立即落盘（消息量可控，不拆文件）。
 */
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ChatSession } from '../../common/types/ChatSession';

const PREFERENCES_NAME: string = 'flowmind_chat';
const SESSIONS_KEY: string = 'sessions';
const MAX_SESSIONS: number = 200;

export class ChatSessionService {
  private static instance: ChatSessionService | null = null;
  private prefs: preferences.Preferences | null = null;

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
    const prefs: preferences.Preferences = await this.ensureInit();
    const raw = await prefs.get(SESSIONS_KEY, '[]');
    try {
      const parsed: ChatSession[] = JSON.parse(raw as string) as ChatSession[];
      if (!Array.isArray(parsed)) {
        return [];
      }
      // updatedAt 倒序
      parsed.sort((a: ChatSession, b: ChatSession) => b.updatedAt - a.updatedAt);
      return parsed;
    } catch {
      return [];
    }
  }

  /** 保存全部会话 */
  async saveSessions(sessions: ChatSession[]): Promise<void> {
    const prefs: preferences.Preferences = await this.ensureInit();
    // 限制数量，优先保留置顶
    let trimmed: ChatSession[] = [...sessions];
    if (trimmed.length > MAX_SESSIONS) {
      const pinned: ChatSession[] = trimmed.filter((s: ChatSession) => s.pinned);
      const unpinned: ChatSession[] = trimmed.filter((s: ChatSession) => !s.pinned)
        .sort((a: ChatSession, b: ChatSession) => b.updatedAt - a.updatedAt);
      const keep: ChatSession[] = [...pinned, ...unpinned.slice(0, MAX_SESSIONS - pinned.length)];
      trimmed = keep;
    }
    await prefs.put(SESSIONS_KEY, JSON.stringify(trimmed));
    await prefs.flush();
  }

  /** upsert 单个会话 */
  async saveSession(session: ChatSession): Promise<void> {
    const sessions: ChatSession[] = await this.loadSessions();
    let found: boolean = false;
    for (let i = 0; i < sessions.length; i++) {
      if (sessions[i].id === session.id) {
        sessions[i] = session;
        found = true;
        break;
      }
    }
    if (!found) {
      sessions.unshift(session);
    }
    await this.saveSessions(sessions);
  }

  /** 删除会话 */
  async deleteSession(id: string): Promise<void> {
    const sessions: ChatSession[] = await this.loadSessions();
    const filtered: ChatSession[] = sessions.filter((s: ChatSession) => s.id !== id);
    await this.saveSessions(filtered);
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
      if (s.title.toLowerCase().includes(q)) {
        return true;
      }
      for (const m of s.messages) {
        if (m.text.toLowerCase().includes(q)) {
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
