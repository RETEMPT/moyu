/**
 * 墨语 (FlowMind) 语义颜色、布局与交互 Token
 *
 * 设计准则：
 *   1. 正文/次级/提示文字与基础界面背景按 4.5:1 检查，设备字形与其他组合另行验收
 *   2. 触控目标 MIN_TOUCH_TARGET = 44vp，相邻控件保留间距
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
  onAccent: string;        // 强调色按钮上的文字与图标
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
  canvas: '#F8F7FB',
  sidebar: '#F1EFF6',
  surface: '#FFFFFF',
  surfaceSubtle: '#F1EFF6',
  border: '#DDD9E7',
  borderSubtle: '#E9E6EF',
  inkPrimary: '#242033',
  inkSecondary: '#575267',
  inkMuted: '#625C70',
  hoverBg: '#EAE5F4',
  activeBg: '#E9E1FC',
  link: '#6342D9',
  accent: '#6842E3',
  accentSoft: '#EEE8FC',
  onAccent: '#FFFFFF',
  success: '#059669',      // 翡翠绿
  warning: '#D97706',      // 琥珀橙
  danger: '#DC2626',       // 玫瑰红
  primary: '#6842E3',
  primarySoft: '#EEE8FC',
  accentPurple: '#6842E3',
  cardBackground: '#FFFFFF',
  borderFocus: '#8566E9',
  statusPending: '#6842E3',
  statusCompleted: '#059669',
  tagBg: '#F1EFF6'
};

// 深色模式: 优雅 OLED 曜石黑与深邃暗夜灰阶
export const DarkColors: ColorPalette = {
  canvas: '#15131C',
  sidebar: '#1B1824',
  surface: '#221E2D',
  surfaceSubtle: '#2C2638',
  border: '#40374E',
  borderSubtle: '#332D40',
  inkPrimary: '#F8FAFC',   // 纯净雪白 (对比度 15:1)
  inkSecondary: '#B8B0C7',
  inkMuted: '#A49AB6',
  hoverBg: '#352E43',
  activeBg: '#3B2D57',
  link: '#C0ADFF',
  accent: '#BBA4FF',
  accentSoft: '#382A52',
  onAccent: '#21172F',
  success: '#34D399',
  warning: '#FBBF24',
  danger: '#F87171',
  primary: '#BBA4FF',
  primarySoft: '#382A52',
  accentPurple: '#BBA4FF',
  cardBackground: '#221E2D',
  borderFocus: '#C8B6FF',
  statusPending: '#BBA4FF',
  statusCompleted: '#34D399',
  tagBg: '#2C2638'
};

export class LayoutTokens {
  static readonly SIDEBAR_WIDTH: number = 260;
  static readonly CONTEXT_PANEL_WIDTH: number = 280;
  static readonly CONTENT_MAX_WIDTH: number = 840;

  // UI/UX Pro Max 触控与间距阶梯
  static readonly MIN_TOUCH_TARGET: number = 44;
  static readonly BOTTOM_NAV_HEIGHT: number = 56;

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
  static readonly BODY_LARGE: number = 15;
  static readonly BODY_REGULAR: number = 13.5;
  static readonly CAPTION: number = 12;
  static readonly TINY: number = 10;
  
  static readonly LINE_HEIGHT_BODY: number = 1.6;
  static readonly LINE_HEIGHT_TITLE: number = 1.3;
}

export class AnimationTokens {
  static duration(milliseconds: number): number { return AppStorage.get<boolean>('flowmindReduceMotion') === true ? 0 : milliseconds; }
  static get DURATION_FAST(): number { return AnimationTokens.duration(180); }
  static get DURATION_NORMAL(): number { return AnimationTokens.duration(250); }
  static get DURATION_SPLIT(): number { return AnimationTokens.duration(250); }
  static get DURATION_PAGE_TRANSITION(): number { return AnimationTokens.duration(250); }
  static get SCALE_PRESSED(): number { return AppStorage.get<boolean>('flowmindReduceMotion') === true ? 1 : 0.97; }
  static get SCALE_LIFTED(): number { return AppStorage.get<boolean>('flowmindReduceMotion') === true ? 1 : 1.02; }
  static get SCALE_MODAL_ENTER(): number { return AppStorage.get<boolean>('flowmindReduceMotion') === true ? 1 : 0.94; }
  static readonly CURVE_STANDARD: Curve = Curve.EaseInOut;
}

export class ResourceTypeTokens {
  static readonly COLOR_MARKDOWN: string = '#4F46E5'; // 经典靛蓝
  static readonly COLOR_CANVAS: string = '#D97706';   // 琥珀橙
  static readonly COLOR_DOC: string = '#059669';      // 森绿
  static readonly COLOR_TASK: string = '#0284C7';     // 晴空蓝
  static readonly COLOR_OTHER: string = '#6B7280';    // 中性灰
}
