/** Shared paper grid / committed ink / live ink layers for whiteboards, PDF and raster annotation. */
@Component
export struct InkCanvasSurface {
  drawingContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  liveContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  paperContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  @Prop drawPaper: boolean = false;
  @Prop contentReady: boolean = true;
  @Prop interactive: boolean = true;
  @Prop liveOpacity: number = 1;
  onPaintReady: () => void = () => {};
  onSizeChanged: (width: number, height: number) => void = () => {};
  onInput: (event: TouchEvent) => void = () => {};
  onBlankTap: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.drawPaper) {
        Canvas(this.paperContext).width('100%').height('100%').hitTestBehavior(HitTestMode.None)
      }
      Canvas(this.drawingContext).width('100%').height('100%').opacity(this.contentReady ? 1 : 0).hitTestBehavior(HitTestMode.None)
      Canvas(this.liveContext).width('100%').height('100%').opacity(this.contentReady ? this.liveOpacity : 0)
        .hitTestBehavior(this.interactive ? HitTestMode.Transparent : HitTestMode.None)
        .onReady(() => this.onPaintReady())
        .onAreaChange((_before: Area, after: Area) => this.onSizeChanged(Number(after.width), Number(after.height)))
        .onClick(() => this.onBlankTap())
    }.width('100%').height('100%').clip(true)
      .hitTestBehavior(this.interactive ? HitTestMode.Default : HitTestMode.None)
      .onTouch((event: TouchEvent) => this.onInput(event))
  }
}
