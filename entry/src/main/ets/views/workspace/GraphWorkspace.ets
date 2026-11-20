import { promptAction, KeyboardAvoidMode } from '@kit.ArkUI';
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { Backlink, LinkGraph, UnresolvedLink } from '../../common/types/LinkGraph';
import { NoteItem } from '../../common/types/NoteItem';
import { WorkspaceStats } from '../../common/types/WorkspaceStats';
import { SpaceFolder } from '../../common/types/SpaceFolder';
import { GraphTopicPolicy } from '../../services/GraphTopicPolicy';
import { ALL_GRAPH_TOPICS, GraphNode, GraphView, GraphViewPolicy } from '../../services/GraphViewPolicy';
import { IconButton } from '../common/IconButton';

interface GalaxyCluster {
  id: string;
  name: string;
  count: number;
}

interface NodePoint { x: number; y: number; }

@Component
export struct GraphWorkspace {
  @Prop @Watch('onGraphChanged') graph: LinkGraph = { backlinks: [], unresolvedLinks: [] };
  @Prop stats: WorkspaceStats = { noteCount: 0, linkCount: 0, unresolvedCount: 0, tagCount: 0 };
  @Prop @Watch('onNotesChanged') allNotes: NoteItem[] = [];
  @Prop @Watch('onNotesChanged') projects: SpaceFolder[] = [];

  onSelectNoteById: (noteId: string) => void = () => {};
  onOpenNoteByTitle: (title: string) => void = () => {};
  onLinkNodes: (sourceId: string, targetId: string, targetTitle: string) => Promise<void> = async () => {};
  onCreateGalaxy: (galaxyName: string) => Promise<boolean> = async () => false;

  @StorageProp('flowmindDarkMode') @Watch('onThemeChanged') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') @Watch('onThemeChanged') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasReady: boolean = false;
  private laidOut: GraphNode[] = [];

  @State zoom: number = 1.0;
  @State panX: number = 0;
  @State panY: number = 0;
  @State selectedNode: GraphNode | null = null;
  @State expandedLinks: boolean = false;
  @State expandedPending: boolean = false;
  @State filterMode: string = 'all';
  @State activeGalaxy: string = ALL_GRAPH_TOPICS;
  @State private visibleGraph: GraphView = { nodes: [], edges: [], backlinks: [], unresolvedLinks: [] };
  @State private focusKey: string = '';
  @State private focusDepth: number = 1;
  @State private linkingMode: boolean = false;
  @State private linkSaving: boolean = false;
  @State linkSourceNode: GraphNode | null = null;

  @State isCreatingGalaxy: boolean = false;
  @State newGalaxyName: string = '';
  @State galaxySaving: boolean = false;
  private alive: boolean = true;
  private previousKeyboardMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;

  aboutToAppear(): void {
    this.alive = true;
    this.previousKeyboardMode = this.getUIContext().getKeyboardAvoidMode();
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    this.rebuildGraph();
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode);
  }

  private async submitGalaxy(): Promise<void> {
    if (this.galaxySaving) { return; }
    const name = this.newGalaxyName.trim();
    if (!name || name.length > 80) {
      promptAction.showToast({ message: '主题名称需为 1–80 字' }); return;
    }
    if (this.getGalaxies().some((topic: GalaxyCluster) => topic.id !== ALL_GRAPH_TOPICS && topic.name === name)) {
      promptAction.showToast({ message: '主题已存在，请从上方选择' }); return;
    }
    this.galaxySaving = true;
    try {
      const saved = await this.onCreateGalaxy(name);
      if (!this.alive || !saved) { return; }
      this.activeGalaxy = name;
      this.focusKey = '';
      this.selectedNode = null;
      this.linkingMode = false;
      this.linkSourceNode = null;
      this.newGalaxyName = '';
      this.isCreatingGalaxy = false;
      this.rebuildGraph();
    } catch {
      if (this.alive) { promptAction.showToast({ message: '主题保存失败，请重试' }); }
    } finally { if (this.alive) { this.galaxySaving = false; } }
  }

  private nodeCustomPositions: Map<string, NodePoint> = new Map();
  private draggingNode: GraphNode | null = null;
  private touchStart: NodePoint | null = null;
  private lastTouchX: number = 0;
  private lastTouchY: number = 0;
  private hasDragged: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  onGraphChanged(): void { this.rebuildGraph(); }

  onNotesChanged(): void { this.rebuildGraph(); }

  onThemeChanged(): void { if (this.canvasReady) { this.drawGraph(); } }

  private getGalaxies(): GalaxyCluster[] {
    const clusters: GalaxyCluster[] = [{
      id: ALL_GRAPH_TOPICS, name: '全部主题', count: this.allNotes.filter(note => !note.deletedAt).length
    }];
    for (const topic of GraphTopicPolicy.topics(this.allNotes, this.projects)) {
      clusters.push({ id: topic.name, name: topic.name, count: topic.count });
    }
    return clusters;
  }

  private rebuildGraph(): void {
    if (this.focusKey && !this.allNotes.some(note => !note.deletedAt && GraphViewPolicy.noteKey(note.id) === this.focusKey)) {
      this.focusKey = '';
    }
    const graph = GraphViewPolicy.build(this.allNotes, this.graph, {
      topic: this.activeGalaxy, focus: this.focusKey, depth: this.focusDepth, filter: this.filterMode
    });
    const selectedKey = this.selectedNode?.key;
    const sourceKey = this.linkSourceNode?.key;
    this.selectedNode = graph.nodes.find(node => node.key === selectedKey) ?? null;
    this.linkSourceNode = graph.nodes.find(node => node.key === sourceKey) ?? null;
    this.linkingMode = this.linkSourceNode !== null;
    this.visibleGraph = graph;
    if (this.canvasReady) { this.drawGraph(); }
  }

  private setFocus(node: GraphNode | null): void {
    this.focusKey = node?.key ?? '';
    this.focusDepth = 1;
    this.filterMode = 'all';
    this.clearSelection();
    this.resetView(false);
    this.rebuildGraph();
  }

  private clearSelection(): void {
    this.selectedNode = null;
    this.linkSourceNode = null;
    this.linkingMode = false;
  }

  private layoutNodes(nodes: GraphNode[], cx: number, cy: number, width: number, height: number): void {
    let root = nodes[0];
    for (const node of nodes) {
      node.isRoot = false;
      if (node.key === this.focusKey || (!this.focusKey && node.degree > root.degree)) { root = node; }
    }
    root.isRoot = true;

    const columns = width < 580 ? 1 : 2;
    const rows = Math.ceil((nodes.length - 1) / columns);
    const gap = Math.max(68, Math.min(100, (height - 100) / Math.max(1, rows - 1)));
    const spread = Math.max(164, Math.min(340, width * 0.30));
    let index = 0;
    const rootY = columns === 1 && rows > 0 ? -height * 0.32 : 0;
    for (const node of nodes) {
      const isRoot = node.key === root.key;
      const x = isRoot || columns === 1 ? 0 : (index % 2 === 0 ? -spread : spread);
      const y = isRoot ? rootY : columns === 1 ? rootY + (index + 1) * gap :
        (Math.floor(index / 2) - (rows - 1) / 2) * gap;
      const custom = this.nodeCustomPositions.get(node.key);
      node.x = cx + (custom?.x ?? x) * this.zoom;
      node.y = cy + (custom?.y ?? y) * this.zoom;
      if (!isRoot) { index++; }
    }
  }

  /**
   * 绘制圆角矩形辅助函数 (100% 兼容各类 Canvas 版本)
   */
  private drawRoundRect(c: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
    const rad: number = Math.min(r, w / 2, h / 2);
    c.beginPath();
    c.moveTo(x + rad, y);
    c.lineTo(x + w - rad, y);
    c.arcTo(x + w, y, x + w, y + rad, rad);
    c.lineTo(x + w, y + h - rad);
    c.arcTo(x + w, y + h, x + w - rad, y + h, rad);
    c.lineTo(x + rad, y + h);
    c.arcTo(x, y + h, x, y + h - rad, rad);
    c.lineTo(x, y + rad);
    c.arcTo(x, y, x + rad, y, rad);
    c.closePath();
  }

  /**
   * 绘制现代极简圆角卡片节点
   */
  private drawNodeCard(c: CanvasRenderingContext2D, n: GraphNode, isSelected: boolean, isDimmed: boolean): void {
    const nw: number = n.w * this.zoom;
    const nh: number = n.h * this.zoom;
    const nx: number = n.x - nw / 2;
    const ny: number = n.y - nh / 2;
    const radius: number = Math.min(8 * this.zoom, nh / 2);

    c.fillStyle = this.isDarkMode ? 'rgba(0, 0, 0, 0.35)' : 'rgba(0, 0, 0, 0.05)';
    this.drawRoundRect(c, nx + 1, ny + 2, nw, nh, radius);
    c.fill();

    if (n.isRoot) {
      c.fillStyle = isSelected ? this.palette().activeBg : this.palette().accentSoft;
    } else if (!n.noteId) {
      c.fillStyle = isSelected
        ? (this.isDarkMode ? '#78350F' : '#FEF3C7')
        : (this.isDarkMode ? '#292524' : '#FFFDF5');
    } else {
      c.fillStyle = isSelected ? this.palette().surfaceSubtle : this.palette().surface;
    }
    this.drawRoundRect(c, nx, ny, nw, nh, radius);
    c.fill();

    if (isSelected) {
      c.lineWidth = 2.0;
      c.strokeStyle = this.palette().accent;
    } else if (n.isRoot) {
      c.lineWidth = 1.6;
      c.strokeStyle = this.palette().accent;
    } else if (!n.noteId) {
      c.lineWidth = 1.2;
      c.strokeStyle = '#F59E0B';
    } else {
      c.lineWidth = 1.0;
      c.strokeStyle = this.palette().border;
    }
    this.drawRoundRect(c, nx, ny, nw, nh, radius);
    c.stroke();

    const fontSize: number = Math.max(11, Math.min(18, 13 * this.zoom));
    c.font = n.isRoot ? `bold ${fontSize}vp sans-serif` : `${fontSize}vp sans-serif`;

    const iconX: number = nx + 12 * this.zoom;
    const textY: number = ny + nh / 2 + fontSize * 0.35;
    c.strokeStyle = !n.noteId ? this.palette().warning : this.palette().accent;
    c.lineWidth = 1.5;
    c.strokeRect(iconX, ny + 14 * this.zoom, 11 * this.zoom, 15 * this.zoom);
    c.beginPath();
    c.moveTo(iconX + 3 * this.zoom, ny + 20 * this.zoom); c.lineTo(iconX + 8 * this.zoom, ny + 20 * this.zoom);
    c.moveTo(iconX + 3 * this.zoom, ny + 24 * this.zoom); c.lineTo(iconX + 8 * this.zoom, ny + 24 * this.zoom); c.stroke();
    const labelX: number = iconX + 20 * this.zoom;
    const available: number = nw - 66 * this.zoom;
    let displayLabel: string = n.label;
    if (c.measureText(displayLabel).width > available) {
      while (displayLabel.length > 0 && c.measureText(displayLabel + '…').width > available) { displayLabel = displayLabel.substring(0, displayLabel.length - 1); }
      displayLabel += '…';
    }
    c.fillStyle = isDimmed ? this.palette().inkMuted : this.palette().inkPrimary;
    c.fillText(displayLabel, labelX, textY);

    if (n.degree > 0) {
      const badgeW: number = 18 * this.zoom;
      const badgeH: number = 15 * this.zoom;
      const badgeX: number = nx + nw - badgeW - 6 * this.zoom;
      const badgeY: number = ny + (nh - badgeH) / 2;

      c.fillStyle = this.palette().surfaceSubtle;
      this.drawRoundRect(c, badgeX, badgeY, badgeW, badgeH, 4 * this.zoom);
      c.fill();

      c.font = `bold ${Math.max(8, fontSize * 0.75)}vp sans-serif`;
      c.fillStyle = this.palette().inkSecondary;
      c.textAlign = 'center';
      c.fillText(`${n.degree}`, badgeX + badgeW / 2, badgeY + badgeH * 0.72);
      c.textAlign = 'left';
    }
  }

  private drawGraph(): void {
    const c: CanvasRenderingContext2D = this.ctx;
    const w: number = c.width;
    const h: number = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }

    c.clearRect(0, 0, w, h);
    c.fillStyle = this.palette().canvas;
    c.fillRect(0, 0, w, h);

    const cx: number = w / 2 + this.panX;
    const cy: number = h / 2 + this.panY;

    const gridSize: number = 24 * this.zoom;
    if (gridSize >= 12) {
      const offsetX: number = (cx % gridSize + gridSize) % gridSize;
      const offsetY: number = (cy % gridSize + gridSize) % gridSize;
      c.fillStyle = this.isDarkMode ? 'rgba(255, 255, 255, 0.07)' : 'rgba(0, 0, 0, 0.05)';
      for (let gx = offsetX; gx < w; gx += gridSize) {
        for (let gy = offsetY; gy < h; gy += gridSize) {
          c.fillRect(gx, gy, 1.4, 1.4);
        }
      }
    }

    const model = this.visibleGraph;
    const nodes = model.nodes;
    if (nodes.length === 0) {
      c.font = '13vp sans-serif';
      c.fillStyle = this.isDarkMode ? 'rgba(255, 255, 255, 0.45)' : 'rgba(0, 0, 0, 0.45)';
      c.textAlign = 'center';
      c.fillText('当前范围内没有节点', w / 2, h / 2);
      c.textAlign = 'left';
      this.laidOut = [];
      return;
    }

    this.layoutNodes(nodes, cx, cy, w, h);
    this.laidOut = nodes;

    const selected: GraphNode | null = this.selectedNode;

    for (let i = 0; i < model.edges.length; i++) {
      const aIdx: number = model.edges[i].a;
      const bIdx: number = model.edges[i].b;
      if (aIdx >= model.nodes.length || bIdx >= model.nodes.length) {
        continue;
      }
      const a: GraphNode = model.nodes[aIdx];
      const b: GraphNode = model.nodes[bIdx];

      const isConnectedToSelected = selected !== null && (a.key === selected.key || b.key === selected.key);
      c.beginPath();
      const sideways = Math.abs(b.x - a.x) > Math.abs(b.y - a.y);
      const direction = sideways ? (b.x >= a.x ? 1 : -1) : (b.y >= a.y ? 1 : -1);
      const startX = sideways ? a.x + direction * a.w * this.zoom / 2 : a.x;
      const startY = sideways ? a.y : a.y + direction * a.h * this.zoom / 2;
      const endX = sideways ? b.x - direction * b.w * this.zoom / 2 : b.x;
      const endY = sideways ? b.y : b.y - direction * b.h * this.zoom / 2;
      c.moveTo(startX, startY);
      if (sideways) { const middle: number = (startX + endX) / 2; c.bezierCurveTo(middle, startY, middle, endY, endX, endY); }
      else { const middle: number = (startY + endY) / 2; c.bezierCurveTo(startX, middle, endX, middle, endX, endY); }

      if (isConnectedToSelected) {
        c.lineWidth = 2.4;
        c.strokeStyle = this.palette().accent;
      } else if (selected !== null) {
        c.lineWidth = 1.0;
        c.strokeStyle = this.isDarkMode ? 'rgba(148, 163, 184, 0.15)' : 'rgba(203, 213, 225, 0.35)';
      } else {
        c.lineWidth = 1.4;
        c.strokeStyle = this.palette().border;
      }
      c.stroke();

      c.beginPath();
      c.arc(endX, endY, 2.5, 0, 6.2832);
      c.fillStyle = isConnectedToSelected ? this.palette().accent : this.palette().inkMuted;
      c.fill();
    }

    if (this.linkingMode && this.linkSourceNode !== null) {
      const sw: number = this.linkSourceNode.w * this.zoom + 8;
      const sh: number = this.linkSourceNode.h * this.zoom + 8;
      const sx: number = this.linkSourceNode.x - sw / 2;
      const sy: number = this.linkSourceNode.y - sh / 2;
      c.lineWidth = 1.6;
      c.strokeStyle = '#D97706';
      this.drawRoundRect(c, sx, sy, sw, sh, 10 * this.zoom);
      c.stroke();
    }

    for (let i = 0; i < nodes.length; i++) {
      const n: GraphNode = nodes[i];
      const isSelected: boolean = selected !== null && selected.key === n.key;
      const isDimmed: boolean = selected !== null && !isSelected;
      this.drawNodeCard(c, n, isSelected, isDimmed);
    }
  }

  /**
   * 命中测试：判定触控是否落在矩形卡片上
   */
  private hitTest(px: number, py: number): GraphNode | null {
    for (let i = this.laidOut.length - 1; i >= 0; i--) {
      const n: GraphNode = this.laidOut[i];
      const hw: number = (n.w * this.zoom) / 2 + 6;
      const hh: number = (n.h * this.zoom) / 2 + 6;
      if (px >= n.x - hw && px <= n.x + hw && py >= n.y - hh && py <= n.y + hh) {
        return n;
      }
    }
    return null;
  }

  private applyZoom(next: number): void {
    this.zoom = next < 0.4 ? 0.4 : (next > 2.5 ? 2.5 : next);
    this.drawGraph();
  }

  private resetView(redraw: boolean = true): void {
    this.zoom = 1;
    this.panX = 0;
    this.panY = 0;
    this.nodeCustomPositions.clear();
    if (redraw && this.canvasReady) { this.drawGraph(); }
  }

  private async selectNode(node: GraphNode | null): Promise<void> {
    if (this.linkSaving) { return; }
    const source = this.linkSourceNode;
    if (!node) {
      this.clearSelection();
    } else if (source) {
      if (node.key === source.key) {
        promptAction.showToast({ message: '请选择另一个节点作为目标' });
        return;
      }
      this.linkSaving = true;
      try {
        await this.onLinkNodes(source.noteId, node.noteId, node.label);
        if (!this.alive) { return; }
        this.clearSelection();
        this.selectedNode = this.visibleGraph.nodes.find(item => item.key === node.key) ?? null;
        promptAction.showToast({ message: '已保存笔记链接' });
      } catch (error) {
        if (this.alive) {
          promptAction.showToast({ message: error instanceof Error ? error.message : '链接保存失败，请重试' });
        }
      } finally {
        if (this.alive) { this.linkSaving = false; }
      }
    } else {
      this.selectedNode = node;
    }
    if (this.canvasReady) { this.drawGraph(); }
  }

  private selectByKey(key: string): void {
    const node = this.visibleGraph.nodes.find(item => item.key === key);
    if (node) { this.selectNode(node); }
  }

  private handleCanvasTouch(event: TouchEvent): void {
    const touch = event.touches[0];
    if (event.type === TouchType.Cancel || event.touches.length > 1) {
      this.touchStart = null;
      this.draggingNode = null;
      return;
    }
    if (event.type === TouchType.Down && touch) {
      this.touchStart = { x: touch.x, y: touch.y };
      this.lastTouchX = touch.x;
      this.lastTouchY = touch.y;
      this.hasDragged = false;
      this.draggingNode = this.hitTest(touch.x, touch.y);
      return;
    }
    const start = this.touchStart;
    if (!start) { return; }
    if (event.type === TouchType.Move && touch) {
      this.hasDragged = this.hasDragged || Math.hypot(touch.x - start.x, touch.y - start.y) >= 6;
      if (!this.hasDragged) { return; }
      const dx = touch.x - this.lastTouchX;
      const dy = touch.y - this.lastTouchY;
      const node = this.draggingNode;
      if (node) {
        this.nodeCustomPositions.set(node.key, {
          x: (node.x + dx - this.ctx.width / 2 - this.panX) / this.zoom,
          y: (node.y + dy - this.ctx.height / 2 - this.panY) / this.zoom
        });
      } else {
        this.panX += dx;
        this.panY += dy;
      }
      this.lastTouchX = touch.x;
      this.lastTouchY = touch.y;
      this.drawGraph();
    } else if (event.type === TouchType.Up) {
      const end = event.changedTouches[0];
      if (!this.hasDragged && (!end || Math.hypot(end.x - start.x, end.y - start.y) < 6)) {
        this.selectNode(this.draggingNode);
      }
      this.touchStart = null;
      this.draggingNode = null;
    }
  }

  @Builder
  canvasControl(label: string, description: string, onClick: () => void) {
    Button(label, { type: ButtonType.Normal })
      .fontSize(12)
      .padding(0)
      .fontColor(this.palette().inkPrimary)
      .width(44)
      .height(44)
      .accessibilityText(description)
      .borderRadius(14)
      .backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().borderSubtle })
      .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)' })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(onClick)
  }

  private setFilter(filter: string): void {
    this.filterMode = filter;
    this.clearSelection();
    this.rebuildGraph();
  }

  private setDepth(depth: number): void {
    this.focusDepth = depth;
    this.clearSelection();
    this.rebuildGraph();
  }

  /** 多主题分类切换胶囊栏 */
  @Builder
  galaxySelectorBar() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.getGalaxies(), (g: GalaxyCluster) => {
          Row({ space: 5 }) {
            Text(g.name)
              .fontSize(12)
              .fontWeight(this.activeGalaxy === g.id ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.activeGalaxy === g.id ? this.palette().onAccent : this.palette().inkPrimary)
            Text(`${g.count}`)
              .fontSize(12)
              .fontColor(this.activeGalaxy === g.id ? 'rgba(255,255,255,0.85)' : this.palette().inkMuted)
          }
          .padding({ left: 12, right: 12, top: 8, bottom: 8 }).constraintSize({ minHeight: 44 })
          .borderRadius(22)
          .backgroundColor(this.activeGalaxy === g.id ? this.palette().accent : this.palette().surfaceSubtle)
          .border({ width: 1, color: this.activeGalaxy === g.id ? this.palette().accent : this.palette().borderSubtle })
          .hoverEffect(HoverEffect.Highlight)
          .enabled(!this.linkSaving)
          .onClick(() => {
            this.activeGalaxy = g.id;
            this.focusKey = '';
            this.clearSelection();
            this.resetView(false);
            this.rebuildGraph();
          })
        }, (g: GalaxyCluster) => `cat-${g.id}`)

        Row({ space: 3 }) {
          Text('+')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().accent)
          Text('新建主题')
            .fontSize(12)
            .fontColor(this.palette().accent)
        }
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .borderRadius(8)
        .backgroundColor(this.palette().accentSoft)
        .hoverEffect(HoverEffect.Highlight)
        .constraintSize({ minHeight: 44 })
        .accessibilityText('新建主题')
        .enabled(!this.galaxySaving && !this.linkSaving)
        .onClick(() => {
          this.isCreatingGalaxy = true;
        })
      }
      .padding({ top: 2, bottom: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
    .width('100%')
  }

  @Builder
  panelTitle(text: string, count: number) {
    Row({ space: 6 }) {
      Text(text)
        .fontSize(16)
        .fontColor(this.palette().inkPrimary)
        .fontWeight(FontWeight.Medium)
      Text(`${count}`)
        .fontSize(12)
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

  @Builder
  scopeButton(label: string, selected: boolean, action: () => void) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(22)
      .fontColor(this.palette().inkPrimary)
      .backgroundColor(selected ? this.palette().accentSoft : Color.Transparent)
      .border({ width: 1, color: selected ? this.palette().accent : this.palette().border })
      .accessibilityDescription(selected ? '已选中' : '')
      .enabled(!this.linkSaving).onClick(action)
  }

  @Builder
  nodeDetails(node: GraphNode) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(node.label).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${node.noteId ? node.category : '待创建笔记'} · ${node.degree} 条可见连接`)
            .fontSize(12).fontColor(this.palette().inkSecondary)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        IconButton({ icon: $r('app.media.ic_close'), label: '清除图谱选中状态', available: !this.linkSaving,
          onAction: () => { this.selectNode(null); } })
      }.width('100%')
      Flex({ wrap: FlexWrap.Wrap }) {
        this.scopeButton(node.noteId ? '打开笔记' : '创建笔记', false, () => {
          if (node.noteId) { this.onSelectNoteById(node.noteId); } else { this.onOpenNoteByTitle(node.label); }
        })
        if (node.noteId && this.focusKey !== node.key) {
          this.scopeButton('查看局部图谱', false, () => this.setFocus(node))
        }
        if (node.canLink && !this.linkingMode) {
          this.scopeButton('建立链接', false, () => {
            this.linkSourceNode = node;
            this.linkingMode = true;
            if (this.canvasReady) { this.drawGraph(); }
          })
        }
      }.width('100%')
    }.padding(12).width('100%').margin({ bottom: 12 }).borderRadius(16)
      .backgroundColor(this.palette().surfaceSubtle).alignItems(HorizontalAlign.Start)
  }

  build() {
    Scroll() {
      Column() {
        Column() {
          Flex({ direction: this.isPhone ? FlexDirection.Column : FlexDirection.Row, alignItems: ItemAlign.Start }) {
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                Text('知识图谱')
                  .fontSize(TypographyTokens.TITLE_HERO)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.palette().inkPrimary)

              }
              .alignItems(VerticalAlign.Center)

              Text(`${this.stats.noteCount} 份资料 · ${this.stats.linkCount} 条连接`)
                .fontSize(14)
                .fontColor(this.palette().inkSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(this.isPhone ? 0 : 1)

            if (!this.isPhone) { Blank() }

            Row({ space: 6 }) {
              this.scopeButton('全部', this.filterMode === 'all', () => this.setFilter('all'))
              this.scopeButton('已收录', this.filterMode === 'notes', () => this.setFilter('notes'))
              this.scopeButton('待创建', this.filterMode === 'unresolved', () => this.setFilter('unresolved'))
            }
          }
          .width('100%')
          .margin({ bottom: 12 })

          Row() {
            this.galaxySelectorBar()
          }
          .width('100%')
          .margin({ bottom: 12 })

          if (this.isCreatingGalaxy) {
            Column({ space: 8 }) {
              Text('新建分类：')
                .fontSize(12)
                .fontColor(this.palette().inkPrimary)
              TextInput({
                text: this.newGalaxyName,
                placeholder: '输入分类主题，如：操作系统 / 考研数学'
              })
                .fontSize(12)
                .height(48)
                .width('100%')
                .maxLength(80)
                .enabled(!this.galaxySaving)
                .accessibilityText('主题名称')
                .backgroundColor(this.palette().surface)
                .border({ width: 1, color: this.palette().borderSubtle })
                .borderRadius(6)
                .onChange((v: string) => {
                  this.newGalaxyName = v;
                })

              Row({ space: 8 }) {
              Button(this.galaxySaving ? '正在保存…' : '确定')
                .height(48)
                .layoutWeight(1)
                .enabled(!this.galaxySaving)
                .accessibilityText('确定新建主题')
                .fontSize(12)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette().onAccent)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(6)
                .backgroundColor(this.palette().accent)
                .onClick(() => this.submitGalaxy())

              Button('取消')
                .height(48)
                .layoutWeight(1)
                .enabled(!this.galaxySaving)
                .fontSize(12)
                .fontColor(this.palette().inkMuted)
                .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                .onClick(() => {
                  this.isCreatingGalaxy = false;
                })
              }.width('100%')
            }
            .width('100%')
            .padding(8)
            .margin({ bottom: 12 })
            .borderRadius(8)
            .backgroundColor(this.palette().surfaceSubtle)
            .border({ width: 1, color: this.palette().accent })
          }

          if (this.focusKey) {
            Column({ space: 6 }) {
              Text('局部图谱 · ' + (this.visibleGraph.nodes[0]?.label || '')).fontSize(14).fontColor(this.palette().inkPrimary)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Row({ space: 6 }) {
                this.scopeButton('一跳', this.focusDepth === 1, () => this.setDepth(1))
                this.scopeButton('两跳', this.focusDepth === 2, () => this.setDepth(2))
                this.scopeButton('退出局部', false, () => this.setFocus(null))
              }.width('100%')
            }.width('100%').alignItems(HorizontalAlign.Start).margin({ bottom: 10 })
          }
          if (this.linkingMode && this.linkSourceNode) {
            Row({ space: 8 }) {
              Text(this.linkSaving ? '正在保存链接…' : '从「' + this.linkSourceNode.label + '」创建链接，请选择目标节点')
                .fontSize(13).fontColor(this.palette().inkPrimary).layoutWeight(1)
              this.scopeButton('取消', false, () => { this.clearSelection(); this.drawGraph(); })
            }.width('100%').padding(8).margin({ bottom: 8 }).borderRadius(16).backgroundColor(this.palette().accentSoft)
          }
          Stack({ alignContent: Alignment.TopEnd }) {
            Canvas(this.ctx)
              .width('100%')
              .height(this.isPhone ? 330 : 440)
              .onReady(() => { this.canvasReady = true; this.drawGraph(); })
              .onAreaChange(() => { if (this.canvasReady) { this.drawGraph(); } })
              .onTouch((event: TouchEvent) => this.handleCanvasTouch(event))
              .accessibilityDescription('图谱画布，下面的连接列表也可用于选择节点')
            Column({ space: 6 }) {
              this.canvasControl('＋', '放大图谱', () => this.applyZoom(this.zoom + 0.2))
              this.canvasControl('－', '缩小图谱', () => this.applyZoom(this.zoom - 0.2))
              this.canvasControl('重置', '重置图谱视图', () => this.resetView())
            }.margin({ top: 8, right: 8 })
          }.width('100%').height(this.isPhone ? 330 : 440).borderRadius(20).clip(true)
            .border({ width: 1, color: this.palette().border }).margin({ bottom: 12 })

          if (this.selectedNode) { this.nodeDetails(this.selectedNode) }

          Flex({
            direction: this.isPhone ? FlexDirection.Column : FlexDirection.Row,
            justifyContent: FlexAlign.Start
          }) {
            Column() {
              this.panelTitle('已建立的连接', this.visibleGraph.backlinks.length)
              if (this.visibleGraph.backlinks.length === 0) {
                this.emptyHint('当前范围内暂无已建立的连接。在正文中书写 [[笔记标题]] 即可建立连接。')
              } else {
                ForEach(this.expandedLinks ? this.visibleGraph.backlinks : this.visibleGraph.backlinks.slice(0, 3), (link: Backlink) => {
                  Column({ space: 3 }) {
                    Row({ space: 6 }) {
                      Text(link.sourceTitle)
                        .fontSize(14)
                        .fontColor(this.palette().inkPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                        .onClick(() => this.selectByKey(GraphViewPolicy.noteKey(link.sourceNoteId)))
                      Text('→')
                        .fontSize(TypographyTokens.CAPTION)
                        .fontColor(this.palette().inkMuted)
                      Text(link.targetTitle)
                        .fontSize(14)
                        .fontColor(this.palette().link)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                        .onClick(() => this.selectByKey(GraphViewPolicy.noteKey(link.targetNoteId)))
                    }
                    .width('100%')

                    if (link.label.length > 0) {
                      Text(link.label)
                        .fontSize(12)
                        .fontColor(this.palette().inkMuted)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                    }
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .borderRadius(8)
                  .hoverEffect(HoverEffect.Highlight)
                }, (link: Backlink, index: number) => `${index}-${link.sourceNoteId}-${link.targetNoteId}-${link.label}`)
              }
              if (this.visibleGraph.backlinks.length > 3) {
                Button(this.expandedLinks ? '收起连接' : '查看全部连接').height(44).fontSize(12).fontColor(this.palette().accent).backgroundColor(Color.Transparent)
                  .onClick(() => { this.expandedLinks = !this.expandedLinks; })
              }
            }
            .width(this.isPhone ? '100%' : undefined)
            .layoutWeight(this.isPhone ? 0 : 1)
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(5)
            .backgroundColor(this.palette().surface)
            .border({ width: 1, color: this.palette().borderSubtle })
            .margin(this.isPhone ? { bottom: 14 } : { right: 12 })

            Column() {
              this.panelTitle('待创建的笔记', this.visibleGraph.unresolvedLinks.length)
              if (this.visibleGraph.unresolvedLinks.length === 0) {
                this.emptyHint('当前范围内暂无待创建的笔记。')
              } else {
                ForEach(this.expandedPending ? this.visibleGraph.unresolvedLinks : this.visibleGraph.unresolvedLinks.slice(0, 3), (link: UnresolvedLink) => {
                  Row({ space: 8 }) {
                    Text('○')
                      .fontSize(12)
                      .fontColor(this.palette().link)
                    Column({ space: 5 }) {
                      Text(link.target).fontSize(14).fontColor(this.palette().inkPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                      Text(`来自 ${link.sourceTitle}`).fontSize(12).fontColor(this.palette().inkMuted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                    }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => this.selectByKey(GraphViewPolicy.pendingKey(link.target)))
                    Text('创建')
                      .fontSize(12)
                      .fontColor(this.palette().accent)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(4)
                      .backgroundColor(this.palette().accentSoft)
                      .onClick(() => this.onOpenNoteByTitle(link.target))
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 8, bottom: 8 })
                  .borderRadius(8)
                  .hoverEffect(HoverEffect.Highlight)
                }, (link: UnresolvedLink, index: number) => `${index}-${link.sourceNoteId}-${link.target}`)
              }
              if (this.visibleGraph.unresolvedLinks.length > 3) {
                Button(this.expandedPending ? '收起待创建笔记' : '查看全部待创建笔记').height(44).fontSize(12).fontColor(this.palette().accent).backgroundColor(Color.Transparent)
                  .onClick(() => { this.expandedPending = !this.expandedPending; })
              }
            }
            .width(this.isPhone ? '100%' : undefined)
            .layoutWeight(this.isPhone ? 0 : 1)
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(5)
            .backgroundColor(this.palette().surface)
            .border({ width: 1, color: this.palette().borderSubtle })
            .margin(this.isPhone ? undefined : { left: 12 })
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH + 200 })
        .alignItems(HorizontalAlign.Start)
        .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 20, bottom: 48 })
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
