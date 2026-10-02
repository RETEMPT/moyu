@Component
export struct NoteCoverVisual {
  @Prop source: string = 'cover:mist';

  private imageSource(): ResourceStr {
    if (this.source === 'cover:ink') { return $r('app.media.cover_ink'); }
    if (this.source === 'cover:sage') { return $r('app.media.cover_sage'); }
    if (this.source === 'cover:sand') { return $r('app.media.cover_sand'); }
    if (this.source === 'cover:mist' || this.source.length === 0) { return $r('app.media.cover_mist'); }
    return this.source;
  }

  build() {
    Image(this.imageSource()).width('100%').height('100%').objectFit(ImageFit.Cover)
      .accessibilityText('笔记封面')
  }
}
