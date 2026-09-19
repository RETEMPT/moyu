/**
 * 墨语 (FlowMind) 主题调色板入口
 *
 * 职责：把「系统色彩模式」统一映射为 DesignTokens 中的 ColorPalette，
 * 让视图层只关心 palette.canvas / palette.inkPrimary 这类语义色，
 * 不再散落硬编码色值。
 *
 * 数据流：
 *   EntryAbility.onConfigurationUpdate -> ThemeHelper.publish(colorMode)
 *   -> AppStorage('flowmindDarkMode') -> 组件 @StorageProp 触发重绘
 *   -> ThemeHelper.paletteOfDark(isDark)
 *
 * 说明：AppStorage 中保存的是布尔值而非 ConfigurationConstant.ColorMode 枚举，
 * 避免 ArkTS 枚举类型与 ArkUI 状态装饰器之间的类型不兼容问题。
 */
import { ConfigurationConstant } from '@kit.AbilityKit';
import { ColorPalette, DarkColors, LightColors } from '../constants/DesignTokens';

/**
 * AppStorage 中承载「是否深色模式」的键名。
 * 注意：ArkUI 的 @StorageProp / @StorageLink 装饰器只接受字符串字面量，
 * 组件内需书写 'flowmindDarkMode'，本常量用于非装饰器的读写入口。
 */
export const DARK_MODE_KEY: string = 'flowmindDarkMode';

export class ThemeHelper {
  /** 系统色彩模式是否为深色（未设置 / 未定义时按浅色处理） */
  static isDark(colorMode: ConfigurationConstant.ColorMode | undefined): boolean {
    return colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  /** 系统色彩模式 -> 调色板 */
  static paletteOf(colorMode: ConfigurationConstant.ColorMode | undefined): ColorPalette {
    return ThemeHelper.paletteOfDark(ThemeHelper.isDark(colorMode));
  }

  /** 布尔深色标记 -> 调色板（视图层的常用入口） */
  static paletteOfDark(isDark: boolean): ColorPalette {
    return isDark ? DarkColors : LightColors;
  }

  /** 由 Ability 层写入系统色彩模式，驱动全局视图重绘 */
  static publish(colorMode: ConfigurationConstant.ColorMode | undefined): void {
    AppStorage.setOrCreate<boolean>(DARK_MODE_KEY, ThemeHelper.isDark(colorMode));
  }

  /** 读取当前是否为深色模式，未初始化时回退为浅色 */
  static currentIsDark(): boolean {
    const stored: boolean | undefined = AppStorage.get<boolean>(DARK_MODE_KEY);
    if (stored === undefined) {
      return false;
    }
    return stored;
  }

  /** 非响应式地取当前调色板，用于一次性读取场景 */
  static currentPalette(): ColorPalette {
    return ThemeHelper.paletteOfDark(ThemeHelper.currentIsDark());
  }
}
