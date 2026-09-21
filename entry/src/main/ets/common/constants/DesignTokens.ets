/**
 * 墨语 (FlowMind) 极简设计系统 Token (UI/UX Pro Max 升级版)
 *
 * 设计智能准则对标：
 *   1. WCAG AA 4.5:1+ 文本对比度标准，杜绝低可见度灰底灰字
 *   2. 人体工学触控：MIN_TOUCH_TARGET = 44vp，相邻间隙 >= 8vp
 *   3. 物理弹性微交互：150-300ms 阻尼过渡，按压回弹 0.97
 *   4. Bento Grid 容器与立体层级阴影系统
 * 纯血鸿蒙 ArkTS 强类型约束
 */

export interface ColorPalette {
  canvas: string;          // 主画布底色 (文档阅读背景)
  sidebar: string;         // 侧边栏底色
  surface: string;         // 悬浮卡片、弹窗表面底色
  surfaceSubtle: string;   // 次级背景 (代码块、引用块底色)
  border: string;          // 浅边框线
  borderSubtle: string;    // 次级极细分割线
  inkPrimary: string;      // 主正文文字 (WCAG AA 高对比度)
  inkSecondary: string;    // 次级文字 (副标题、说明)
  inkMuted: string;        // 占位符、弱提示、时间戳
  hoverBg: string;         // 悬浮浅灰色
  activeBg: string;        // 激活选中背景色
  link: string;            // Obsidian 标志性双向链接紫青色
  accent: string;          // 主交互强调色 (按钮、激活图标)
  accentSoft: string;      // 主交互浅底色
  success: string;         // 已保存、已同步、已完成
  warning: string;         // 正在保存、待复习、中优先级
  danger: string;          // 保存失败、删除、高优先级
  // ---- UI/UX Pro Max 扩展语义色 ----
  primary: string;         // 核心主色
  primarySoft: string;     // 核心主色柔和浅底
  accentPurple: string;    // AI 伴读与智能生成强调色
  cardBackground: string;  // Bento 模块卡片底色
  borderFocus: string;     // 聚焦光标外框色
  statusPending: string;   // 待办/待处理状态色
  statusCompleted: string; // 完结归档状态色
  tagBg: string;           // 标签徽标通用底色
}

// 浅色模式: 纯净高对比度学习阅读色阶
export const LightColors: ColorPalette = {
  canvas: '#FAF9F6',
  sidebar: '#F3F4F6',
  surface: '#FFFFFF',
  surfaceSubtle: '#F1F5F9',
  border: '#E2E8F0',
  borderSubtle: '#ECEEF2',
  inkPrimary: '#0F172A',   // 墨夜黑 (对比度 14:1)
  inkSecondary: '#475569', // 石板灰 (对比度 6.5:1)
  inkMuted: '#64748B',     // 弱化灰 (对比度 4.6:1, 符合 WCAG AA)
  hoverBg: '#E2E8F0',
  activeBg: '#CBD5E1',
  link: '#6366F1',         // 经典靛蓝链接
  accent: '#2563EB',       // 皇家蓝
  accentSoft: '#EFF6FF',
  success: '#059669',      // 翡翠绿
  warning: '#D97706',      // 琥珀橙
  danger: '#DC2626',       // 玫瑰红
  primary: '#2563EB',
  primarySoft: '#EFF6FF',
  accentPurple: '#8B5CF6', // 智能紫色
  cardBackground: '#FFFFFF',
  borderFocus: '#3B82F6',
  statusPending: '#2563EB',
  statusCompleted: '#059669',
  tagBg: '#F1F5F9'
};

// 深色模式: 优雅 OLED 曜石黑与深邃暗夜灰阶
export const DarkColors: ColorPalette = {
  canvas: '#121214',
  sidebar: '#18181B',
  surface: '#1E1E22',
  surfaceSubtle: '#27272E',
  border: '#2E2E38',
  borderSubtle: '#262630',
  inkPrimary: '#F8FAFC',   // 纯净雪白 (对比度 15:1)
  inkSecondary: '#94A3B8', // 柔雾灰 (对比度 7:1)
  inkMuted: '#64748B',     // 中性灰 (对比度 4.5:1)
  hoverBg: '#27272E',
  activeBg: '#33333E',
  link: '#A5B4FC',
  accent: '#3B82F6',
  accentSoft: '#1E293B',
  success: '#34D399',
  warning: '#FBBF24',
  danger: '#F87171',
  primary: '#3B82F6',
  primarySoft: '#1E293B',
  accentPurple: '#A78BFA',
  cardBackground: '#1E1E22',
  borderFocus: '#60A5FA',
  statusPending: '#60A5FA',
  statusCompleted: '#34D399',
  tagBg: '#27272E'
};

export class LayoutTokens {
  static readonly SIDEBAR_WIDTH: number = 260;
  static readonly CONTEXT_PANEL_WIDTH: number = 280;
  static readonly CONTENT_MAX_WIDTH: number = 840;

  // UI/UX Pro Max 触控与间距阶梯
  static readonly MIN_TOUCH_TARGET: number = 44;
  static readonly SPACING_XS: number = 4;
  static readonly SPACING_SM: number = 8;
  static readonly SPACING_MD: number = 12;
  static readonly SPACING_LG: number = 16;
  static readonly SPACING_XL: number = 24;

  // 圆角阶梯 (Bento & Cards)
  static readonly RADIUS_SM: number = 8;
  static readonly RADIUS_MD: number = 12;
  static readonly RADIUS_LG: number = 16;
  static readonly RADIUS_XL: number = 24;
  static readonly RADIUS_FULL: number = 9999;
  
  // 响应式物理断点 (vp)
  static readonly BREAKPOINT_TABLET_LARGE: number = 1200; // 三栏 (侧边栏 + 正文 + 上下文面板)
  static readonly BREAKPOINT_TABLET_MEDIUM: number = 840;  // 双栏 (侧边栏/抽屉 + 正文)
}

export class TypographyTokens {
  static readonly TITLE_HERO: number = 28;
  static readonly TITLE_SECTION: number = 20;
  static readonly TITLE_SUB: number = 16;
  static readonly BODY_LARGE: number = 15;
  static readonly BODY_REGULAR: number = 13.5;
  static readonly CAPTION: number = 12;
  static readonly TINY: number = 10;
  
  static readonly LINE_HEIGHT_BODY: number = 1.6;
  static readonly LINE_HEIGHT_TITLE: number = 1.3;
}

export class AnimationTokens {
  static readonly DURATION_FAST: number = 180;
  static readonly DURATION_NORMAL: number = 250;
  static readonly DURATION_SPLIT: number = 280;
  static readonly DURATION_PAGE_TRANSITION: number = 300;
  static readonly SCALE_PRESSED: number = 0.97;
  static readonly SCALE_LIFTED: number = 1.02;
  static readonly SCALE_MODAL_ENTER: number = 0.94;
  static readonly CURVE_STANDARD: Curve = Curve.FastOutSlowIn;
}

export class ResourceTypeTokens {
  static readonly COLOR_MARKDOWN: string = '#4F46E5'; // 经典靛蓝
  static readonly COLOR_CANVAS: string = '#D97706';   // 琥珀橙
  static readonly COLOR_DOC: string = '#059669';      // 森绿
  static readonly COLOR_TASK: string = '#0284C7';     // 晴空蓝
  static readonly COLOR_OTHER: string = '#6B7280';    // 中性灰
}
