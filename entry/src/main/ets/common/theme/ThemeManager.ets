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
 *   3. 桌面图标 —— 调 bundleManager.setAlternateIcon('theme_dark' | '')，
 *      切换 app.json5 里 alternateIcons 声明的备用图标。
 *
 * 主题选择存在 Preferences 的 'flowmind_theme' / 'themeMode' 下，
 * 在 EntryAbility.onCreate 里于首帧渲染之前 restore()，避免浅色闪一下再变深色。
 *
 * 能力边界（已在真机/模拟器上实测）：
 *   setAlternateIcon 自 API 26 起提供。本项目 compatibleSdkVersion 为 24，
 *   因此低版本设备上这一步会被 deviceInfo.sdkApiVersion 拦下并静默跳过 —— 图标
 *   不会跟着变，但应用内配色照常切换，不会崩。
 */
import { bundleManager, common, ConfigurationConstant } from '@kit.AbilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { DARK_MODE_KEY } from './ThemeHelper';
import { normalizeThemeMode, ThemeMode } from './ThemeMode';

/** Preferences 实例名与键名 */
const PREFERENCES_NAME: string = 'flowmind_theme';
const THEME_MODE_KEY: string = 'themeMode';

/** app.json5 中 alternateIcons[].name，深色备用图标 */
const DARK_ALTERNATE_ICON: string = 'theme_dark';

/** setAlternateIcon / getAlternateIcons 起始可用版本 */
const ALTERNATE_ICON_MIN_API: number = 26;

export class ThemeManager {
  /** 用户当前选择的模式，未 restore 前按「跟随系统」处理 */
  private static mode: ThemeMode = ThemeMode.SYSTEM;
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
  /** 备用图标能力是否可用，避免每次切换都重复判断 */
  private static alternateIconSupported: boolean = deviceInfo.sdkApiVersion >= ALTERNATE_ICON_MIN_API;
  /**
   * 正在执行 setColorMode 的标记。setColorMode 会同步回调 onConfigurationUpdate，
   * 用它把那次回声与「系统真的换肤了」区分开，避免无限递归。
   */
  private static applyingColorMode: boolean = false;

  /** 当前模式（同步读取，供界面展示选中态） */
  static currentMode(): ThemeMode {
    return ThemeManager.mode;
  }

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
    } catch (error) {
      console.error(`主题偏好读取失败，回退为跟随系统: ${JSON.stringify(error)}`);
      ThemeManager.mode = ThemeMode.SYSTEM;
    }
    ThemeManager.apply(true);
  }

  /** 用户在设置里切换模式：立即生效并落盘。无需传 Context，restore 时已缓存。 */
  static async setMode(mode: ThemeMode): Promise<void> {
    if (ThemeManager.mode === mode) {
      return;
    }
    ThemeManager.mode = mode;
    ThemeManager.apply(true);
    if (ThemeManager.store === null) {
      console.error('主题偏好尚未初始化，本次切换不会被持久化');
      return;
    }
    try {
      await ThemeManager.store.put(THEME_MODE_KEY, mode as number);
      await ThemeManager.store.flush();
    } catch (error) {
      console.error(`主题偏好写入失败: ${JSON.stringify(error)}`);
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

  /** 把当前模式落到三处：AppStorage 调色板、应用色彩模式、桌面图标 */
  private static apply(syncIcon: boolean): void {
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

    // 3) 桌面图标
    if (syncIcon) {
      ThemeManager.syncLauncherIcon(isDark);
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

  /**
   * 让桌面图标与当前主题一致。
   *
   * 先查 getAlternateIcons() 的 enabled 标记，只有确实需要变时才调用
   * setAlternateIcon —— 避免每次冷启动都去打扰启动器。
   */
  private static async syncLauncherIcon(isDark: boolean): Promise<void> {
    if (!ThemeManager.alternateIconSupported) {
      console.info(`当前 API ${deviceInfo.sdkApiVersion} 不支持备用图标，跳过桌面图标切换`);
      return;
    }
    try {
      const icons: bundleManager.AlternateIconInfo[] = await bundleManager.getAlternateIcons();
      let darkEnabled: boolean = false;
      for (let i = 0; i < icons.length; i++) {
        if (icons[i].iconName === DARK_ALTERNATE_ICON && icons[i].enabled) {
          darkEnabled = true;
          break;
        }
      }
      if (darkEnabled === isDark) {
        return;
      }
      // 传空串即取消备用图标，恢复 app.json5 里的默认图标
      await bundleManager.setAlternateIcon(isDark ? DARK_ALTERNATE_ICON : '');
      console.info(`桌面图标已切换为${isDark ? '深色' : '默认'}`);
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      console.error(`桌面图标切换失败 (code=${failure.code}): ${failure.message}`);
    }
  }
}
