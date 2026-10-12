import { ChatSession } from '../../common/types/ChatSession';

export class ChatHistoryPolicy {
  static preview(session: ChatSession): string {
    for (let i = session.messages.length - 1; i >= 0; i--) {
      const message = session.messages[i];
      if ((message.role === 'user' || message.role === 'assistant') && message.text.trim()) {
        return message.text.replace(/\s+/g, ' ').slice(0, 120);
      }
    }
    return '暂无消息';
  }

  static group(session: ChatSession, now: number): string {
    if (session.pinned) { return '置顶'; }
    const today = new Date(now); today.setHours(0, 0, 0, 0);
    if (session.updatedAt >= today.getTime()) { return '今天'; }
    if (session.updatedAt >= today.getTime() - 6 * 24 * 60 * 60 * 1000) { return '最近七天'; }
    return '更早';
  }

  static filter(sessions: ChatSession[], keyword: string, group: string, now: number): ChatSession[] {
    const terms = keyword.trim().toLowerCase().split(/\s+/).filter((term: string) => term.length > 0).slice(0, 12);
    return sessions.filter((session: ChatSession) => ChatHistoryPolicy.group(session, now) === group &&
      terms.every((term: string) => `${session.title} ${ChatHistoryPolicy.preview(session)}`.toLowerCase().includes(term)))
      .sort((a: ChatSession, b: ChatSession) => b.updatedAt - a.updatedAt);
  }
}
