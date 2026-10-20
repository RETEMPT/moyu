/**
 * 墨语 (FlowMind) 主题管理器
 *
 * 职责：把「用户在设置里选的模式」变成三件同时发生的事，并持久化这个选择。
 *
 *   1. 调色板热切换 —— 写 AppStorage('flowmindDarkMode')，
 *      13 个视图组件通过 @StorageProp 立刻重绘，无需重启、无需重建 Ability。
 *   2. 应用资源限定符 —— 调 applicationContext.setColorMode(...)，
 *      让 $r('app.color.x')、系统弹窗、状态栏等跟随同一套深浅色。
 *      传 COLOR_MODE_NOT_SET 表示「跟随系统」。
 *
 * 桌面图标不跟随主题切换：华为审核指南 1.20 要求商店图标与终端显示图标一致，
 * 备用图标会让深色模式下的终端图标与商店素材不符，故始终使用默认图标。
 *
 * 主题选择存在 Preferences 的 'flowmind_theme' / 'themeMode' 下，
 * 在 EntryAbility.onCreate 里于首帧渲染之前 restore()，避免浅色闪一下再变深色。
 */
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { DARK_MODE_KEY } from './ThemeHelper';
import { normalizeThemeMode, ThemeMode } from './ThemeMode';
import { normalizeThemeStyle, THEME_STYLE_KEY } from './ThemeStyle';

/** Preferences 实例名与键名 */
const PREFERENCES_NAME: string = 'flowmind_theme';
const THEME_MODE_KEY: string = 'themeMode';

export class ThemeManager {
  /** 用户当前选择的模式，未 restore 前按「跟随系统」处理 */
  private static mode: ThemeMode = ThemeMode.SYSTEM;
  private static style: string = 'mono';
  private static writes: Promise<void> = Promise.resolve();
  /** 系统当前的深浅色，用于解析 ThemeMode.SYSTEM */
  private static systemIsDark: boolean = false;
  /** 持久化句柄，restore 成功后才可用 */
  private static store: preferences.Preferences | null = null;
  /**
   * 应用级 Context。缓存的是 ApplicationContext 而不是 UIAbilityContext ——
   * 前者与进程同生命周期，静态持有不会泄漏 Ability；后者会在 Ability 销毁后残留。
   * setColorMode 本来就挂在 ApplicationContext 上，用它足够了。
   */
  private static appContext: common.ApplicationContext | null = null;
  /**
   * 正在执行 setColorMode 的标记。setColorMode 会同步回调 onConfigurationUpdate，
   * 用它把那次回声与「系统真的换肤了」区分开，避免无限递归。
   */
  private static applyingColorMode: boolean = false;

  /** 当前模式（同步读取，供界面展示选中态） */
  static currentMode(): ThemeMode {
    return ThemeManager.mode;
  }

  static currentStyle(): string { return ThemeManager.style; }

  /** 当前是否应当呈现深色 */
  static isDark(): boolean {
    return ThemeManager.resolveIsDark(ThemeManager.mode);
  }

  /**
   * 读取持久化的主题选择并立即生效。
   * 必须在首帧渲染前调用（EntryAbility.onCreate），否则会看到一次浅色闪烁。
   *
   * 系统色彩模式由调用方传入而不是从 context.config 读：common.Context 上没有
   * config 字段，只有 UIAbilityContext 才有；传参可以让本类不依赖具体 Context 子类。
   */
  static async restore(context: common.Context, colorMode: ConfigurationConstant.ColorMode | undefined): Promise<void> {
    ThemeManager.appContext = context.getApplicationContext();
    ThemeManager.systemIsDark = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    try {
      ThemeManager.store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      const stored: number = await ThemeManager.store.get(THEME_MODE_KEY, ThemeMode.SYSTEM as number) as number;
      ThemeManager.mode = normalizeThemeMode(stored);
      ThemeManager.style = normalizeThemeStyle(await ThemeManager.store.get('themeStyle', 'mono') as string);
      const reduce = await ThemeManager.store.get('reduceMotion', false);
      AppStorage.setOrCreate<boolean>('flowmindReduceMotion', reduce === true);
    } catch (error) {
      console.error(`主题偏好读取失败，回退为跟随系统: ${JSON.stringify(error)}`);
      ThemeManager.mode = ThemeMode.SYSTEM;
      ThemeManager.style = 'mono';
      AppStorage.setOrCreate<boolean>('flowmindReduceMotion', false);
    }
    AppStorage.setOrCreate<string>(THEME_STYLE_KEY, ThemeManager.style);
    ThemeManager.apply();
  }

  /** 用户在设置里切换模式：立即生效并落盘。无需传 Context，restore 时已缓存。 */
  static async setMode(mode: ThemeMode): Promise<void> {
    await ThemeManager.enqueue(async () => {
      const next = normalizeThemeMode(mode);
      await ThemeManager.persist(THEME_MODE_KEY, next as number, ThemeManager.mode as number);
      ThemeManager.mode = next;
      ThemeManager.apply();
    });
  }

  static async setStyle(style: string): Promise<void> {
    await ThemeManager.enqueue(async () => {
      const next = normalizeThemeStyle(style);
      await ThemeManager.persist('themeStyle', next, ThemeManager.style);
      ThemeManager.style = next;
      AppStorage.setOrCreate<string>(THEME_STYLE_KEY, next);
    });
  }

  static async setReduceMotion(value: boolean): Promise<void> {
    await ThemeManager.enqueue(async () => {
      await ThemeManager.persist('reduceMotion', value, AppStorage.get<boolean>('flowmindReduceMotion') === true);
      AppStorage.setOrCreate<boolean>('flowmindReduceMotion', value);
    });
  }

  private static enqueue(action: () => Promise<void>): Promise<void> {
    const work = ThemeManager.writes.then(action);
    ThemeManager.writes = work.catch(() => {});
    return work;
  }

  private static async persist(key: string, value: preferences.ValueType, previous: preferences.ValueType): Promise<void> {
    if (ThemeManager.store === null) { throw new Error('外观设置尚未初始化'); }
    try {
      await ThemeManager.store.put(key, value);
      await ThemeManager.store.flush();
    } catch {
      // 恢复 Preferences 的内存值，避免下一次 flush 把失败的设置一并落盘。
      try { await ThemeManager.store.put(key, previous); } catch { /* 下一次成功写入仍可重试 */ }
      throw new Error('外观设置保存失败，请重试');
    }
  }

  /**
   * 系统深浅色变化时调用（EntryAbility.onConfigurationUpdate）。
   *
   * 这里有本模块最要命的一个坑：applicationContext.setColorMode() 会**同步**回调
   * onConfigurationUpdate。如果不加判断地在这里再调 apply()，就会形成
   *     apply -> setColorMode -> onConfigurationUpdate -> onSystemColorModeChanged -> apply
   * 的无限递归，真机/模拟器上的表现是 RangeError: Stack overflow! 直接崩。
   * 所以此处只更新调色板，任何情况下都不再回调 setColorMode。
   */
  static onSystemColorModeChanged(colorMode: ConfigurationConstant.ColorMode | undefined): void {
    const reportedDark: boolean = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;

    // 我们自己刚设置过色彩模式，这是回声而不是系统真的变了
    if (ThemeManager.applyingColorMode) {
      return;
    }
    // 即便回调改成异步，固定模式下的上报值必然等于我们设置的值，同样按回声丢弃，
    // 否则 systemIsDark 会被自己的覆盖值污染，之后切回「跟随系统」时会取到错的系统态。
    if (ThemeManager.mode === ThemeMode.DARK && reportedDark) {
      return;
    }
    if (ThemeManager.mode === ThemeMode.LIGHT && !reportedDark) {
      return;
    }

    ThemeManager.systemIsDark = reportedDark;
    if (ThemeManager.mode === ThemeMode.SYSTEM) {
      AppStorage.setOrCreate<boolean>(DARK_MODE_KEY, reportedDark);
    }
  }

  /** 模式 -> 是否深色 */
  private static resolveIsDark(mode: ThemeMode): boolean {
    if (mode === ThemeMode.DARK) {
      return true;
    }
    if (mode === ThemeMode.LIGHT) {
      return false;
    }
    return ThemeManager.systemIsDark;
  }

  /** 把当前模式落到两处：AppStorage 调色板、应用色彩模式 */
  private static apply(): void {
    const isDark: boolean = ThemeManager.resolveIsDark(ThemeManager.mode);

    // 1) 视图层调色板：这一步决定界面是否立刻变色
    AppStorage.setOrCreate<boolean>(DARK_MODE_KEY, isDark);

    // 2) 应用色彩模式：影响资源限定符与系统绘制的界面元素
    if (ThemeManager.appContext !== null) {
      ThemeManager.applyingColorMode = true;
      try {
        ThemeManager.appContext.setColorMode(ThemeManager.colorModeOf(ThemeManager.mode));
      } catch (error) {
        console.error(`setColorMode 失败: ${JSON.stringify(error)}`);
      } finally {
        ThemeManager.applyingColorMode = false;
      }
    }
  }

  private static colorModeOf(mode: ThemeMode): ConfigurationConstant.ColorMode {
    if (mode === ThemeMode.DARK) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    if (mode === ThemeMode.LIGHT) {
      return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    }
    return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  }
}
