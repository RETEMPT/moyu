export interface ProjectIconOption { value: string; label: string; }

export const PROJECT_ICONS: ProjectIconOption[] = [
  { value: 'line:folder', label: '文件夹' }, { value: 'line:rocket', label: '计划' },
  { value: 'line:books', label: '课本' }, { value: 'line:bulb', label: '灵感' },
  { value: 'line:science', label: '实验' }, { value: 'line:briefcase', label: '工作' },
  { value: 'line:target', label: '目标' }, { value: 'line:palette', label: '创作' }
];

/** Existing emoji identifiers remain readable without changing saved projects. */
export function projectIcon(value: string = ''): Resource {
  if (value === 'line:rocket' || value === '🚀') { return $r('app.media.ic_project_rocket'); }
  if (value === 'line:books' || value === '📚') { return $r('app.media.ic_project_books'); }
  if (value === 'line:bulb' || value === '💡') { return $r('app.media.ic_project_bulb'); }
  if (value === 'line:science' || value === '🔬') { return $r('app.media.ic_project_science'); }
  if (value === 'line:briefcase' || value === '💼') { return $r('app.media.ic_project_briefcase'); }
  if (value === 'line:target' || value === '🎯') { return $r('app.media.ic_project_target'); }
  if (value === 'line:palette' || value === '🎨') { return $r('app.media.ic_project_palette'); }
  return $r('app.media.ic_folder');
}
