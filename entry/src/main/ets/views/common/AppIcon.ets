/** Theme-tinted SVG; size is visual only, its parent owns the touch target. */
@Component
export struct AppIcon {
  @Prop source: Resource = $r('app.media.ic_note');
  @Prop iconSize: number = 20;
  @Prop tint: ResourceColor = '#6D4AFF';

  build() {
    Image(this.source)
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Contain)
      .fillColor(this.tint)
      .draggable(false)
      .accessibilityLevel('no')
      .hitTestBehavior(HitTestMode.None)
  }
}
