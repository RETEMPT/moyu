import { ChatSession, StoredMessage, ChatCitation } from '../../common/types/ChatSession';

/** 隔离旧版本与损坏字段，单条坏记录不会清空整份对话历史。 */
export class ChatSessionSanitizer {
  static normalize(sessions: ChatSession[]): ChatSession[] {
    const result: ChatSession[] = [];
    if (!Array.isArray(sessions)) { return result; }
    for (const session of sessions) {
      if (!session || typeof session !== 'object' || typeof session.id !== 'string' || session.id.length === 0) { continue; }
      const messages: StoredMessage[] = [];
      for (const message of (Array.isArray(session.messages) ? session.messages : [])) {
        if (!message || typeof message !== 'object') { continue; }
        const roles: string[] = ['user', 'assistant', 'system', 'tool'];
        const safe: StoredMessage = { id: typeof message.id === 'string' && message.id.length > 0 ? message.id : `${session.id}-message-${messages.length}`,
          role: roles.includes(message.role) ? message.role : 'assistant',
          text: typeof message.text === 'string' ? message.text : '',
          createdAt: typeof message.createdAt === 'number' ? message.createdAt : 0,
          reasoningContent: typeof message.reasoningContent === 'string' ? message.reasoningContent : undefined,
          reasoningDurationMs: typeof message.reasoningDurationMs === 'number' ? message.reasoningDurationMs : undefined,
          reasoningFolded: message.reasoningFolded !== false, streaming: false,
          formula: typeof message.formula === 'string' ? message.formula : undefined,
          bullets: Array.isArray(message.bullets) ? message.bullets.filter((s: string) => typeof s === 'string') : [],
          citations: ChatSessionSanitizer.citations(message.citations || []),
          agentLayer: message.agentLayer, modelProfileId: typeof message.modelProfileId === 'string' ? message.modelProfileId : undefined,
          error: typeof message.error === 'string' ? message.error : undefined,
          proposalAppliedIds: Array.isArray(message.proposalAppliedIds) ? message.proposalAppliedIds.filter((id: string) => typeof id === 'string') : [],
          proposalStatus: ['pending', 'accepted', 'dismissed'].includes(message.proposalStatus || '') ? message.proposalStatus : undefined };
        messages.push(safe);
      }
      const mode = session.agentMode;
      const normalized: ChatSession = { id: session.id, title: typeof session.title === 'string' ? session.title : '新对话',
        pinned: session.pinned === true, agentMode: mode === 'L1' || mode === 'L2' || mode === 'L3' ? mode : 'auto',
        messages: messages, createdAt: typeof session.createdAt === 'number' ? session.createdAt : 0,
        updatedAt: typeof session.updatedAt === 'number' ? session.updatedAt : 0 };
      result.push(normalized);
    }
    return result.sort((a: ChatSession, b: ChatSession) => b.updatedAt - a.updatedAt);
  }

  private static citations(items: ChatCitation[]): ChatCitation[] {
    if (!Array.isArray(items)) { return []; }
    return items.filter((c: ChatCitation) => c !== null && typeof c === 'object' &&
      typeof c.noteId === 'string' && typeof c.noteTitle === 'string' && typeof c.chunkText === 'string')
      .map((c: ChatCitation) => {
        const citation: ChatCitation = { noteId: c.noteId, noteTitle: c.noteTitle, chunkText: c.chunkText,
          headingPath: typeof c.headingPath === 'string' ? c.headingPath : '',
          score: typeof c.score === 'number' ? c.score : 0,
          pageNumber: Number.isInteger(c.pageNumber) && (c.pageNumber || 0) > 0 ? c.pageNumber : undefined,
          startLine: Number.isInteger(c.startLine) && (c.startLine || 0) > 0 ? c.startLine : undefined };
        return citation;
      });
  }
}
