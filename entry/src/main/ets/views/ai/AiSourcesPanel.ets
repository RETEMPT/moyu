/**
 * AI 墨客右栏：类 Antigravity 工程上下文工作舱 (AiSourcesPanel)
 *
 * 融合 Google Antigravity / Cursor 工程工作区管理范式：
 * 1. 顶部：Project 切换器（全库 / 专属工程）+「+ 新建 Project」内联创建器
 * 2. 当前对话挂载上下文 (Active Working Set)：
 *    - 实时呈现已注入对话的文档药丸卡片与 ✕ 移除按键
 *    - Token 消耗仪表盘（计算上下文窗口占比）
 *    - 核心行动入口：「💬 基于已选上下文开启对话」一键联动主对话舱
 * 3. 类 Antigravity 目录与文件树 (Directory & File Tree Explorer)：
 *    - 文件夹折叠/展开与文件类型图标（Markdown 📄, PDF 📕, 手写草稿 ✏️）
 *    - 目录级批量快捷操作：「+ 挂载全目录」/「✓ 全挂载」一键加卸载
 *    - 文件级精细操作：「+ 附加」/「✓ 已在上下文」实时联动
 *    - 实时目录过滤搜索框
 * 4. 溯源与工具标签页 (Citations & Agent Tools)：
 *    - 知识溯源切片 (RAG Hits)
 *    - 智能体 Function Calling 工具箱总控与权限说明
 */
import { curves, promptAction } from '@kit.ArkUI';
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { ChatCitation } from '../../common/types/ChatSession';
import { NoteItem } from '../../common/types/NoteItem';
import { SpaceFolder } from '../../common/types/SpaceFolder';

const PRESET_PROJECT_COLORS: string[] = [
  '#4F46E5', // 经典靛蓝
  '#2563EB', // 皇家蓝
  '#059669', // 翡翠绿
  '#D97706', // 琥珀橙
  '#DC2626', // 玫瑰红
  '#8B5CF6'  // 智能紫
];

const PRESET_PROJECT_ICONS: string[] = [
  '📁', '⚡', '📚', '🔬', '💡', '🎯', '🚀', '🧠'
];

@Component
export struct AiSourcesPanel {
  @Prop spaces: SpaceFolder[] = [];
  @Prop citations: ChatCitation[] = [];
  @Prop pinnedNotes: NoteItem[] = [];
  @Prop layerLabel: string = '';
  @Prop modelLabel: string = '';
  @Prop currentDocTitle: string = '';
  @Prop currentDocNote: NoteItem | null = null;
  @Prop allNotes: NoteItem[] = [];
  @Prop toolsEnabled: boolean = true;

  onToggleTools: (enabled: boolean) => void = () => {};
  onAddPinnedNote: (note: NoteItem) => void = () => {};
  onAddBatchPinnedNotes: (notes: NoteItem[]) => void = () => {};
  onRemovePinnedNote: (noteId: string) => void = () => {};
  onRemoveBatchPinnedNotes: (noteIds: string[]) => void = () => {};
  onClearPinnedNotes: () => void = () => {};
  onPreviewSource: (citation: ChatCitation) => void = () => {};
  onOpenModelSettings: () => void = () => {};
  onClose: () => void = () => {};
  onCreateProject: (name: string, color: string, icon: string) => void = () => {};
  onStartChatWithContext: (prefilledPrompt: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  @State activeTab: string = 'explorer'; // 'explorer' | 'tools'
  @State selectedProjectFilter: string = ''; // '' 代表全部工程
  @State searchKeyword: string = '';
  @State projectDropdownOpen: boolean = false;

  // 新建工程状态
  @State isCreatingProject: boolean = false;
  @State newProjectName: string = '';
  @State newProjectColor: string = '#4F46E5';
  @State newProjectIcon: string = '📁';

  // 文件夹展开/折叠状态映射 (folderId -> isOpen)
  @State folderOpenStates: Record<string, boolean> = {};

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  /** 判断文件夹是否展开 */
  private isFolderExpanded(space: SpaceFolder): boolean {
    if (this.folderOpenStates[space.id] !== undefined) {
      return this.folderOpenStates[space.id];
    }
    return space.isOpen ?? true;
  }

  /** 切换文件夹展开折叠 */
  private toggleFolderExpand(space: SpaceFolder): void {
    animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
      const current: boolean = this.isFolderExpanded(space);
      this.folderOpenStates[space.id] = !current;
    });
  }

  /** 估算当前挂载上下文的 tokens */
  private calculateEstimatedTokens(): number {
    let charCount: number = 0;
    for (let i = 0; i < this.pinnedNotes.length; i++) {
      charCount += (this.pinnedNotes[i].contentDetail ?? '').length;
      charCount += this.pinnedNotes[i].title.length;
    }
    // 中英混合文本 1 token 约等于 1.5 字符
    return Math.max(Math.round(charCount / 1.5), this.pinnedNotes.length * 50);
  }

  /** 检查某工程目录下的笔记是否全部已挂载 */
  private isFolderFullyPinned(space: SpaceFolder): boolean {
    const notes: NoteItem[] = space.notes ?? [];
    if (notes.length === 0) {
      return false;
    }
    const pinnedIds: Set<string> = new Set(this.pinnedNotes.map((n: NoteItem) => n.id));
    for (let i = 0; i < notes.length; i++) {
      if (!pinnedIds.has(notes[i].id)) {
        return false;
      }
    }
    return true;
  }

  /** 一键挂载或卸载整个工程目录 */
  private toggleFolderPinBatch(space: SpaceFolder): void {
    const notes: NoteItem[] = space.notes ?? [];
    if (notes.length === 0) {
      promptAction.showToast({ message: `工程「${space.name}」下暂无文档` });
      return;
    }
    const isFullyPinned: boolean = this.isFolderFullyPinned(space);
    if (isFullyPinned) {
      // 卸载整目录
      const ids: string[] = notes.map((n: NoteItem) => n.id);
      this.onRemoveBatchPinnedNotes(ids);
      promptAction.showToast({ message: `已移出工程「${space.name}」的全部文档` });
    } else {
      // 批量挂载整目录
      this.onAddBatchPinnedNotes(notes);
      promptAction.showToast({ message: `已挂载工程「${space.name}」共 ${notes.length} 篇文档` });
    }
  }

  /** 获取要展示的工程空间列表 */
  private filteredSpaces(): SpaceFolder[] {
    const kw: string = this.searchKeyword.trim().toLowerCase();
    const result: SpaceFolder[] = [];

    for (let i = 0; i < this.spaces.length; i++) {
      const space: SpaceFolder = this.spaces[i];
      // 如果筛选了特定工程
      if (this.selectedProjectFilter.length > 0 && space.name !== this.selectedProjectFilter) {
        continue;
      }

      // 如果有搜索词
      if (kw.length > 0) {
        const spaceNameMatch: boolean = space.name.toLowerCase().includes(kw);
        const matchedNotes: NoteItem[] = (space.notes ?? []).filter((n: NoteItem) =>
          n.title.toLowerCase().includes(kw) ||
          (n.tag && n.tag.toLowerCase().includes(kw)) ||
          (n.previewText && n.previewText.toLowerCase().includes(kw))
        );

        if (spaceNameMatch || matchedNotes.length > 0) {
          result.push({
            id: space.id,
            name: space.name,
            count: matchedNotes.length > 0 ? matchedNotes.length : space.count,
            isOpen: true, // 搜索时自动展开
            children: space.children,
            color: space.color,
            icon: space.icon,
            notes: spaceNameMatch ? (space.notes ?? []) : matchedNotes
          });
        }
      } else {
        result.push(space);
      }
    }
    return result;
  }

  /** 获取文件类型图标 */
  private getFileIcon(note: NoteItem): string {
    if (note.type === 'pdf' || note.title.toLowerCase().endsWith('.pdf')) {
      return '📕';
    }
    if (note.type === 'draft' || (note.previewText && note.previewText.includes('手写'))) {
      return '✏️';
    }
    return '📄';
  }

  /** 处理新建工程确认 */
  private handleCreateProject(): void {
    const name: string = this.newProjectName.trim();
    if (name.length === 0) {
      promptAction.showToast({ message: '请输入工程名称' });
      return;
    }
    this.onCreateProject(name, this.newProjectColor, this.newProjectIcon);
    this.selectedProjectFilter = name;
    this.newProjectName = '';
    this.isCreatingProject = false;
    promptAction.showToast({ message: `已创建并切换至工程「${name}」` });
  }

  /** 触发基于已选上下文开启对话 */
  private triggerStartChat(): void {
    if (this.pinnedNotes.length === 0) {
      promptAction.showToast({ message: '请先在下方目录勾选或挂载文档到上下文' });
      return;
    }
    const projName: string = this.selectedProjectFilter.length > 0 ? this.selectedProjectFilter : '当前资料';
    const titles: string = this.pinnedNotes.slice(0, 3).map((n: NoteItem) => `《${n.title}》`).join('、');
    const extra: string = this.pinnedNotes.length > 3 ? `等共 ${this.pinnedNotes.length} 篇` : '';
    const suggestedPrompt: string = `请结合【${projName}】已挂载的文档（${titles}${extra}），总结核心要点。`;

    this.onStartChatWithContext(suggestedPrompt);
    promptAction.showToast({ message: '已添加上下文' });
  }

  // ------------------------------------------------------------------
  // UI 构件 (Builders)
  // ------------------------------------------------------------------

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(TypographyTokens.TINY)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.palette().inkMuted)
      .width('100%')
      .padding({ bottom: 4 })
  }

  /** 顶栏标签切换 */
  @Builder
  tabBar() {
    Row({ space: 4 }) {
      // 目录与工程 Tab
      Row({ space: 5 }) {
        Text('▤')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.activeTab === 'explorer' ? this.palette().accent : this.palette().inkMuted)
        Text('目录')
          .fontSize(TypographyTokens.TINY)
          .fontWeight(this.activeTab === 'explorer' ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.activeTab === 'explorer' ? this.palette().accent : this.palette().inkMuted)
        if (this.pinnedNotes.length > 0) {
          Text(`${this.pinnedNotes.length}`)
            .fontSize(TypographyTokens.TINY)
            .fontColor(Color.White)
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .borderRadius(6)
            .backgroundColor(this.palette().accent)
        }
      }
      .layoutWeight(1)
      .height(28)
      .justifyContent(FlexAlign.Center)
      .borderRadius(6)
      .backgroundColor(this.activeTab === 'explorer' ? this.palette().accentSoft : Color.Transparent)
      .animation({ duration: 180, curve: Curve.EaseInOut })
      .onClick(() => {
        this.activeTab = 'explorer';
      })

      // 溯源与工具 Tab
      Row({ space: 5 }) {
        Text('⚙')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.activeTab === 'tools' ? this.palette().accent : this.palette().inkMuted)
        Text('工具')
          .fontSize(TypographyTokens.TINY)
          .fontWeight(this.activeTab === 'tools' ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.activeTab === 'tools' ? this.palette().accent : this.palette().inkMuted)
        Circle({ width: 6, height: 6 })
          .fill(this.toolsEnabled ? '#22C55E' : '#787774')
      }
      .layoutWeight(1)
      .height(28)
      .justifyContent(FlexAlign.Center)
      .borderRadius(6)
      .backgroundColor(this.activeTab === 'tools' ? this.palette().accentSoft : Color.Transparent)
      .animation({ duration: 180, curve: Curve.EaseInOut })
      .onClick(() => {
        this.activeTab = 'tools';
      })
    }
    .width('100%')
    .padding(2)
    .borderRadius(6)
    .backgroundColor(this.palette().surfaceSubtle)
  }

  /** Project 切换栏与新建按键 */
  @Builder
  projectHeaderSection() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        // 当前工程指示器与下拉触发器
        Row({ space: 4 }) {
          Text(this.selectedProjectFilter.length > 0 ? '📁' : '🌐')
            .fontSize(TypographyTokens.CAPTION)
          Text(this.selectedProjectFilter.length > 0 ? this.selectedProjectFilter : '全部资料')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.projectDropdownOpen ? '▲' : '▼')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .layoutWeight(1)
        .height(30)
        .padding({ left: 8, right: 8 })
        .borderRadius(6)
        .backgroundColor(this.palette().surfaceSubtle)
        .border({ width: 1, color: this.palette().borderSubtle })
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
            this.projectDropdownOpen = !this.projectDropdownOpen;
          });
        })

        // + 新建 Project 快捷按键
        Row({ space: 2 }) {
          Text('+')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().accent)
          Text('新建')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().accent)
        }
        .height(30)
        .padding({ left: 8, right: 8 })
        .borderRadius(6)
        .backgroundColor(this.palette().accentSoft)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          animateTo({ curve: curves.springMotion(0.28, 0.76) }, () => {
            this.isCreatingProject = !this.isCreatingProject;
          });
        })
      }
      .width('100%')

      // 下拉工程选择菜单
      if (this.projectDropdownOpen) {
        Column({ space: 2 }) {
          // 全部工程项
          Row({ space: 6 }) {
            Text('🌐')
              .fontSize(TypographyTokens.TINY)
            Text('全部资料')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.selectedProjectFilter === '' ? this.palette().accent : this.palette().inkPrimary)
              .fontWeight(this.selectedProjectFilter === '' ? FontWeight.Bold : FontWeight.Normal)
              .layoutWeight(1)
            if (this.selectedProjectFilter === '') {
              Text('✓')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().accent)
            }
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .borderRadius(4)
          .backgroundColor(this.selectedProjectFilter === '' ? this.palette().accentSoft : Color.Transparent)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.selectedProjectFilter = '';
            this.projectDropdownOpen = false;
          })

          // 各项目选项
          ForEach(this.spaces, (sp: SpaceFolder) => {
            Row({ space: 6 }) {
              Circle({ width: 6, height: 6 })
                .fill(sp.color || '#4F46E5')
              Text(sp.name)
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.selectedProjectFilter === sp.name ? this.palette().accent : this.palette().inkPrimary)
                .fontWeight(this.selectedProjectFilter === sp.name ? FontWeight.Bold : FontWeight.Normal)
                .layoutWeight(1)
              Text(`${sp.count} 篇`)
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
              if (this.selectedProjectFilter === sp.name) {
                Text('✓')
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().accent)
              }
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .borderRadius(4)
            .backgroundColor(this.selectedProjectFilter === sp.name ? this.palette().accentSoft : Color.Transparent)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.selectedProjectFilter = sp.name;
              this.projectDropdownOpen = false;
            })
          }, (sp: SpaceFolder) => `opt-${sp.id}`)
        }
        .width('100%')
        .padding(4)
        .borderRadius(6)
        .backgroundColor(this.palette().surface)
        .border({ width: 1, color: this.palette().border })
        .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)' })
      }

      // 新建工程内嵌面板
      if (this.isCreatingProject) {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text('✦ 新建工程')
              .fontSize(TypographyTokens.TINY)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)
              .layoutWeight(1)
            Text('✕')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
              .onClick(() => {
                this.isCreatingProject = false;
              })
          }
          .width('100%')

          TextInput({
            text: this.newProjectName,
            placeholder: '工程名称，如：HarmonyOS开发'
          })
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkPrimary)
            .placeholderColor(this.palette().inkMuted)
            .height(28)
            .backgroundColor(this.palette().surface)
            .border({ width: 1, color: this.palette().borderSubtle })
            .borderRadius(4)
            .onChange((v: string) => {
              this.newProjectName = v;
            })

          // 色标选择
          Row({ space: 6 }) {
            Text('色标:')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
            ForEach(PRESET_PROJECT_COLORS, (color: string) => {
              Circle({ width: 12, height: 12 })
                .fill(color)
                .stroke(this.newProjectColor === color ? this.palette().inkPrimary : Color.Transparent)
                .strokeWidth(2)
                .onClick(() => {
                  this.newProjectColor = color;
                })
            }, (c: string) => c)
          }
          .width('100%')

          Row({ space: 6 }) {
            Button('创建工程')
              .type(ButtonType.Normal)
              .fontSize(TypographyTokens.TINY)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor(this.palette().accent)
              .borderRadius(4)
              .height(26)
              .layoutWeight(1)
              .onClick(() => {
                this.handleCreateProject();
              })

            Button('取消')
              .type(ButtonType.Normal)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
              .backgroundColor(this.palette().surfaceSubtle)
              .borderRadius(4)
              .height(26)
              .onClick(() => {
                this.isCreatingProject = false;
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding(8)
        .borderRadius(6)
        .backgroundColor(this.palette().surfaceSubtle)
        .border({ width: 1, color: this.palette().accent })
      }
    }
    .width('100%')
  }

  /** 当前对话挂载上下文工作集 (Active Working Set) */
  @Builder
  workingSetSection() {
    if (this.pinnedNotes.length > 0) {
      Column({ space: 6 }) {
        // 头部与计数
        Row({ space: 6 }) {
          Text('📌')
            .fontSize(TypographyTokens.TINY)
          Text('已挂载')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
          Text(`(${this.pinnedNotes.length})`)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().accent)
            .fontWeight(FontWeight.Medium)

          Blank()

          Text('清空')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => {
              this.onClearPinnedNotes();
              promptAction.showToast({ message: '已清空挂载' });
            })
        }
        .width('100%')

        // 已挂载药丸标签
        Flex({ wrap: FlexWrap.Wrap, space: { main: { value: 4, unit: 0 }, cross: { value: 4, unit: 0 } } }) {
          ForEach(this.pinnedNotes, (note: NoteItem) => {
            Row({ space: 4 }) {
              Text(this.getFileIcon(note))
                .fontSize(TypographyTokens.TINY)
              Text(note.title)
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 120 })
              Text('✕')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
                .padding({ left: 2, right: 2 })
                .onClick(() => {
                  this.onRemovePinnedNote(note.id);
                })
            }
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(this.palette().accentSoft)
            .border({ width: 1, color: this.palette().borderSubtle })
          }, (note: NoteItem) => `work-${note.id}`)
        }
        .width('100%')
      }
      .width('100%')
      .padding(8)
      .borderRadius(6)
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: 1, color: this.palette().borderSubtle })
    }
  }

  /** Antigravity 目录树与文件列表 */
  @Builder
  directoryTreeSection() {
    Column({ space: 6 }) {
      // 目录搜索过滤
      Row({ space: 6 }) {
        Text('🔍')
          .fontSize(TypographyTokens.TINY)
        TextInput({
          text: this.searchKeyword,
          placeholder: '搜索文档…'
        })
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkPrimary)
          .placeholderColor(this.palette().inkMuted)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .height(28)
          .onChange((v: string) => {
            this.searchKeyword = v;
          })

        if (this.searchKeyword.length > 0) {
          Text('✕')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .onClick(() => {
              this.searchKeyword = '';
            })
        }
      }
      .width('100%')
      .padding({ left: 8, right: 6 })
      .borderRadius(6)
      .backgroundColor(this.palette().surfaceSubtle)
      .border({ width: 1, color: this.palette().borderSubtle })

      // 目录树
      Column({ space: 4 }) {
        ForEach(this.filteredSpaces(), (sp: SpaceFolder) => {
          this.folderTreeNode(sp)
        }, (sp: SpaceFolder) => `tree-${sp.id}-${sp.name}`)
      }
      .width('100%')
    }
    .width('100%')
  }

  /** 目录树文件夹节点 */
  @Builder
  folderTreeNode(space: SpaceFolder) {
    Column({ space: 2 }) {
      // 文件夹行
      Row({ space: 6 }) {
        // 折叠展开箭头
        Text(this.isFolderExpanded(space) ? '▼' : '▶')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width(14)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.toggleFolderExpand(space);
          })

        // 文件夹图标与名称
        Text(space.icon || '📁')
          .fontSize(TypographyTokens.CAPTION)
        Text(space.name)
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .onClick(() => {
            this.toggleFolderExpand(space);
          })

        Text(`${space.notes?.length ?? space.count}`)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)

        // 目录级批量挂载按键 (Antigravity 标志性功能)
        Row({ space: 2 }) {
          Text(this.isFolderFullyPinned(space) ? '✓ 已挂载' : '+ 挂载')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.isFolderFullyPinned(space) ? this.palette().accent : this.palette().inkMuted)
        }
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.isFolderFullyPinned(space) ? this.palette().accentSoft : Color.Transparent)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.toggleFolderPinBatch(space);
        })
      }
      .width('100%')
      .height(28)
      .padding({ left: 6, right: 6 })
      .borderRadius(6)
      .backgroundColor(this.palette().surfaceSubtle)

      // 展开的子文件列表
      if (this.isFolderExpanded(space)) {
        Column({ space: 2 }) {
          if ((space.notes ?? []).length === 0) {
            Row() {
              Text('目录为空')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
            }
            .padding({ left: 24, top: 4, bottom: 4 })
          } else {
            ForEach(space.notes ?? [], (note: NoteItem) => {
              this.fileTreeNode(note)
            }, (note: NoteItem) => `file-${note.id}`)
          }
        }
        .width('100%')
        .padding({ left: 12, top: 2, bottom: 4 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 文件节点 */
  @Builder
  fileTreeNode(note: NoteItem) {
    Row({ space: 6 }) {
      Text(this.getFileIcon(note))
        .fontSize(TypographyTokens.TINY)

      Text(note.title)
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      // 挂载 / 移除操作
      if (this.pinnedNotes.some((n: NoteItem) => n.id === note.id)) {
        Row() {
          Text('✓')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().accent)
        }
        .width(22)
        .height(22)
        .justifyContent(FlexAlign.Center)
        .borderRadius(4)
        .backgroundColor(this.palette().accentSoft)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.onRemovePinnedNote(note.id);
        })
      } else {
        Row() {
          Text('+')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .width(22)
        .height(22)
        .justifyContent(FlexAlign.Center)
        .borderRadius(4)
        .backgroundColor(Color.Transparent)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.onAddPinnedNote(note);
        })
      }
    }
    .width('100%')
    .height(26)
    .padding({ left: 6, right: 6 })
    .borderRadius(4)
    .hoverEffect(HoverEffect.Highlight)
  }

  /** 溯源切片 (RAG Hits) */
  @Builder
  citationsSection() {
    Column({ space: 6 }) {
      this.sectionTitle(this.citations.length > 0 ? `知识溯源切片 (${this.citations.length})` : '知识溯源切片')

      if (this.citations.length === 0) {
        Row() {
          Text('本次回答未触发跨库切片检索。')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
        .padding(8)
        .borderRadius(6)
        .backgroundColor(this.palette().surfaceSubtle)
      } else {
        ForEach(this.citations, (c: ChatCitation) => {
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Text(c.noteTitle)
                .fontSize(TypographyTokens.TINY)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.palette().inkPrimary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text(`${Math.round(c.score * 100)}% 匹配`)
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().accent)
                .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                .borderRadius(4)
                .backgroundColor(this.palette().accentSoft)
            }
            .width('100%')

            if (c.headingPath.length > 0) {
              Text(`§ ${c.headingPath}`)
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }

            Text(c.chunkText)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .lineHeight(16)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(8)
          .borderRadius(6)
          .backgroundColor(this.palette().surfaceSubtle)
          .border({ width: 1, color: this.palette().borderSubtle })
          .margin({ bottom: 4 })
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.onPreviewSource(c))
        }, (c: ChatCitation) => `${c.noteId}-${c.headingPath}-${c.score}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 智能体工具箱 Tab */
  @Builder
  toolsTabContent() {
    Column({ space: 12 }) {
      // 工具总控开关
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text('Function Calling 工具箱')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary)
          Text(this.toolsEnabled ? '已允许模型自主调用工具' : '已停用（纯文本直答）')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.toolsEnabled ? this.palette().accent : this.palette().inkMuted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.toolsEnabled })
          .selectedColor(this.palette().accent)
          .onChange((isOn: boolean) => {
            this.onToggleTools(isOn);
          })
      }
      .width('100%')
      .padding(10)
      .borderRadius(8)
      .backgroundColor(this.palette().surfaceSubtle)

      // 5 大原生工具卡片清单
      Column({ space: 6 }) {
        this.sectionTitle('注册智能体工具 (5/5)')

        this.toolItemRow('search_notes', '知识库切片检索', '检索与关键词最匹配的笔记段落', '只读 · 自动', true)
        this.toolItemRow('list_notes', '目录与分类遍历', '获取指定分类或全部笔记目录', '只读 · 自动', true)
        this.toolItemRow('read_note', '单篇笔记全文精读', '按标题或 ID 获取完整文档内容', '只读 · 自动', true)
        this.toolItemRow('summarize_vault', '知识库全景资产统计', '统计笔记数、双链与待办概况', '只读 · 自动', true)
        this.toolItemRow('create_todo', '智能规划新建待办', '将分析行动项落盘为真实待办', '写操作 · 需确认', false)
      }
      .width('100%')

      // 溯源切片展示在工具页底部
      this.citationsSection()

      // 安全机制说明
      Column({ space: 4 }) {
        Text('🛡 安全护栏与闭环准则')
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkSecondary)
        Text('只读检索工具在沙箱内秒级执行；任何修改或新增数据的操作（如新建待办），均会在执行前向您弹出二次确认卡片。')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .lineHeight(16)
      }
      .width('100%')
      .padding(8)
      .borderRadius(6)
      .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.02)' : 'rgba(0,0,0,0.02)')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  toolItemRow(name: string, title: string, desc: string, perm: string, isRead: boolean) {
    Column({ space: 2 }) {
      Row({ space: 6 }) {
        Circle({ width: 6, height: 6 })
          .fill(this.toolsEnabled ? (isRead ? '#22C55E' : '#3B82F6') : '#787774')
        Text(title)
          .fontSize(TypographyTokens.TINY)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkPrimary)
          .layoutWeight(1)
        Text(perm)
          .fontSize(TypographyTokens.TINY)
          .fontColor(isRead ? this.palette().inkMuted : this.palette().accent)
          .padding({ left: 4, right: 4, top: 1, bottom: 1 })
          .borderRadius(4)
          .backgroundColor(this.palette().surfaceSubtle)
      }
      .width('100%')

      Text(desc)
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().inkMuted)
        .padding({ left: 12 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(8)
    .borderRadius(6)
    .backgroundColor(this.palette().surfaceSubtle)
    .border({ width: 1, color: this.palette().borderSubtle })
  }

  build() {
    Column() {
      // 1. 顶栏 (Header)
      Row({ space: 8 }) {
        Row({ space: 6 }) {
          Text('▤')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().accent)
          Text('工程上下文')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
        }
        .layoutWeight(1)

        Text('✕')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width(24).height(24)
          .textAlign(TextAlign.Center)
          .borderRadius(4)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.onClose())
      }
      .width('100%')
      .height(38)
      .padding({ left: 12, right: 8 })
      .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })

      // 2. Tab 分段滑块
      Row() {
        this.tabBar()
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 6, bottom: 6 })

      // 3. 滚动主体
      Scroll() {
        Column({ space: 10 }) {
          if (this.activeTab === 'explorer') {
            // Project 切换器与新建
            this.projectHeaderSection()

            // 当前对话挂载上下文工作集
            this.workingSetSection()

            // Antigravity 目录树与文件列表
            this.directoryTreeSection()
          } else {
            // 智能体工具箱与溯源切片
            this.toolsTabContent()
          }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .padding({ left: 10, right: 10, bottom: 12 })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)

      // 4. 底栏：模型状态与配置直达
      Row({ space: 6 }) {
        Circle({ width: 6, height: 6 })
          .fill(this.modelLabel.includes('未配') ? '#F59E0B' : '#22C55E')
        Text(this.modelLabel.length > 0 ? this.modelLabel : '未配置模型')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text('⚙ 设置')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().accent)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(4)
          .backgroundColor(this.palette().accentSoft)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.onOpenModelSettings())
      }
      .width('100%')
      .height(34)
      .padding({ left: 10, right: 10 })
      .border({ width: { top: 1 }, color: { top: this.palette().borderSubtle } })
      .backgroundColor(this.palette().surface)
    }
    .width(LayoutTokens.CONTEXT_PANEL_WIDTH)
    .height('100%')
    .backgroundColor(this.palette().sidebar)
    .border({ width: { left: 1 }, color: { left: this.palette().borderSubtle } })
  }
}
