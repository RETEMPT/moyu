/**
 * 墨语 (FlowMind) 极简设计系统 Token
 * 视觉对标: Notion 模块化排版灰阶 + Obsidian 文件双链与三栏工作台
 * 纯血鸿蒙 ArkTS 强类型约束
 */

export interface ColorPalette {
  canvas: string;          // 主画布底色 (文档阅读背景)
  sidebar: string;         // 侧边栏底色
  surface: string;         // 悬浮卡片、弹窗表面底色
  surfaceSubtle: string;   // 次级背景 (代码块、引用块底色)
  border: string;          // 浅边框线
  borderSubtle: string;    // 次级极细分割线
  inkPrimary: string;      // 主正文文字 (Notion 炭黑 / 柔白)
  inkSecondary: string;    // 次级文字 (副标题、说明)
  inkMuted: string;        // 占位符、弱提示、时间戳
  hoverBg: string;         // 悬浮浅灰色
  activeBg: string;        // 激活选中背景色
  link: string;            // Obsidian 标志性双向链接紫青色
  accent: string;          // 主交互强调色 (按钮、激活图标)
  accentSoft: string;      // 主交互浅底色
  success: string;         // 已保存、已同步
  warning: string;         // 正在保存、待复习
  danger: string;          // 保存失败、删除
}

// 浅色模式: 纯净 Notion 白与柔和石板灰
export const LightColors: ColorPalette = {
  canvas: '#FFFFFF',
  sidebar: '#F7F6F5',
  surface: '#FFFFFF',
  surfaceSubtle: '#F1F1EF',
  border: '#E9E9E7',
  borderSubtle: '#F0F0EE',
  inkPrimary: '#37352F',
  inkSecondary: '#787774',
  inkMuted: '#9B9A97',
  hoverBg: '#EFEFED',
  activeBg: '#E3E2E0',
  link: '#6A5ACD',         // Obsidian 经典紫青色
  accent: '#2383E2',       // Notion 经典交互蓝
  accentSoft: '#E8F1FC',
  success: '#448361',
  warning: '#D9730D',
  danger: '#E03E3E'
};

// 深色模式: 优雅 Obsidian 曜石灰黑
export const DarkColors: ColorPalette = {
  canvas: '#191919',
  sidebar: '#202020',
  surface: '#252525',
  surfaceSubtle: '#2B2B2B',
  border: '#2E2E2E',
  borderSubtle: '#282828',
  inkPrimary: '#D4D4D4',
  inkSecondary: '#9A9A9A',
  inkMuted: '#6B6B6B',
  hoverBg: '#2C2C2C',
  activeBg: '#353535',
  link: '#8B5CF6',         // Obsidian 亮紫色
  accent: '#3B82F6',
  accentSoft: '#1E293B',
  success: '#34D399',
  warning: '#FBBF24',
  danger: '#F87171'
};

export class LayoutTokens {
  static readonly SIDEBAR_WIDTH: number = 260;
  static readonly CONTEXT_PANEL_WIDTH: number = 280;
  static readonly CONTENT_MAX_WIDTH: number = 840;
  static readonly MIN_TOUCH_TARGET: number = 44;

  // 响应式物理断点 (vp)
  static readonly BREAKPOINT_TABLET_LARGE: number = 1200; // 三栏 (侧边栏 + 正文 + 上下文面板)
  static readonly BREAKPOINT_TABLET_MEDIUM: number = 840;  // 双栏 (侧边栏/抽屉 + 正文)
  static readonly BREAKPOINT_PHONE: number = 600;          // 手机紧凑态：收窄留白、抽屉改百分比宽

  // 正文左右留白：宽屏舒展、手机紧凑
  static readonly GUTTER_WIDE: number = 32;
  static readonly GUTTER_COMPACT: number = 16;

  /** 手机紧凑态返回收窄后的左右留白，否则用宽屏留白。 */
  static gutter(isPhone: boolean): number {
    return isPhone ? LayoutTokens.GUTTER_COMPACT : LayoutTokens.GUTTER_WIDE;
  }
}

export class TypographyTokens {
  static readonly TITLE_HERO: number = 28;
  static readonly TITLE_SECTION: number = 20;
  static readonly TITLE_SUB: number = 16;
  static readonly BODY_LARGE: number = 16;
  static readonly BODY_REGULAR: number = 14;
  static readonly CAPTION: number = 12;
  static readonly TINY: number = 10;
  
  static readonly LINE_HEIGHT_BODY: number = 1.6;
}

export class AnimationTokens {
  static readonly DURATION_FAST: number = 180;
  static readonly DURATION_NORMAL: number = 260;
  static readonly SCALE_PRESSED: number = 0.96;
  static readonly SCALE_LIFTED: number = 1.025;
}

export class ResourceTypeTokens {
  static readonly COLOR_MARKDOWN: string = '#4F46E5'; // 经典靛蓝
  static readonly COLOR_CANVAS: string = '#D97706';   // 琥珀橙
  static readonly COLOR_DOC: string = '#059669';      // 森绿
  static readonly COLOR_TASK: string = '#0284C7';     // 晴空蓝
  static readonly COLOR_OTHER: string = '#6B7280';    // 中性灰
}

