/**
 * 墨语极简纯白二叉树链接工作台 (GraphWorkspace)
 *
 * 核心设计重塑：
 * 1. 纯白高质感底色：告别沉重生硬的深空星球模拟，采用纯白 (#FFFFFF) 画布搭配微细点阵网格，干净通透
 * 2. 现代二叉树节点卡片 (Binary Tree Cards)：采用 Notion / Miro 风格圆角胶囊卡片，具备类型图标、标题及连接度徽章
 * 3. 平滑三次贝塞尔分支连接 (Cubic Bezier Connectors)：父节点底部平滑连接至子节点顶部，层级分明，天然自洽
 * 4. 丝滑拖拽与弹性拉伸 (Dynamic Node Dragging)：随手拖拽任意节点，引力连线如弹簧般平滑动态拉伸
 * 5. 极简二击直连 (Direct 2-Tap Linking)：点击节点 A 选中，再点击节点 B 即可直接建立双链，彻底摒弃繁杂遮挡的弹窗
 * 6. 轻量悬浮动作条 (Docked Action Pill)：选定节点后在画布底端弹出小巧胶囊条（高度仅 36vp），直达「连线」或「进入笔记」
 * 7. 多主题分类切换：顶部横向胶囊切换不同主题星系（如操作系统、考研数学等），亦可新建分类
 */
import { curves, promptAction } from '@kit.ArkUI';
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { Backlink, LinkGraph, UnresolvedLink } from '../../common/types/LinkGraph';
import { NoteItem } from '../../common/types/NoteItem';
import { WorkspaceStats } from '../../common/types/WorkspaceStats';

/** 纯白二叉拓扑节点 */
export interface GraphNode {
  noteId: string;
  label: string;
  category: string;
  unresolved: boolean;
  x: number;
  y: number;
  w: number;
  h: number;
  degree: number;
  level: number;
  isRoot: boolean;
}

/** 引力边模型 */
export interface GraphEdge {
  a: number;
  b: number;
}

/** 图模型 */
export interface GraphModel {
  nodes: GraphNode[];
  edges: GraphEdge[];
}

/** 主题分类信息 */
export interface GalaxyCluster {
  id: string;
  name: string;
  count: number;
  color: string;
}

/** 坐标点 */
export interface NodePoint {
  x: number;
  y: number;
}

@Component
export struct GraphWorkspace {
  @Prop @Watch('onGraphChanged') graph: LinkGraph = { backlinks: [], unresolvedLinks: [] };
  @Prop stats: WorkspaceStats = { noteCount: 0, linkCount: 0, unresolvedCount: 0, tagCount: 0 };
  @Prop @Watch('onNotesChanged') allNotes: NoteItem[] = [];

  onSelectNoteById: (noteId: string) => void = () => {};
  onOpenNoteByTitle: (title: string) => void = () => {};
  onLinkNodes: (sourceIdentifier: string, targetTitle: string) => void = () => {};
  onCreateGalaxy: (galaxyName: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private canvasReady: boolean = false;
  private laidOut: GraphNode[] = [];

  @State zoom: number = 1.0;
  @State panX: number = 0;
  @State panY: number = 0;
  @State selectedNode: GraphNode | null = null;
  @State filterMode: string = 'all'; // 'all' | 'notes' | 'unresolved'
  @State activeGalaxy: string = 'all'; // 'all' | 具体的分类名

  // 连线模式
  @State linkingMode: boolean = false;
  @State linkSourceNode: GraphNode | null = null;

  // 新建主题分类
  @State isCreatingGalaxy: boolean = false;
  @State newGalaxyName: string = '';

  // 拖动节点坐标暂存 (key: node.label -> NodePoint)
  private nodeCustomPositions: Map<string, NodePoint> = new Map();
  private draggingNode: GraphNode | null = null;
  private isNodeDragging: boolean = false;
  private isPanning: boolean = false;
  private lastTouchX: number = 0;
  private lastTouchY: number = 0;
  private touchDownTime: number = 0;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  onGraphChanged(): void {
    if (this.canvasReady) {
      this.drawGraph();
    }
  }

  onNotesChanged(): void {
    if (this.canvasReady) {
      this.drawGraph();
    }
  }

  /**
   * 获取多主题分类列表
   */
  private getGalaxies(): GalaxyCluster[] {
    const map: Map<string, number> = new Map();
    for (let i = 0; i < this.allNotes.length; i++) {
      const cat: string = (this.allNotes[i].category && this.allNotes[i].category.trim().length > 0)
        ? this.allNotes[i].category.trim()
        : '未分类';
      const cur: number = map.get(cat) ?? 0;
      map.set(cat, cur + 1);
    }

    const clusters: GalaxyCluster[] = [];
    clusters.push({
      id: 'all',
      name: '全部主题',
      count: this.allNotes.length,
      color: '#4F46E5'
    });

    const colors: string[] = ['#3B82F6', '#8B5CF6', '#EC4899', '#10B981', '#F59E0B', '#06B6D4'];
    let idx: number = 0;
    map.forEach((count: number, name: string) => {
      clusters.push({
        id: name,
        name: name,
        count: count,
        color: colors[idx % colors.length]
      });
      idx++;
    });

    return clusters;
  }

  /**
   * 构建图数据模型
   */
  private buildModel(): GraphModel {
    const rawNodes: GraphNode[] = [];
    const idIndex: Map<string, number> = new Map();
    const edges: GraphEdge[] = [];

    // 建立笔记分类速查表
    const noteCategoryMap: Map<string, string> = new Map();
    for (let i = 0; i < this.allNotes.length; i++) {
      const n: NoteItem = this.allNotes[i];
      const cat: string = (n.category && n.category.trim().length > 0) ? n.category.trim() : '未分类';
      noteCategoryMap.set(n.id, cat);
      noteCategoryMap.set(n.title, cat);
    }

    const ensureNode = (key: string, noteId: string, label: string, unresolved: boolean): number => {
      const existing: number | undefined = idIndex.get(key);
      if (existing !== undefined) {
        return existing;
      }
      const idx: number = rawNodes.length;
      const category: string = noteCategoryMap.get(noteId) ?? (noteCategoryMap.get(label) ?? '未分类');
      // 根据文字长度自适应卡片宽度
      const textLen: number = label.length;
      const cardW: number = Math.max(96, Math.min(190, textLen * 11 + 54));

      rawNodes.push({
        noteId: noteId,
        label: label,
        category: category,
        unresolved: unresolved,
        x: 0,
        y: 0,
        w: cardW,
        h: 32,
        degree: 0,
        level: 0,
        isRoot: false
      });
      idIndex.set(key, idx);
      return idx;
    };

    // 1. 已建立反向链接
    for (let i = 0; i < this.graph.backlinks.length; i++) {
      const l: Backlink = this.graph.backlinks[i];
      const a: number = ensureNode(`id:${l.sourceNoteId}`, l.sourceNoteId, l.sourceTitle, false);
      const b: number = ensureNode(`id:${l.targetNoteId}`, l.targetNoteId, l.targetTitle, false);
      edges.push({ a: a, b: b });
      rawNodes[a].degree++;
      rawNodes[b].degree++;
    }

    // 2. 原初未物化概念
    for (let i = 0; i < this.graph.unresolvedLinks.length; i++) {
      const l: UnresolvedLink = this.graph.unresolvedLinks[i];
      const a: number = ensureNode(`id:${l.sourceNoteId}`, l.sourceNoteId, l.sourceTitle, false);
      const b: number = ensureNode(`t:${l.target}`, '', l.target, true);
      edges.push({ a: a, b: b });
      rawNodes[a].degree++;
      rawNodes[b].degree++;
    }

    // 3. 当前分类中未连线的孤岛笔记也纳入画布，方便用户两击建立双链
    for (let i = 0; i < this.allNotes.length; i++) {
      const n: NoteItem = this.allNotes[i];
      const cat: string = (n.category && n.category.trim().length > 0) ? n.category.trim() : '未分类';
      if (this.activeGalaxy === 'all' || cat === this.activeGalaxy) {
        ensureNode(`id:${n.id}`, n.id, n.title, false);
      }
    }

    // 4. 若选定了特定分类，仅保留该分类及直连节点
    if (this.activeGalaxy !== 'all') {
      const filteredIndices: Set<number> = new Set();
      for (let i = 0; i < rawNodes.length; i++) {
        if (rawNodes[i].category === this.activeGalaxy) {
          filteredIndices.add(i);
        }
      }
      const filteredEdges: GraphEdge[] = [];
      for (let i = 0; i < edges.length; i++) {
        const e: GraphEdge = edges[i];
        if (filteredIndices.has(e.a) || filteredIndices.has(e.b)) {
          filteredIndices.add(e.a);
          filteredIndices.add(e.b);
          filteredEdges.push(e);
        }
      }

      const newNodes: GraphNode[] = [];
      const oldToNew: Map<number, number> = new Map();
      rawNodes.forEach((node: GraphNode, oldIdx: number) => {
        if (filteredIndices.has(oldIdx)) {
          oldToNew.set(oldIdx, newNodes.length);
          newNodes.push(node);
        }
      });

      const remappedEdges: GraphEdge[] = [];
      for (let i = 0; i < filteredEdges.length; i++) {
        const ea: number | undefined = oldToNew.get(filteredEdges[i].a);
        const eb: number | undefined = oldToNew.get(filteredEdges[i].b);
        if (ea !== undefined && eb !== undefined) {
          remappedEdges.push({ a: ea, b: eb });
        }
      }

      return { nodes: newNodes, edges: remappedEdges };
    }

    return { nodes: rawNodes, edges: edges };
  }

  /**
   * 类二叉树分支拓扑布局算法
   */
  private layoutTree(nodes: GraphNode[], edges: GraphEdge[], cx: number, cy: number, w: number, h: number): void {
    if (nodes.length === 0) {
      return;
    }
    if (nodes.length === 1) {
      const pos: NodePoint | undefined = this.nodeCustomPositions.get(nodes[0].label);
      nodes[0].x = pos ? pos.x : cx;
      nodes[0].y = pos ? pos.y : cy;
      nodes[0].isRoot = true;
      nodes[0].level = 0;
      return;
    }

    // 1. 构建邻接表
    const adj: Map<number, number[]> = new Map();
    for (let i = 0; i < nodes.length; i++) {
      adj.set(i, []);
    }
    for (let i = 0; i < edges.length; i++) {
      const e: GraphEdge = edges[i];
      if (e.a < nodes.length && e.b < nodes.length) {
        adj.get(e.a)?.push(e.b);
        adj.get(e.b)?.push(e.a);
      }
    }

    // 2. 确定根节点 Root
    let rootIdx: number = 0;
    let maxDegree: number = -1;
    for (let i = 0; i < nodes.length; i++) {
      if (this.activeGalaxy !== 'all' && nodes[i].label.includes(this.activeGalaxy)) {
        rootIdx = i;
        break;
      }
      if (nodes[i].degree > maxDegree) {
        maxDegree = nodes[i].degree;
        rootIdx = i;
      }
    }

    // 3. BFS 分层
    const visited: boolean[] = new Array(nodes.length).fill(false);
    const queue: number[] = [rootIdx];
    visited[rootIdx] = true;
    nodes[rootIdx].isRoot = true;
    nodes[rootIdx].level = 0;

    const levels: number[][] = [[rootIdx]];

    while (queue.length > 0) {
      const curr: number = queue.shift()!;
      const currLevel: number = nodes[curr].level;
      const neighbors: number[] = adj.get(curr) || [];

      for (let j = 0; j < neighbors.length; j++) {
        const neighbor: number = neighbors[j];
        if (!visited[neighbor]) {
          visited[neighbor] = true;
          nodes[neighbor].level = currLevel + 1;
          queue.push(neighbor);

          while (levels.length <= currLevel + 1) {
            levels.push([]);
          }
          levels[currLevel + 1].push(neighbor);
        }
      }
    }

    // 处理孤立节点
    const unvisited: number[] = [];
    for (let i = 0; i < nodes.length; i++) {
      if (!visited[i]) {
        unvisited.push(i);
        nodes[i].level = levels.length;
      }
    }
    if (unvisited.length > 0) {
      levels.push(unvisited);
    }

    // 4. 坐标计算：根节点在顶部偏上，子节点按二叉树分支左右舒展
    const startY: number = cy - Math.min(h * 0.35, 135) * this.zoom;
    const levelHeight: number = Math.max(76, Math.min(115, (h * 0.72) / Math.max(2, levels.length))) * this.zoom;

    for (let l = 0; l < levels.length; l++) {
      const levelNodes: number[] = levels[l];
      const count: number = levelNodes.length;
      const currentY: number = startY + l * levelHeight;

      if (l === 0) {
        // 核心根节点
        const n: GraphNode = nodes[levelNodes[0]];
        const custom: NodePoint | undefined = this.nodeCustomPositions.get(n.label);
        n.x = custom ? custom.x : cx;
        n.y = custom ? custom.y : currentY;
      } else {
        // 左右分支展开：保持合适卡片间距
        const minGap: number = 110 * this.zoom;
        const totalSpan: number = Math.max(minGap * (count - 1), Math.min(w * 0.88, count * 135 * this.zoom));
        const step: number = count > 1 ? totalSpan / (count - 1) : 0;
        const startX: number = cx - totalSpan / 2;

        for (let idx = 0; idx < count; idx++) {
          const nIdx: number = levelNodes[idx];
          const n: GraphNode = nodes[nIdx];
          const custom: NodePoint | undefined = this.nodeCustomPositions.get(n.label);
          if (custom) {
            n.x = custom.x;
            n.y = custom.y;
          } else {
            n.x = count === 1 ? cx : (startX + idx * step);
            n.y = currentY;
          }
        }
      }
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

    // 1. 微轻柔投影
    c.fillStyle = this.isDarkMode ? 'rgba(0, 0, 0, 0.35)' : 'rgba(0, 0, 0, 0.05)';
    this.drawRoundRect(c, nx + 1, ny + 2, nw, nh, radius);
    c.fill();

    // 2. 卡片底色 (纯白 / 极简浅灰)
    if (n.isRoot) {
      c.fillStyle = isSelected
        ? (this.isDarkMode ? '#312E81' : '#EEF2FF')
        : (this.isDarkMode ? '#1E1B4B' : '#F5F3FF');
    } else if (n.unresolved) {
      c.fillStyle = isSelected
        ? (this.isDarkMode ? '#78350F' : '#FEF3C7')
        : (this.isDarkMode ? '#292524' : '#FFFDF5');
    } else {
      c.fillStyle = isSelected
        ? (this.isDarkMode ? '#1E293B' : '#F8FAFC')
        : (this.isDarkMode ? '#1E293B' : '#FFFFFF');
    }
    this.drawRoundRect(c, nx, ny, nw, nh, radius);
    c.fill();

    // 3. 边框 (选中为靛蓝主色，根节点为淡紫，未物化为虚线金黄)
    if (isSelected) {
      c.lineWidth = 2.0;
      c.strokeStyle = '#4F46E5';
    } else if (n.isRoot) {
      c.lineWidth = 1.6;
      c.strokeStyle = '#6366F1';
    } else if (n.unresolved) {
      c.lineWidth = 1.2;
      c.strokeStyle = '#F59E0B';
    } else {
      c.lineWidth = 1.0;
      c.strokeStyle = this.isDarkMode ? '#334155' : '#E2E8F0';
    }
    this.drawRoundRect(c, nx, ny, nw, nh, radius);
    c.stroke();

    // 4. 左侧图标与标题文字
    const fontSize: number = Math.max(9, Math.min(13, 11 * this.zoom));
    c.font = n.isRoot ? `bold ${fontSize}vp sans-serif` : `${fontSize}vp sans-serif`;

    const icon: string = n.isRoot ? '🏷' : (n.unresolved ? '✦' : '📄');
    const iconX: number = nx + 8 * this.zoom;
    const textY: number = ny + nh / 2 + fontSize * 0.35;

    c.fillStyle = n.unresolved ? '#D97706' : (n.isRoot ? '#4F46E5' : (this.isDarkMode ? '#94A3B8' : '#64748B'));
    c.fillText(icon, iconX, textY);

    // 文本标号截断
    const labelX: number = iconX + 16 * this.zoom;
    const maxChars: number = Math.max(5, Math.floor((nw - 48 * this.zoom) / (fontSize * 0.72)));
    const displayLabel: string = n.label.length > maxChars ? `${n.label.substring(0, maxChars)}…` : n.label;

    c.fillStyle = isSelected
      ? (this.isDarkMode ? '#FFFFFF' : '#1E1B4B')
      : (isDimmed
          ? (this.isDarkMode ? '#64748B' : '#94A3B8')
          : (this.isDarkMode ? '#F8FAFC' : '#1E293B'));
    c.fillText(displayLabel, labelX, textY);

    // 5. 右侧连接度徽章 Badge
    if (n.degree > 0) {
      const badgeW: number = 18 * this.zoom;
      const badgeH: number = 15 * this.zoom;
      const badgeX: number = nx + nw - badgeW - 6 * this.zoom;
      const badgeY: number = ny + (nh - badgeH) / 2;

      c.fillStyle = this.isDarkMode ? '#334155' : '#F1F5F9';
      this.drawRoundRect(c, badgeX, badgeY, badgeW, badgeH, 4 * this.zoom);
      c.fill();

      c.font = `bold ${Math.max(8, fontSize * 0.75)}vp sans-serif`;
      c.fillStyle = this.isDarkMode ? '#CBD5E1' : '#64748B';
      c.textAlign = 'center';
      c.fillText(`${n.degree}`, badgeX + badgeW / 2, badgeY + badgeH * 0.72);
      c.textAlign = 'left';
    }
  }

  /**
   * 绘制纯白二叉树画布
   */
  private drawGraph(): void {
    const c: CanvasRenderingContext2D = this.ctx;
    const w: number = c.width;
    const h: number = c.height;
    if (w <= 0 || h <= 0) {
      return;
    }

    // 1. 纯白高质感画布底色 (暗色模式为优雅暗灰)
    c.clearRect(0, 0, w, h);
    c.fillStyle = this.isDarkMode ? '#0F172A' : '#FFFFFF';
    c.fillRect(0, 0, w, h);

    const cx: number = w / 2 + this.panX;
    const cy: number = h / 2 + this.panY;

    // 2. 极简轻柔点阵网格 (Notion / Miro 风格)
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

    const model: GraphModel = this.buildModel();
    let nodes: GraphNode[] = model.nodes;

    // 节点类型筛选
    if (this.filterMode === 'notes') {
      nodes = nodes.filter((n: GraphNode) => !n.unresolved);
    } else if (this.filterMode === 'unresolved') {
      nodes = nodes.filter((n: GraphNode) => n.unresolved);
    }

    if (nodes.length === 0) {
      c.font = '13vp sans-serif';
      c.fillStyle = this.isDarkMode ? 'rgba(255, 255, 255, 0.45)' : 'rgba(0, 0, 0, 0.45)';
      c.textAlign = 'center';
      c.fillText('暂无笔记链接。在笔记中书写 [[概念名称]] 即可点亮知识网络。', w / 2, h / 2);
      c.textAlign = 'left';
      this.laidOut = [];
      return;
    }

    // 3. 执行类二叉树分支拓扑布局
    this.layoutTree(nodes, model.edges, cx, cy, w, h);
    this.laidOut = nodes;

    const selected: GraphNode | null = this.selectedNode;

    // 4. 绘制平滑优雅的类二叉树分支连接线 (Cubic Bezier curves)
    for (let i = 0; i < model.edges.length; i++) {
      const aIdx: number = model.edges[i].a;
      const bIdx: number = model.edges[i].b;
      if (aIdx >= model.nodes.length || bIdx >= model.nodes.length) {
        continue;
      }
      const a: GraphNode = model.nodes[aIdx];
      const b: GraphNode = model.nodes[bIdx];

      // 区分父节点与子节点（根据层级判定流动方向）
      const parent: GraphNode = a.level <= b.level ? a : b;
      const child: GraphNode = a.level <= b.level ? b : a;

      const isConnectedToSelected: boolean = selected !== null &&
        (a.label === selected.label || b.label === selected.label);

      c.beginPath();
      // 从父节点底部中心优雅连向子节点顶部中心
      const startX: number = parent.x;
      const startY: number = parent.y + (parent.h * this.zoom) / 2;
      const endX: number = child.x;
      const endY: number = child.y - (child.h * this.zoom) / 2;

      const deltaY: number = Math.max(22, (endY - startY) * 0.46);
      c.moveTo(startX, startY);
      c.bezierCurveTo(startX, startY + deltaY, endX, endY - deltaY, endX, endY);

      if (isConnectedToSelected) {
        // 选中高亮能量线
        c.lineWidth = 2.4;
        c.strokeStyle = '#4F46E5';
      } else if (selected !== null) {
        // 其余淡化
        c.lineWidth = 1.0;
        c.strokeStyle = this.isDarkMode ? 'rgba(148, 163, 184, 0.15)' : 'rgba(203, 213, 225, 0.35)';
      } else {
        // 常态极简分支灰线
        c.lineWidth = 1.4;
        c.strokeStyle = this.isDarkMode ? '#334155' : '#CBD5E1';
      }
      c.stroke();

      // 在子节点接入点绘制微型连接圆点
      c.beginPath();
      c.arc(endX, endY, 2.5, 0, 6.2832);
      c.fillStyle = isConnectedToSelected ? '#4F46E5' : (this.isDarkMode ? '#64748B' : '#94A3B8');
      c.fill();
    }

    // 5. 如果处于直连模式，在起点节点周围绘制轻柔引导光晕
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

    // 6. 绘制所有现代卡片节点
    for (let i = 0; i < nodes.length; i++) {
      const n: GraphNode = nodes[i];
      const isSelected: boolean = selected !== null && selected.label === n.label;
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

  private resetView(): void {
    this.zoom = 1.0;
    this.panX = 0;
    this.panY = 0;
    this.selectedNode = null;
    this.linkingMode = false;
    this.linkSourceNode = null;
    this.nodeCustomPositions.clear();
    this.drawGraph();
    promptAction.showToast({ message: '已复位视图' });
  }

  /**
   * 执行两个节点建立双链
   */
  private executeLinkNodes(source: GraphNode, target: GraphNode): void {
    if (source.label === target.label) {
      promptAction.showToast({ message: '不能与自身建立链接' });
      return;
    }
    const sourceIdentifier: string = source.noteId && source.noteId.length > 0 ? source.noteId : source.label;
    this.onLinkNodes(sourceIdentifier, target.label);
    promptAction.showToast({ message: `已建立双向链接：${source.label} ↔ ${target.label}` });
    this.linkingMode = false;
    this.linkSourceNode = null;
    this.selectedNode = target;
    this.drawGraph();
  }

  // ------------------------------------------------------------------
  // UI 构件 (Builders)
  // ------------------------------------------------------------------

  @Builder
  canvasControl(label: string, onClick: () => void) {
    Text(label)
      .fontSize(TypographyTokens.BODY_REGULAR)
      .fontColor(this.palette().inkPrimary)
      .width(32)
      .height(32)
      .textAlign(TextAlign.Center)
      .borderRadius(6)
      .backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().borderSubtle })
      .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)' })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(onClick)
  }

  @Builder
  filterPill(mode: string, label: string, count: number) {
    Row({ space: 4 }) {
      Text(label)
        .fontSize(TypographyTokens.TINY)
        .fontWeight(this.filterMode === mode ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.filterMode === mode ? this.palette().accent : this.palette().inkMuted)
      Text(`${count}`)
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.filterMode === mode ? this.palette().accent : this.palette().inkMuted)
    }
    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
    .borderRadius(14)
    .backgroundColor(this.filterMode === mode ? this.palette().accentSoft : this.palette().surfaceSubtle)
    .border({ width: 1, color: this.filterMode === mode ? this.palette().accent : Color.Transparent })
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      this.filterMode = mode;
      this.selectedNode = null;
      this.drawGraph();
    })
  }

  /** 多主题分类切换胶囊栏 */
  @Builder
  galaxySelectorBar() {
    Scroll() {
      Row({ space: 6 }) {
        ForEach(this.getGalaxies(), (g: GalaxyCluster) => {
          Row({ space: 5 }) {
            Text(g.name)
              .fontSize(TypographyTokens.TINY)
              .fontWeight(this.activeGalaxy === g.id ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.activeGalaxy === g.id ? Color.White : this.palette().inkPrimary)
            Text(`${g.count}`)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.activeGalaxy === g.id ? 'rgba(255,255,255,0.85)' : this.palette().inkMuted)
          }
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .borderRadius(8)
          .backgroundColor(this.activeGalaxy === g.id ? this.palette().accent : this.palette().surfaceSubtle)
          .border({ width: 1, color: this.activeGalaxy === g.id ? this.palette().accent : this.palette().borderSubtle })
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.activeGalaxy = g.id;
            this.selectedNode = null;
            this.linkingMode = false;
            this.linkSourceNode = null;
            this.drawGraph();
          })
        }, (g: GalaxyCluster) => `cat-${g.id}`)

        // + 新建主题分类
        Row({ space: 3 }) {
          Text('+')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().accent)
          Text('新建主题')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().accent)
        }
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .borderRadius(8)
        .backgroundColor(this.palette().accentSoft)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.isCreatingGalaxy = true;
        })
      }
      .padding({ top: 2, bottom: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
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
          // ---- 1. 顶栏标题与统计 ----
          Row() {
            Column({ space: 4 }) {
              Row({ space: 8 }) {
                Text('知识图谱')
                  .fontSize(TypographyTokens.TITLE_HERO)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.palette().inkPrimary)
                Text('二叉链接版')
                  .fontSize(TypographyTokens.TINY)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.palette().accent)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .backgroundColor(this.palette().accentSoft)
              }
              .alignItems(VerticalAlign.Center)

              Text(`共 ${this.stats.noteCount} 篇笔记 · ${this.stats.linkCount} 条已解析双链 · 可拖拽节点改变路径 · 点击两节点直接建立链接`)
                .fontSize(TypographyTokens.BODY_REGULAR)
                .fontColor(this.palette().inkSecondary)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Blank()

            // 过滤选择胶囊
            Row({ space: 6 }) {
              this.filterPill('all', '全部', this.stats.linkCount + this.stats.unresolvedCount)
              this.filterPill('notes', '实体笔记', this.stats.linkCount)
              this.filterPill('unresolved', '待创建概念', this.stats.unresolvedCount)
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ bottom: 12 })

          // ---- 1.1 主题分类横向切换栏 ----
          Row() {
            this.galaxySelectorBar()
          }
          .width('100%')
          .margin({ bottom: 12 })

          // 新建主题分类内联条
          if (this.isCreatingGalaxy) {
            Row({ space: 8 }) {
              Text('新建分类：')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkPrimary)
              TextInput({
                text: this.newGalaxyName,
                placeholder: '输入分类主题，如：操作系统 / 考研数学'
              })
                .fontSize(TypographyTokens.TINY)
                .height(30)
                .layoutWeight(1)
                .backgroundColor(this.palette().surface)
                .border({ width: 1, color: this.palette().borderSubtle })
                .borderRadius(6)
                .onChange((v: string) => {
                  this.newGalaxyName = v;
                })

              Text('确定')
                .fontSize(TypographyTokens.TINY)
                .fontWeight(FontWeight.Bold)
                .fontColor(Color.White)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(6)
                .backgroundColor(this.palette().accent)
                .onClick(() => {
                  const name: string = this.newGalaxyName.trim();
                  if (name.length === 0) {
                    promptAction.showToast({ message: '请输入分类主题名称' });
                    return;
                  }
                  this.onCreateGalaxy(name);
                  this.activeGalaxy = name;
                  this.newGalaxyName = '';
                  this.isCreatingGalaxy = false;
                  promptAction.showToast({ message: `已创建并切换到主题「${name}」` });
                })

              Text('取消')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
                .padding({ left: 8, right: 8, top: 5, bottom: 5 })
                .onClick(() => {
                  this.isCreatingGalaxy = false;
                })
            }
            .width('100%')
            .padding(8)
            .margin({ bottom: 12 })
            .borderRadius(8)
            .backgroundColor(this.palette().surfaceSubtle)
            .border({ width: 1, color: this.palette().accent })
          }

          // ---- 2. 纯白极简二叉树链接 Canvas 舞台 ----
          Stack({ alignContent: Alignment.TopEnd }) {
            Canvas(this.ctx)
              .width('100%')
              .height(440)
              .borderRadius(14)
              .backgroundColor(this.isDarkMode ? '#0F172A' : '#FFFFFF')
              .border({ width: 1, color: this.palette().borderSubtle })
              .shadow({ radius: 8, color: 'rgba(0,0,0,0.04)', offsetY: 2 })
              .onReady(() => {
                this.canvasReady = true;
                this.drawGraph();
              })
              .onTouch((event: TouchEvent) => {
                const touch = event.touches[0];
                if (!touch) {
                  return;
                }

                if (event.type === TouchType.Down) {
                  this.lastTouchX = touch.x;
                  this.lastTouchY = touch.y;
                  this.touchDownTime = Date.now();

                  const hit: GraphNode | null = this.hitTest(touch.x, touch.y);
                  if (hit !== null) {
                    this.draggingNode = hit;
                    this.isNodeDragging = true;
                    this.isPanning = false;
                  } else {
                    this.draggingNode = null;
                    this.isNodeDragging = false;
                    this.isPanning = true;
                  }
                } else if (event.type === TouchType.Move) {
                  const dx: number = touch.x - this.lastTouchX;
                  const dy: number = touch.y - this.lastTouchY;

                  if (this.isNodeDragging && this.draggingNode !== null) {
                    // 实时拖动节点，平滑拉伸贝塞尔连线
                    this.draggingNode.x = touch.x;
                    this.draggingNode.y = touch.y;
                    const pt: NodePoint = { x: touch.x, y: touch.y };
                    this.nodeCustomPositions.set(this.draggingNode.label, pt);
                    this.drawGraph();
                  } else if (this.isPanning) {
                    if (Math.hypot(dx, dy) > 3) {
                      this.panX += dx;
                      this.panY += dy;
                      this.lastTouchX = touch.x;
                      this.lastTouchY = touch.y;
                      this.drawGraph();
                    }
                  }
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  const duration: number = Date.now() - this.touchDownTime;
                  // 短触击 (Tap)：实现直接两击建链或选定节点
                  if (duration < 280) {
                    const tappedNode: GraphNode | null = this.hitTest(touch.x, touch.y);
                    if (tappedNode !== null) {
                      if (this.linkingMode && this.linkSourceNode !== null) {
                        // 连线模式中：直接点击第二节点建立链接！
                        this.executeLinkNodes(this.linkSourceNode, tappedNode);
                      } else {
                        // 选定节点：自动作为起点备选
                        this.selectedNode = tappedNode;
                        this.linkSourceNode = tappedNode;
                        this.linkingMode = true;
                        this.drawGraph();
                      }
                    } else {
                      // 点击空白取消选择
                      this.selectedNode = null;
                      this.linkingMode = false;
                      this.linkSourceNode = null;
                      this.drawGraph();
                    }
                  }
                  this.isNodeDragging = false;
                  this.draggingNode = null;
                  this.isPanning = false;
                }
              })

            // 顶部居中：极简连线提示横幅
            if (this.linkingMode && this.linkSourceNode !== null) {
              Row({ space: 8 }) {
                Text('🔗')
                  .fontSize(13)
                  .fontColor('#4F46E5')
                Text(`已选「${this.linkSourceNode.label}」，点击任意节点建立链接`)
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkPrimary)
                  .fontWeight(FontWeight.Medium)
                Text('取消')
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkMuted)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(4)
                  .backgroundColor(this.palette().surfaceSubtle)
                  .onClick(() => {
                    this.linkingMode = false;
                    this.linkSourceNode = null;
                    this.drawGraph();
                  })
              }
              .padding({ left: 12, right: 10, top: 6, bottom: 6 })
              .borderRadius(18)
              .backgroundColor(this.palette().surface)
              .border({ width: 1, color: this.palette().borderSubtle })
              .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)' })
              .margin({ top: 12 })
              .alignSelf(ItemAlign.Center)
              .position({ x: '22%', y: 12 })
            }

            // 右上角极简视口控制器
            Column({ space: 6 }) {
              this.canvasControl('＋', () => this.applyZoom(this.zoom + 0.2))
              this.canvasControl('－', () => this.applyZoom(this.zoom - 0.2))
              this.canvasControl('⤾', () => this.resetView())
            }
            .margin({ top: 12, right: 12 })

            // 底部居中：轻量悬浮胶囊动作条 (Docked Action Pill，高度仅 36vp，绝不遮挡)
            if (this.selectedNode !== null) {
              Row({ space: 10 }) {
                Row({ space: 5 }) {
                  Text(this.selectedNode.unresolved ? '✦' : '📄')
                    .fontSize(14)
                    .fontColor(this.selectedNode.unresolved ? '#D97706' : '#4F46E5')
                  Text(this.selectedNode.label)
                    .fontSize(TypographyTokens.TINY)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette().inkPrimary)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .constraintSize({ maxWidth: 160 })
                  Text(`${this.selectedNode.degree}条双链`)
                    .fontSize(10)
                    .fontColor(this.palette().inkMuted)
                    .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                    .borderRadius(4)
                    .backgroundColor(this.palette().surfaceSubtle)
                }

                Divider()
                  .vertical(true)
                  .height(16)
                  .color(this.palette().borderSubtle)

                // 快捷直达笔记
                Row({ space: 4 }) {
                  Text(this.selectedNode.unresolved ? '✦ 物化' : '进入笔记 →')
                    .fontSize(TypographyTokens.TINY)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                }
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .borderRadius(6)
                .backgroundColor(this.selectedNode.unresolved ? '#D97706' : '#4F46E5')
                .hoverEffect(HoverEffect.Highlight)
                .onClick(() => {
                  if (this.selectedNode !== null) {
                    if (this.selectedNode.unresolved) {
                      this.onOpenNoteByTitle(this.selectedNode.label);
                    } else if (this.selectedNode.noteId.length > 0) {
                      this.onSelectNoteById(this.selectedNode.noteId);
                    }
                  }
                })

                // 取消选择
                Text('✕')
                  .fontSize(12)
                  .fontColor(this.palette().inkMuted)
                  .padding(4)
                  .borderRadius(4)
                  .hoverEffect(HoverEffect.Highlight)
                  .onClick(() => {
                    this.selectedNode = null;
                    this.linkingMode = false;
                    this.linkSourceNode = null;
                    this.drawGraph();
                  })
              }
              .padding({ left: 14, right: 10, top: 6, bottom: 6 })
              .borderRadius(20)
              .backgroundColor(this.palette().surface)
              .border({ width: 1, color: this.palette().borderSubtle })
              .shadow({ radius: 12, color: 'rgba(0,0,0,0.08)', offsetY: 3 })
              .alignSelf(ItemAlign.Center)
              .position({ x: '18%', y: 385 })
            }
          }
          .width('100%')
          .height(440)
          .margin({ bottom: 20 })

          // ---- 3. 双链脉络明细抽屉 ----
          Flex({
            direction: this.isPhone ? FlexDirection.Column : FlexDirection.Row,
            justifyContent: FlexAlign.Start
          }) {
            // ---- 已解析引用 ----
            Column() {
              this.panelTitle('已解析双链脉络', this.graph.backlinks.length)
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
                  .borderRadius(8)
                  .hoverEffect(HoverEffect.Highlight)
                }, (link: Backlink, index: number) => `${index}-${link.sourceNoteId}-${link.targetNoteId}-${link.label}`)
              }
            }
            .width(this.isPhone ? '100%' : undefined)
            .layoutWeight(this.isPhone ? 0 : 1)
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(10)
            .backgroundColor(this.palette().surface)
            .border({ width: 1, color: this.palette().borderSubtle })
            .margin(this.isPhone ? { bottom: 14 } : { right: 12 })

            // ---- 原初星云（待创建概念） ----
            Column() {
              this.panelTitle('待创建概念', this.graph.unresolvedLinks.length)
              if (this.graph.unresolvedLinks.length === 0) {
                this.emptyHint('所有双链都已指向真实笔记，知识网络闭合自洽。')
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
                    Text(`来自 ${link.sourceTitle}`)
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().inkMuted)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text('＋ 物化')
                      .fontSize(TypographyTokens.TINY)
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
            }
            .width(this.isPhone ? '100%' : undefined)
            .layoutWeight(this.isPhone ? 0 : 1)
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(10)
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
