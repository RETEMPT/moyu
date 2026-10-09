import { NoteItem } from '../../common/types/NoteItem';

export class WorkspaceNotePolicy {
  static mutate(note: NoteItem, operation: string, value: string, expectedUpdatedAt: number): NoteItem {
    const next = JSON.parse(JSON.stringify(note)) as NoteItem;
    if (operation === 'rename_note') {
      if (!value.trim() || value.length > 255 || /[\r\n]/.test(value)) { throw new Error('标题需为 1–255 字，不能包含换行'); }
      next.title = value.trim();
    } else if (operation === 'update_note') {
      if ((note.updatedAt || 0) !== expectedUpdatedAt) { throw new Error('笔记已变化，请重新读取并核对，旧版本未覆盖'); }
      if (!['markdown', 'text', 'md'].includes(note.type.toLowerCase()) ||
        ['pdf', 'doc', 'image'].includes(note.sourceType || '')) { throw new Error('仅允许更新文字笔记，原件、PDF 和手写笔迹不会被覆盖'); }
      if (!value.trim() || value.length > 20000) { throw new Error('正文需为 1–20000 字，请分段整理'); }
      next.contentDetail = value; next.previewText = value.slice(0, 100).replace(/[#*`\n]/g, ' ').trim();
    } else if (operation === 'set_note_flag') {
      const parts = value.split(':');
      if (!['favorite', 'pinned'].includes(parts[0]) || !['yes', 'no'].includes(parts[1]) || parts.length !== 2) { throw new Error('收藏/置顶参数无效'); }
      if (parts[0] === 'favorite') { next.favorite = parts[1] === 'yes'; }
      else { next.isPinned = parts[1] === 'yes'; }
    } else { throw new Error('不支持的资料修改'); }
    next.updatedAt = Math.max(Date.now(), (note.updatedAt || 0) + 1); next.updateTime = '刚刚'; return next;
  }
}
