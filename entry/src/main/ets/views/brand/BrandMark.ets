/**
 * 应用内品牌标
 *
 * 用应用图标本身作为应用内的品牌标识，并跟随主题热切换：
 * 浅色用白底墨笔版，深色用曜石黑霓虹版。
 *
 * 为什么是「两张图二选一」而不是一张图交给资源限定符自动解析：
 * theme 切换时 palette 是同步生效的，而资源限定符的重新解析时机不在应用掌控内。
 * 显式按 @StorageProp 的布尔值切 Image 源，重绘是确定性的，切主题不掉帧、不闪烁。
 *
 * resources/base/media/brand_mark_light.png 与 brand_mark_dark.png 由
 * tools/generate-icons.mjs 从 design/app_mark_*.svg 生成。
 */
import { ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';

@Component
export struct BrandMark {
  /**
   * 显示边长（vp）。品牌标是正方形，宽高共用此值。
   * 注意不能叫 size —— CustomComponent 基类上已有 size 属性，同名会类型冲突。
   */
  @Prop markSize: number = 22;

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  build() {
    Image(this.isDarkMode ? $r('app.media.brand_mark_dark') : $r('app.media.brand_mark_light'))
      .width(this.markSize)
      .height(this.markSize)
      .draggable(false)
      .interpolation(ImageInterpolation.High)
  }
}

/**
 * 品牌标 + 工作区名的横向组合，侧边栏与首页共用，
 * 避免两处各写一遍同样的排版。
 */
@Component
export struct BrandLockup {
  @Prop markSize: number = 22;
  @Prop label: string = '墨语 · 第二大脑';
  @Prop fontSize: number = 14;
  @Prop showLabel: boolean = true;

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  build() {
    Row({ space: 8 }) {
      BrandMark({ markSize: this.markSize })
      if (this.showLabel) {
        Text(this.label)
          .fontSize(this.fontSize)
          .fontColor(this.palette().inkPrimary)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
    }
    .alignItems(VerticalAlign.Center)
  }
}
