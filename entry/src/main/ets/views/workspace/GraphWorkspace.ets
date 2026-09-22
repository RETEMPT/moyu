/**
 * 知识图谱视图（功能9）
 *
 * Canvas 绘制由 linkGraph（真实 [[双链]] 解析结果）生成的网络图：
 * 已解析引用连成实线节点，未解析概念显示为空心虚节点。
 * 圆形布局 + 缩放控件，点击节点直接打开对应笔记；下方保留可追溯的引用列表。
 */
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { Backlink, LinkGraph, UnresolvedLink } from '../../common/types/LinkGraph';
import { WorkspaceStats } from '../../common/types/WorkspaceStats';

/** 功能9：图上的一个节点。坐标在绘制时按圆形布局实时计算并缓存，供命中测试 */
interface GraphNode {
  noteId: string;
  label: string;
  /** 未解析概念（虚指的目标）没有真实 noteId，点击走 onOpenNoteByTitle */
  unresolved: boolean;
  x: number;
  y: number;
  r: number;
}

/** 一条边：连接两个节点在 laidOut 数组里的下标 */
interface GraphEdge {
  a: number;
  b: number;
}

/** 图模型：节点数组 + 边数组 */
interface GraphModel {
  nodes: GraphNode[];
  edges: GraphEdge[];
}

@Component
export struct GraphWorkspace {
  @Prop @Watch('onGraphChanged') graph: LinkGraph = { backlinks: [], unresolvedLinks: [] };
  @Prop stats: WorkspaceStats = { noteCount: 0, linkCount: 0, unresolvedCount: 0, tagCount: 0 };

  onSelectNoteById: (noteId: string) => void = () => {};
  onOpenNoteByTitle: (title: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  /** 功能9：Canvas 绘制真实双链图，缩放控件改变 zoom 后重绘 */
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  @State zoom: number = 1;
  private canvasReady: boolean = false;
  /** 最近一次绘制的节点屏幕坐标，onTouch 命中测试用 */
  private laidOut: GraphNode[] = [];

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  onGraphChanged(): void {
    if (this.canvasReady) {
      this.drawGraph();
    }
  }

  /**
   * 从 linkGraph 构建节点/边模型：
   * - 已解析引用的两端（源、目标）各成一个节点，按 noteId 去重；
   * - 未解析链接的目标成为「虚节点」，按标题去重；
   * - 边连接对应节点下标。
   */
  private buildModel(): GraphModel {
    const nodes: GraphNode[] = [];
    const idIndex: Map<string, number> = new Map();
    const edges: GraphEdge[] = [];

    const ensureNode = (key: string, noteId: string, label: string, unresolved: boolean): number => {
      const existing: number | undefined = idIndex.get(key);
      if (existing !== undefined) {
        return existing;
      }
      const idx: number = nodes.length;
      nodes.push({ noteId: noteId, label: label, unresolved: unresolved, x: 0, y: 0, r: unresolved ? 5 : 7 });
      idIndex.set(key, idx);
      return idx;
    };

    for (let i = 0; i < this.graph.backlinks.length; i++) {
      const l: Backlink = this.graph.backlinks[i];
      const a: number = ensureNode(`id:${l.sourceNoteId}`, l.sourceNoteId, l.sourceTitle, false);
      const b: number = ensureNode(`id:${l.targetNoteId}`, l.targetNoteId, l.targetTitle, false);
      edges.push({ a: a, b: b });
    }
    for (let i = 0; i < this.graph.unresolvedLinks.length; i++) {
      const l: UnresolvedLink = this.graph.unresolvedLinks[i];
      const a: number = ensureNode(`id:${l.sourceNoteId}`, l.sourceNoteId, l.sourceTitle, false);
      const b: number = ensureNode(`t:${l.target}`, '', l.target, true);
      edges.push({ a: a, b: b });
    }
    const model: GraphModel = { nodes: nodes, edges: edges };
    return model;
  }

  /** 圆形布局绘制真实双链图：边描线、节点画圆 + 标签，随 zoom 缩放 */
  private drawGraph(): void {
    const c: CanvasRenderingContext2D = this.ctx;
    const w: number = c.width;
    const h: number = c.height;
    const pal: ColorPalette = this.palette();
    c.clearRect(0, 0, w, h);

    const model: GraphModel = this.buildModel();
    const nodes: GraphNode[] = model.nodes;
    if (nodes.length === 0) {
      c.font = '13vp sans-serif';
      c.fillStyle = pal.inkMuted;
      c.textAlign = 'center';
      c.fillText('还没有双链。在正文里写 [[笔记标题]] 即可连成网络。', w / 2, h / 2);
      c.textAlign = 'left';
      this.laidOut = [];
      return;
    }

    const cx: number = w / 2;
    const cy: number = h / 2;
    const baseR: number = Math.min(w, h) / 2 - 46;
    const radius: number = baseR * this.zoom;
    const count: number = nodes.length;
    for (let i = 0; i < count; i++) {
      const angle: number = (Math.PI * 2 * i) / count - Math.PI / 2;
      nodes[i].x = count === 1 ? cx : cx + radius * Math.cos(angle);
      nodes[i].y = count === 1 ? cy : cy + radius * Math.sin(angle);
    }
    this.laidOut = nodes;

    c.lineWidth = 1.4;
    c.strokeStyle = pal.border;
    for (let i = 0; i < model.edges.length; i++) {
      const a: GraphNode = nodes[model.edges[i].a];
      const b: GraphNode = nodes[model.edges[i].b];
      c.beginPath();
      c.moveTo(a.x, a.y);
      c.lineTo(b.x, b.y);
      c.stroke();
    }

    c.font = '11vp sans-serif';
    for (let i = 0; i < count; i++) {
      const n: GraphNode = nodes[i];
      c.beginPath();
      c.arc(n.x, n.y, n.r * (n.unresolved ? 1 : 1.15), 0, 6.2832);
      if (n.unresolved) {
        c.fillStyle = pal.canvas;
        c.fill();
        c.lineWidth = 1.4;
        c.strokeStyle = pal.link;
        c.stroke();
      } else {
        c.fillStyle = pal.accent;
        c.fill();
      }
      c.fillStyle = n.unresolved ? pal.inkMuted : pal.inkSecondary;
      const label: string = n.label.length > 10 ? `${n.label.substring(0, 10)}…` : n.label;
      c.fillText(label, n.x + n.r + 4, n.y + 4);
    }
  }

  /** 命中测试：找到触点最近且在半径内的节点，打开对应笔记 */
  private hitTest(px: number, py: number): void {
    let best: number = -1;
    let bestDist: number = Number.MAX_VALUE;
    for (let i = 0; i < this.laidOut.length; i++) {
      const n: GraphNode = this.laidOut[i];
      const dx: number = px - n.x;
      const dy: number = py - n.y;
      const dist: number = Math.sqrt(dx * dx + dy * dy);
      const hitR: number = n.r + 12;
      if (dist <= hitR && dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
    if (best < 0) {
      return;
    }
    const node: GraphNode = this.laidOut[best];
    if (node.unresolved) {
      this.onOpenNoteByTitle(node.label);
    } else if (node.noteId.length > 0) {
      this.onSelectNoteById(node.noteId);
    }
  }

  private applyZoom(next: number): void {
    this.zoom = next < 0.5 ? 0.5 : (next > 2 ? 2 : next);
    this.drawGraph();
  }

  @Builder
  canvasControl(label: string, next: number) {
    Text(label)
      .fontSize(TypographyTokens.BODY_REGULAR)
      .fontColor(this.palette().inkSecondary)
      .width(32)
      .height(32)
      .textAlign(TextAlign.Center)
      .borderRadius(8)
      .backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().border })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.applyZoom(next))
  }

  @Builder
  panelTitle(text: string, count: number) {
    Row({ space: 6 }) {
      Text(text)
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
        .fontWeight(FontWeight.Medium)
      Text(`${count}`)
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkSecondary)
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  emptyHint(text: string) {
    Column() {
      Text(text)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().inkMuted)
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          Text('知识图谱')
            .fontSize(TypographyTokens.TITLE_HERO)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
          Text(`共 ${this.stats.noteCount} 篇笔记 · ${this.stats.linkCount} 条已解析引用 · ${this.stats.unresolvedCount} 个待创建概念`)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .margin({ top: 4, bottom: 18 })

          // ---- 功能9：Canvas 真实双链图 + 缩放控件（点击节点可打开笔记） ----
          Stack({ alignContent: Alignment.TopEnd }) {
            Canvas(this.ctx)
              .width('100%')
              .height(300)
              .backgroundColor(this.palette().surfaceSubtle)
              .borderRadius(10)
              .onReady(() => {
                this.canvasReady = true;
                this.drawGraph();
              })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down && event.touches.length > 0) {
                  const t: TouchObject = event.touches[0];
                  this.hitTest(t.x, t.y);
                }
              })

            Column({ space: 6 }) {
              this.canvasControl('＋', this.zoom + 0.2)
              this.canvasControl('－', this.zoom - 0.2)
              this.canvasControl('⤾', 1)
            }
            .margin({ top: 10, right: 10 })
          }
          .width('100%')
          .margin({ bottom: 18 })

          Row({ space: 24 }) {
            // ---- 已解析引用 ----
            Column() {
              this.panelTitle('已解析引用', this.graph.backlinks.length)
              if (this.graph.backlinks.length === 0) {
                this.emptyHint('还没有任何 [[双链]]。在正文中书写 [[笔记标题]] 即可建立连接。')
              } else {
                ForEach(this.graph.backlinks, (link: Backlink) => {
                  Column({ space: 3 }) {
                    Row({ space: 6 }) {
                      Text(link.sourceTitle)
                        .fontSize(TypographyTokens.BODY_REGULAR)
                        .fontColor(this.palette().inkPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                        .onClick(() => this.onSelectNoteById(link.sourceNoteId))
                      Text('→')
                        .fontSize(TypographyTokens.CAPTION)
                        .fontColor(this.palette().inkMuted)
                      Text(link.targetTitle)
                        .fontSize(TypographyTokens.BODY_REGULAR)
                        .fontColor(this.palette().link)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                        .onClick(() => this.onSelectNoteById(link.targetNoteId))
                    }
                    .width('100%')

                    if (link.label.length > 0) {
                      Text(link.label)
                        .fontSize(TypographyTokens.TINY)
                        .fontColor(this.palette().inkMuted)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .borderRadius(6)
                  .hoverEffect(HoverEffect.Highlight)
                }, (link: Backlink, index: number) => `${index}-${link.sourceNoteId}-${link.targetNoteId}-${link.label}`)
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(8)
            .backgroundColor(this.palette().surfaceSubtle)

            // ---- 未解析 ----
            Column() {
              this.panelTitle('待创建的概念', this.graph.unresolvedLinks.length)
              if (this.graph.unresolvedLinks.length === 0) {
                this.emptyHint('所有双链都已指向真实笔记，知识网络是闭合的。')
              } else {
                ForEach(this.graph.unresolvedLinks, (link: UnresolvedLink) => {
                  Row({ space: 8 }) {
                    Text('○')
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().link)
                    Text(link.target)
                      .fontSize(TypographyTokens.BODY_REGULAR)
                      .fontColor(this.palette().link)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                      .onClick(() => this.onOpenNoteByTitle(link.target))
                    Text(link.sourceTitle)
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().inkMuted)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .borderRadius(6)
                  .hoverEffect(HoverEffect.Highlight)
                }, (link: UnresolvedLink, index: number) => `${index}-${link.sourceNoteId}-${link.target}`)
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(8)
            .backgroundColor(this.palette().surfaceSubtle)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
        .width('100%')
        .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH + 200 })
        .alignItems(HorizontalAlign.Start)
        .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 28, bottom: 48 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .backgroundColor(this.palette().canvas)
  }
}
