export interface NoteCoverPreset {
  id: string;
  title: string;
  hint: string;
}

/** Stable identifiers are stored in note metadata; images remain bundled offline. */
export const NOTE_COVER_PRESETS: NoteCoverPreset[] = [
  { id: 'cover:ink', title: '墨线', hint: '深色几何 · 研究与技术' },
  { id: 'cover:mist', title: '雾蓝', hint: '层叠山形 · 灵感与随笔' },
  { id: 'cover:sage', title: '青野', hint: '植物线条 · 学习与记录' },
  { id: 'cover:sand', title: '纸砂', hint: '暖色书页 · 阅读与人文' }
];

export function isCoverPreset(value: string): boolean {
  return NOTE_COVER_PRESETS.some((preset: NoteCoverPreset) => preset.id === value);
}
