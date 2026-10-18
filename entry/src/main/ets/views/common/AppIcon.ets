import { ColorMetrics } from '@kit.ArkUI';
import { drawing } from '@kit.ArkGraphics2D';

/** Recolor rendered alpha, preserving hollow SVG strokes and their transparent interiors. */
@Component
export struct AppIcon {
  @Prop source: Resource = $r('app.media.ic_note');
  @Prop iconSize: number = 20;
  @Prop tint: ResourceColor = '#65635E';

  private tintFilter(): drawing.ColorFilter {
    const color = ColorMetrics.resourceColor(this.tint);
    return drawing.ColorFilter.createBlendModeColorFilter({ red: color.red, green: color.green, blue: color.blue,
      alpha: color.alpha }, drawing.BlendMode.SRC_IN);
  }

  build() {
    Image(this.source)
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .supportSvg2(true)
      .colorFilter(this.tintFilter())
      .draggable(false)
      .accessibilityLevel('no')
      .hitTestBehavior(HitTestMode.None)
  }
}
