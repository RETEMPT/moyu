/** A single type mapping shared by covers, menus and library rows. */
export function documentLabel(type: string): string {
  const kind = type.toLowerCase();
  if (kind === 'pdf' || kind === 'doc' || kind === 'docx' || kind === '资料') { return 'PDF 资料'; }
  if (kind === 'canvas' || kind === 'handwriting' || kind === '白板' || kind === '白纸笔记' || kind === '稿纸') { return '手写笔记'; }
  if (kind === 'task' || kind === '待办') { return '任务记录'; }
  return '文字笔记';
}

export function documentIcon(type: string): Resource {
  const label = documentLabel(type);
  if (label === 'PDF 资料') { return $r('app.media.ic_pdf'); }
  if (label === '手写笔记') { return $r('app.media.ic_pen'); }
  if (label === '任务记录') { return $r('app.media.ic_check'); }
  return $r('app.media.ic_note');
}
