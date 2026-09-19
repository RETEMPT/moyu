/**
 * 主题模式定义
 *
 * 应用内可热切换的三种外观模式。注意这与「系统色彩模式」不是一回事：
 *   - SYSTEM：跟随系统深浅色，系统换了应用跟着换
 *   - LIGHT / DARK：把应用钉死在浅色或深色，不再随系统变化
 *
 * 持久化时存的是 ThemeMode 的数值，读取端需容忍越界值（回退为 SYSTEM）。
 */

export enum ThemeMode {
  /** 跟随系统 */
  SYSTEM = 0,
  /** 始终浅色 */
  LIGHT = 1,
  /** 始终深色 */
  DARK = 2
}

/** 外观设置面板里的一行选项 */
export interface ThemeModeOption {
  mode: ThemeMode;
  /** 选项标题 */
  label: string;
  /** 一句话说明，让用户知道选它会发生什么 */
  hint: string;
}

/** 外观面板的选项顺序即此数组顺序 */
export const THEME_MODE_OPTIONS: ThemeModeOption[] = [
  { mode: ThemeMode.SYSTEM, label: '跟随系统', hint: '系统切换深浅色时应用同步跟随' },
  { mode: ThemeMode.LIGHT, label: '浅色', hint: '始终使用 Notion 白，界面固定不随系统变化' },
  { mode: ThemeMode.DARK, label: '深色', hint: '始终使用曜石黑，界面固定不随系统变化' }
];

/** 把持久化读回的任意数值收敛为合法枚举值 */
export function normalizeThemeMode(value: number): ThemeMode {
  if (value === ThemeMode.LIGHT) {
    return ThemeMode.LIGHT;
  }
  if (value === ThemeMode.DARK) {
    return ThemeMode.DARK;
  }
  return ThemeMode.SYSTEM;
}

/** 供界面展示的模式名；未知值按「跟随系统」处理 */
export function themeModeLabel(mode: ThemeMode): string {
  for (let i = 0; i < THEME_MODE_OPTIONS.length; i++) {
    if (THEME_MODE_OPTIONS[i].mode === mode) {
      return THEME_MODE_OPTIONS[i].label;
    }
  }
  return THEME_MODE_OPTIONS[0].label;
}
