import { ColorPalette, LightColors, DarkColors } from '../constants/DesignTokens';

export interface ThemeStyleOption { id: string; label: string; hint: string; }
interface ThemeAccent { id: string; light: string; dark: string; lightSoft: string; darkSoft: string; }
export const THEME_STYLE_KEY: string = 'flowmindThemeStyle';
export const THEME_STYLE_OPTIONS: ThemeStyleOption[] = [
  { id: 'blue', label: '白蓝', hint: '清晰蓝色' },
  { id: 'cyan', label: '白青', hint: '清爽青色' },
  { id: 'jade', label: '白绿', hint: '自然绿色' },
  { id: 'rose', label: '白玫', hint: '柔和玫色' },
  { id: 'sand', label: '暖砂', hint: '温润砂色' },
  { id: 'ink', label: '墨紫', hint: '经典墨紫' },
  { id: 'mono', label: '黑白', hint: '中性纸面，专注内容' },
  { id: 'mist', label: '雾蓝', hint: '柔和蓝色' }
];

// Saved accents remain compatible; document surfaces have one shared definition.
const ACCENTS: ThemeAccent[] = [
  { id: 'blue', light: '#245BBE', dark: '#A2C4FF', lightSoft: '#E6EEFC', darkSoft: '#293F63' },
  { id: 'cyan', light: '#08777E', dark: '#84D4D7', lightSoft: '#E0F4F3', darkSoft: '#1D464A' },
  { id: 'jade', light: '#247654', dark: '#93D5B2', lightSoft: '#E7F3ED', darkSoft: '#25463C' },
  { id: 'rose', light: '#A23C66', dark: '#EDABC6', lightSoft: '#F9E9F0', darkSoft: '#4A2B3C' },
  { id: 'sand', light: '#8A602F', dark: '#E1C197', lightSoft: '#F7EFE4', darkSoft: '#453A2B' },
  { id: 'ink', light: '#6842E3', dark: '#BBA4FF', lightSoft: '#EEE8FC', darkSoft: '#382A52' },
  { id: 'mist', light: '#2C629C', dark: '#A6CFFC', lightSoft: '#DFEBF8', darkSoft: '#2B425F' }
];

export function normalizeThemeStyle(value: string): string {
  return THEME_STYLE_OPTIONS.some((option: ThemeStyleOption) => option.id === value) ? value : 'mono';
}

export function paletteForStyle(isDark: boolean, style: string): ColorPalette {
  const base: ColorPalette = isDark ? DarkColors : LightColors;
  const accent = ACCENTS.find((item: ThemeAccent) => item.id === style);
  if (!accent) { return base; }
  return {
    canvas: base.canvas, sidebar: base.sidebar, surface: base.surface, surfaceSubtle: base.surfaceSubtle,
    border: base.border, borderSubtle: base.borderSubtle,
    inkPrimary: base.inkPrimary, inkSecondary: base.inkSecondary, inkMuted: base.inkMuted,
    hoverBg: base.hoverBg, activeBg: base.activeBg, tagBg: base.tagBg,
    link: isDark ? accent.dark : accent.light, accent: isDark ? accent.dark : accent.light,
    accentSoft: isDark ? accent.darkSoft : accent.lightSoft, onAccent: isDark ? '#202020' : '#FFFFFF',
    success: base.success, warning: base.warning, danger: base.danger
  };
}
