/**
 * 墨语 (FlowMind) 语义颜色、布局与交互 Token
 *
 * 设计准则：
 *   1. 正文/次级/提示文字与基础界面背景按 4.5:1 检查，设备字形与其他组合另行验收
 *   2. 触控目标 MIN_TOUCH_TARGET = 44vp，相邻控件保留间距
 *   3. 动效复用 AnimationTokens，遵守减少动态设置
 *   4. 中性层级、细线图标与统一书封
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
  link: string;            // 双向链接与正文链接
  accent: string;          // 主交互强调色 (按钮、激活图标)
  accentSoft: string;      // 主交互浅底色
  onAccent: string;        // 强调色按钮上的文字与图标
  success: string;         // 已保存、已同步、已完成
  warning: string;         // 正在保存、待复习、中优先级
  danger: string;          // 保存失败、删除、高优先级
  tagBg: string;           // 标签徽标通用底色
}

// 浅色模式: 纯净高对比度学习阅读色阶
export const LightColors: ColorPalette = {
  canvas: '#FFFFFF',
  sidebar: '#F7F7F5',
  surface: '#FFFFFF',
  surfaceSubtle: '#F7F7F5',
  border: '#DEDEDA',
  borderSubtle: '#ECECE9',
  inkPrimary: '#37352F',
  inkSecondary: '#65635E',
  inkMuted: '#66645E',
  hoverBg: '#EFEFED',
  activeBg: '#EAEAE7',
  link: '#2567A8',
  accent: '#37352F',
  accentSoft: '#EFEFED',
  onAccent: '#FFFFFF',
  success: '#337653',
  warning: '#95620E',
  danger: '#C43B36',
  tagBg: '#F1F1EF'
};

// 深色模式: 优雅 OLED 曜石黑与深邃暗夜灰阶
export const DarkColors: ColorPalette = {
  canvas: '#191919',
  sidebar: '#202020',
  surface: '#202020',
  surfaceSubtle: '#262626',
  border: '#41413F',
  borderSubtle: '#30302E',
  inkPrimary: '#EFEFEC',
  inkSecondary: '#BCBCB5',
  inkMuted: '#B3B3AC',
  hoverBg: '#2C2C2A',
  activeBg: '#333330',
  link: '#8ABCF0',
  accent: '#EFEFEC',
  accentSoft: '#333330',
  onAccent: '#202020',
  success: '#8AC9A4',
  warning: '#DFBB79',
  danger: '#F3A49E',
  tagBg: '#2C2C2A'
};

export class LayoutTokens {
  static readonly SIDEBAR_WIDTH: number = 328;
  static readonly CONTEXT_PANEL_WIDTH: number = 280;
  static readonly CONTENT_MAX_WIDTH: number = 840;

  // 触控与间距阶梯
  static readonly MIN_TOUCH_TARGET: number = 44;
  static readonly BOTTOM_NAV_HEIGHT: number = 56;

  // 响应式物理断点 (vp)
  static readonly BREAKPOINT_TABLET_LARGE: number = 1200; // 三栏 (侧边栏 + 正文 + 上下文面板)
  static readonly BREAKPOINT_TABLET_MEDIUM: number = 840;  // 双栏 (侧边栏/抽屉 + 正文)
  static readonly BREAKPOINT_PHONE: number = 840;          // 紧凑态：底栏/抽屉；小平板保持可用导航

  // 正文左右留白：宽屏舒展、手机紧凑
  static readonly GUTTER_WIDE: number = 40;
  static readonly GUTTER_COMPACT: number = 16;

  /** 手机紧凑态返回收窄后的左右留白，否则用宽屏留白。 */
  static gutter(isPhone: boolean): number {
    return isPhone ? LayoutTokens.GUTTER_COMPACT : LayoutTokens.GUTTER_WIDE;
  }
}

export class TypographyTokens {
  static readonly TITLE_HERO: number = 34;
  static readonly TITLE_SECTION: number = 22;
  static readonly TITLE_SUB: number = 16;
  static readonly BODY_LARGE: number = 16;
  static readonly BODY_REGULAR: number = 14;
  static readonly CAPTION: number = 12;
  static readonly TINY: number = 11;
  
  static readonly LINE_HEIGHT_BODY: number = 1.6;
  static readonly LINE_HEIGHT_TITLE: number = 1.3;
}

export class AnimationTokens {
  static duration(milliseconds: number): number { return AppStorage.get<boolean>('flowmindReduceMotion') === true ? 0 : milliseconds; }
  static get DURATION_FAST(): number { return AnimationTokens.duration(100); }
  static get DURATION_NORMAL(): number { return AnimationTokens.duration(160); }
  static get DURATION_MEDIUM(): number { return AnimationTokens.duration(200); }
  static get DURATION_SPLIT(): number { return AnimationTokens.duration(200); }
  static get DURATION_PAGE_TRANSITION(): number { return AnimationTokens.duration(200); }
  static get SCALE_PRESSED(): number { return AppStorage.get<boolean>('flowmindReduceMotion') === true ? 1 : 0.995; }
  static get SCALE_MODAL_ENTER(): number { return AppStorage.get<boolean>('flowmindReduceMotion') === true ? 1 : 0.99; }
  static readonly CURVE_STANDARD: Curve = Curve.EaseOut;
}
