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
