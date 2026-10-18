/**
 * 研读正文 (T3.1)
 *
 * Notion 风格排版：28vp 大标题 + 轻量元数据行 + Markdown 块级渲染。
 * 支持「阅读 / 编辑」模式切换；输入变化触发 800ms 防抖，
 * 保存交给上层 ReaderCommitService，正文与快照在同一个用例队列中处理。
 */
import { common } from '@kit.AbilityKit';
import { KeyCode } from '@kit.InputKit';
import { curves, KeyboardAvoidMode, promptAction } from '@kit.ArkUI';
import { ColorPalette, LayoutTokens, TypographyTokens, AnimationTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { MarkdownDocument } from '../../common/types/MarkdownDocument';
import { MarkdownOutlineItem } from '../../common/types/MarkdownOutlineItem';
import { NoteStorageService } from '../../services/NoteStorageService';
import { ReaderSaveKind } from '../../common/types/ReaderSaveKind';
import { TimeFormat } from '../../common/utils/TimeFormat';
import { SAVE_FAILED, SAVE_IDLE, SAVE_SAVING } from '../../common/constants/WorkspaceConstants';
import { NoteCoverVisual } from './NoteCoverVisual';
import { AppIcon } from '../common/AppIcon';
import { IconButton } from '../common/IconButton';
import { SystemShareService } from '../../services/SystemShareService';
import { DocumentText } from '../common/DocumentText';
import { DocumentTextParser, DocumentBlock, DocumentSpan } from '../../services/document/DocumentTextParser';
import { HuaweiDocActionDialog, HuaweiDocDialogType } from './huawei/HuaweiDocActionDialog';
import { ReaderOutputService } from '../../services/document/ReaderOutputService';
import { MarkdownEditing, MarkdownEdit, MarkdownHistory } from '../../services/document/MarkdownEditing';
import { copyNote } from '../../common/utils/NoteSnapshot';
import { MarkdownLinkService } from '../../services/document/MarkdownLinkService';

/** 输入停止后延迟落盘的毫秒数 */
const AUTOSAVE_DELAY_MS: number = 800;

/** 格式工具栏按钮定义（简约文本风格，非 emoji） */
interface FormatAction {
  label: string;
  action: string;
  tip: string;
}

const FORMAT_ACTIONS: FormatAction[] = [
  { label: 'B', action: 'bold', tip: '粗体' },
  { label: 'I', action: 'italic', tip: '斜体' },
  { label: 'S', action: 'strike', tip: '删除线' },
  { label: 'H₁', action: 'h1', tip: '一级标题' },
  { label: 'H₂', action: 'h2', tip: '二级标题' },
  { label: 'H₃', action: 'h3', tip: '三级标题' },
  { label: '•', action: 'bullet', tip: '无序列表' },
  { label: '1.', action: 'ordered', tip: '有序列表' },
  { label: '☐', action: 'task', tip: '待办项' },
  { label: '❝', action: 'quote', tip: '引用' },
  { label: '⟨⟩', action: 'code', tip: '行内代码' },
  { label: '```', action: 'fence', tip: '代码块' },
  { label: '表', action: 'table', tip: '表格' },
  { label: 'URL', action: 'url', tip: '网页链接' },
  { label: '—', action: 'divider', tip: '分割线' },
  { label: '[[]]', action: 'link', tip: '双向链接' },
  { label: '#', action: 'tag', tip: '标签' }
];


/** 正文行内片段（用于给 [[双链]] 与 #标签 上色） */
interface TextSegment {
  kind: string; // 'text' | 'link' | 'tag'
  text: string;
}

/** 正文块级元素 */
interface MarkdownBlock {
  kind: string; // 'heading' | 'paragraph' | 'quote' | 'bullet' | 'ordered' | 'task' | 'code' | 'divider' | 'gap'
  level: number;
  text: string;
  /** 该块在正文中的起始行号（0 基），用于大纲锚点定位 */
  line: number;
  /** 仅 task 块使用：勾选框是否已勾选 */
  checked?: boolean;
  marker?: string;
}

/** 待办行解析结果 */
interface TaskParse {
  checked: boolean;
  text: string;
}

@Component
export struct MarkdownReader {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop @Watch('handleBackRequest') backRequestToken: number = 0;
  @Prop @Watch('saveForHost') saveRequestToken: number = 0;
  @Prop inputLocked: boolean = false;
  @Prop companionPane: boolean = false;
  @Prop compactPane: boolean = false;
  @Prop showBackButton: boolean = true;
  @Prop manageKeyboardMode: boolean = true;
  @Prop showCompanionAction: boolean = false;
  onOpenCompanion: () => void = () => {};
  onSaveRequestFinished: (ok: boolean, noteId: string, token: number) => void = () => {};
  onRequestClose: () => void = () => {};
  /** 大纲锚点跳转令牌：每次自增即触发一次定位 */
  @Prop @Watch('onJumpRequest') jumpToken: number = 0;
  /** 待定位的目标行号（0 基），配合 jumpToken 使用 */
  @Prop jumpLine: number = -1;
  /** 上层用例负责正文与快照持久化，成功后才能更新保存状态 */
  onSaved: (note: NoteItem, content: string, kind?: ReaderSaveKind) => Promise<void> = async () => {};
  onChooseCover: () => void = () => {};
  @Prop favorite: boolean = false;
  @Prop annotationPaneOpen: boolean = false;
  onToggleFavorite: () => void = () => {};
  onToggleAnnotation: () => void = () => {};
  onDeleteNote: () => void = () => {};
  /** 落盘状态变化：已保存 / 保存中 / 保存失败 */
  onSaveStateChange: (state: string) => void = () => {};
  /** 正文块解析完成后回传大纲，供 OutlinePanel 复用 */
  onOutlineUpdated: (items: MarkdownOutlineItem[]) => void = () => {};
  /** 点击正文中的 [[双链]] 跳转打开目标笔记 */
  onOpenNoteByTitle: (title: string) => void = () => {};

  @State title: string = '';
  @State content: string = '';
  @State blocks: MarkdownBlock[] = [];
  @State isEditing: boolean = false;
  @State saveState: string = SAVE_IDLE;
  @State editorFocused: boolean = false;
  @State displayUpdateTime: string = '';
  /** 格式工具栏是否可见（键盘弹出时显示，收起时隐藏） */
  @State isFormatBarVisible: boolean = false;
  @State private previewVisible: boolean = false;
  @State private canUndo: boolean = false;
  @State private canRedo: boolean = false;
  private history: MarkdownHistory = new MarkdownHistory();
  private saveInFlight: Promise<void> | null = null;
  private loadGeneration: number = 0;
  @State private documentLoading: boolean = false;

  private storage: NoteStorageService = new NoteStorageService();
  private scroller: Scroller = new Scroller();
  private textAreaController: TextAreaController = new TextAreaController();
  private saveTimer: number = -1;
  private loadedNoteId: string = '';
  private isDirty: boolean = false;
  /**
   * 当前正文（this.content）真正归属的笔记。
   * 必须与 @Prop note 解耦：切换笔记时 ArkUI 会先替换 this.note，
   * 若落盘时读取 this.note 会把 A 的正文写进 B 的 .md 文件。
   */
  private editingNote: NoteItem | null = null;

  /** 编辑区当前选区（字符索引），由 TextArea.onTextSelectionChange 实时维护，供格式动作定位 */
  private selStart: number = 0;
  private selEnd: number = 0;

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;
  @State private shareBusy: boolean = false;
  @State private outputAction: HuaweiDocDialogType = '';
  @State private outputMessage: string = '';
  @State private outputFailed: boolean = false;
  @State private actionMenuOpen: boolean = false;
  private previousKeyboardMode: KeyboardAvoidMode = KeyboardAvoidMode.OFFSET;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  aboutToAppear(): void {
    // 键盘避让用 RESIZE：页面可用高度被键盘压缩，底部悬浮的编辑工具栏
    // 会自动贴到键盘正上方并跟随升降，无需手动监听键盘高度。
    if (this.manageKeyboardMode) {
      this.previousKeyboardMode = this.getUIContext().getKeyboardAvoidMode();
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    }
    this.loadDocument();
  }

  aboutToDisappear(): void {
    if (this.manageKeyboardMode) { this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardMode); }
    // 离开研读页时立即落盘，避免 800ms 窗口内的输入丢失
    this.flushSave();
  }

  onNoteChanged(propName: string): void {
    if (this.note.id === this.loadedNoteId) {
      // 同一篇笔记的元数据被外部改动（重命名 / 移动分类）：同步到正文归属副本，
      // 否则下一次自动保存会用旧的 title/category 把改动覆盖回去。
      this.syncExternalMeta();
      return;
    }
    // 先落盘上一篇正文，再加载新文档，保证写入的是正确的 .md 文件
    this.switchNote();
  }

  /** 外部改动同一篇笔记的标题/分类时，同步到本地编辑态，避免自动保存回退 */
  private syncExternalMeta(): void {
    const titleEdited = this.editingNote !== null && this.title !== this.editingNote.title;
    if (this.editingNote !== null) {
      this.editingNote.title = this.note.title;
      this.editingNote.category = this.note.category;
      this.editingNote.coverUrl = this.note.coverUrl;
      this.editingNote.tag = this.note.tag;
      this.editingNote.tagColor = this.note.tagColor;
      this.editingNote.updateTime = this.note.updateTime;
      this.editingNote.updatedAt = this.note.updatedAt;
      this.editingNote.tags = this.note.tags;
      this.editingNote.favorite = this.note.favorite;
      this.editingNote.isPinned = this.note.isPinned;
      this.editingNote.pdfTextJson = this.note.pdfTextJson;
    }
    if (!titleEdited) { this.title = this.note.title; }
  }

  /** 切换笔记：等待上一篇落盘完成后再读取新笔记正文 */
  private async switchNote(): Promise<void> {
    this.outputAction = ''; this.outputMessage = ''; this.shareBusy = false;
    await this.flushSave();
    if (this.isDirty) { return; }
    await this.loadDocument();
  }

  /** 大纲点击后由父组件递增 jumpToken 触发平滑锚点定位 */
  onJumpRequest(propName: string): void {
    if (this.jumpLine < 0 || this.blocks.length === 0) {
      return;
    }
    let target: number = 0;
    for (let i = 0; i < this.blocks.length; i++) {
      if (this.blocks[i].line <= this.jumpLine) {
        target = i;
      } else {
        break;
      }
    }
    this.scroller.scrollToIndex(target, true, ScrollAlign.START);
  }

  // ------------------------------------------------------------------
  // 数据：读取与落盘
  // ------------------------------------------------------------------

  private async loadDocument(): Promise<void> {
    this.documentLoading = true;
    const generation = ++this.loadGeneration;
    const source = this.cloneNote(this.note);
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    // 绑定正文归属：复制一份笔记元数据，避免 @Prop note 被切换时连带改写归属
    this.editingNote = this.cloneNote(this.note);
    this.loadedNoteId = this.note.id;
    this.title = this.note.title;
    this.displayUpdateTime = this.note.updateTime;
    this.isDirty = false;
    this.editorFocused = false;
    try {
      const document: MarkdownDocument = await this.storage.read(context, source);
      if (generation !== this.loadGeneration || this.note.id !== source.id) { return; }
      this.applyContent(document.content);
    } catch (error) {
      if (generation !== this.loadGeneration || this.note.id !== source.id) { return; }
      // 文件不可读时回退到元数据快照中的正文，绝不丢弃用户内容
      console.error(`研读正文读取失败: ${JSON.stringify(error)}`);
      this.applyContent(source.contentDetail);
    }
    // Reading is the default even for a newly created blank document.
    this.documentLoading = false;
    this.isEditing = false;
  }

  /** 复制笔记元数据，用于把「正文归属」与可变的 @Prop note 彻底解耦 */
  private cloneNote(source: NoteItem): NoteItem {
    return copyNote(source);
  }

  private applyContent(next: string): void {
    this.history.reset(); this.canUndo = false; this.canRedo = false;
    this.selStart = 0; this.selEnd = 0; this.previewVisible = false;
    this.content = next;
    this.blocks = this.parseBlocks(next);
    this.saveState = SAVE_IDLE;
    this.onSaveStateChange(SAVE_IDLE);
    this.onOutlineUpdated(this.collectOutline(this.blocks));
  }

  /** 从块列表中抽取标题，生成大纲 */
  private collectOutline(blocks: MarkdownBlock[]): MarkdownOutlineItem[] {
    const items: MarkdownOutlineItem[] = [];
    for (let i = 0; i < blocks.length; i++) {
      if (blocks[i].kind === 'heading') {
        items.push({ level: blocks[i].level, text: blocks[i].text, line: blocks[i].line });
      }
    }
    return items;
  }

  private scheduleSave(): void {
    this.isDirty = true;
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
    }
    this.saveState = SAVE_SAVING;
    this.onSaveStateChange(SAVE_SAVING);
    this.saveTimer = setTimeout(() => {
      this.flushSave();
    }, AUTOSAVE_DELAY_MS);
  }

  private async flushSave(): Promise<void> {
    if (this.saveTimer !== -1) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    if (this.saveInFlight !== null) {
      await this.saveInFlight;
      // Another waiter may already have started a newer commit; join it as well.
      if (this.saveState !== SAVE_FAILED) { await this.flushSave(); }
      return;
    }
    // 落盘对象取自正文归属笔记 this.editingNote，绝不使用可能已被切换的 this.note
    const target: NoteItem | null = this.editingNote;
    if (!this.isDirty || target === null || target.id.length === 0) {
      return;
    }
    this.isDirty = false;

    const snapshot: NoteItem = this.buildSnapshot(target);
    this.saveInFlight = this.commitSnapshot(snapshot);
    try { await this.saveInFlight; } finally { this.saveInFlight = null; }
    if (this.isDirty && this.saveState !== SAVE_FAILED) { await this.flushSave(); }
  }

  private async commitSnapshot(snapshot: NoteItem): Promise<void> {
    try {
      await this.onSaved(snapshot, snapshot.contentDetail, 'markdown');
      if (this.content !== snapshot.contentDetail || (this.title.trim() || '未命名笔记') !== snapshot.title || this.editingNote?.id !== snapshot.id) { return; }
      this.saveState = SAVE_IDLE;
      this.displayUpdateTime = snapshot.updateTime;
      this.onSaveStateChange(SAVE_IDLE);
    } catch (error) {
      // 保存失败必须显式暴露，不能伪装成成功
      console.error(`Markdown 正文保存失败: ${JSON.stringify(error)}`);
      this.isDirty = true;
      this.saveState = SAVE_FAILED;
      this.onSaveStateChange(SAVE_FAILED);
    }
  }

  private buildSnapshot(note: NoteItem): NoteItem {
    const plain: string = this.content.replace(/[#>*`\[\]]/g, ' ').replace(/\s+/g, ' ').trim();
    const preview: string = plain.length > 48 ? `${plain.substring(0, 48)}…` : plain;
    const snapshot = copyNote(note);
    snapshot.title = this.title.trim() || '未命名笔记'; snapshot.previewText = preview;
    snapshot.updateTime = TimeFormat.now(); snapshot.contentDetail = this.content;
    return snapshot;
  }

  // ------------------------------------------------------------------
  // 解析：块级与行内
  // ------------------------------------------------------------------

  private parseBlocks(source: string): MarkdownBlock[] {
    const lines = source.replace(/\r\n?/g, '\n').split('\n');
    return DocumentTextParser.parse(source).map((block: DocumentBlock): MarkdownBlock => {
      const task = block.kind === 'list' ? this.parseTask(lines[block.line].trim()) : null;
      let kind = block.kind;
      if (kind === 'list') { kind = task ? 'task' : /^\d/.test(block.marker) ? 'ordered' : 'bullet'; }
      const rich = kind === 'table' || kind === 'math' || kind === 'code';
      return { kind: kind, level: block.level, line: block.line, marker: block.marker,
        text: task ? task.text : rich ? lines.slice(block.line, block.endLine + 1).join('\n') : block.text,
        checked: task ? task.checked : undefined };
    });
  }

  /**
   * 解析待办项：`- [ ] 文本` / `- [x] 文本`（`*` 亦可，`[X]` 视为已勾选）。
   * 非待办项返回 null。方括号后允许紧跟空格或直接结束。
   */
  private parseTask(trimmed: string): TaskParse | null {
    const task = trimmed.match(/^[-*+][ \t]+\[([ xX])\](?:[ \t]+(.*)|$)/);
    return task ? { checked: task[1] !== ' ', text: task[2] || '' } : null;
  }

  private editorSelection(): MarkdownEdit {
    return MarkdownEditing.selection(this.content, this.selStart, this.selEnd);
  }

  private applyEdit(edit: MarkdownEdit, record: boolean = true): void {
    if (record) { this.history.record(this.editorSelection(), edit); }
    this.setContent(edit.text);
    this.selStart = edit.start; this.selEnd = edit.end;
    this.canUndo = this.history.canUndo(); this.canRedo = this.history.canRedo();
    if (this.isEditing && (!this.isPhone || !this.previewVisible)) { this.textAreaController.setTextSelection(edit.start, edit.end); }
  }

  private changeText(value: string): void {
    if (value === this.content) { return; }
    const before = this.editorSelection();
    let prefix = 0, suffix = 0;
    while (prefix < before.text.length && prefix < value.length && before.text[prefix] === value[prefix]) { prefix++; }
    while (suffix < before.text.length - prefix && suffix < value.length - prefix &&
      before.text[before.text.length - 1 - suffix] === value[value.length - 1 - suffix]) { suffix++; }
    const cursor = value.length - suffix;
    const next: MarkdownEdit = { text: value, start: cursor, end: cursor };
    this.history.record(before, next, true);
    this.selStart = cursor; this.selEnd = cursor;
    this.canUndo = this.history.canUndo(); this.canRedo = this.history.canRedo();
    this.setContent(value);
  }

  private undoEdit(redo: boolean = false): void {
    const edit = redo ? this.history.redo(this.editorSelection()) : this.history.undo(this.editorSelection());
    if (edit) { this.applyEdit(edit, false); }
  }

  private setContent(next: string): void {
    if (next === this.content) { return; }
    this.content = next;
    this.blocks = this.parseBlocks(next);
    this.onOutlineUpdated(this.collectOutline(this.blocks));
    this.scheduleSave();
  }

  /** 把一行拆成普通文本 / [[双链]] / #标签 三类片段 */
  private splitSegments(line: string): TextSegment[] {
    const segments: TextSegment[] = [];
    let buffer: string = '';
    let index: number = 0;

    while (index < line.length) {
      const char: string = line.charAt(index);
      if (char === '`') {
        const ending = line.indexOf('`', index + 1);
        if (ending > index) { buffer += line.slice(index, ending + 1); index = ending + 1; continue; }
      }
      if (char === '[' && index + 1 < line.length && line.charAt(index + 1) === '[') {
        const end: number = line.indexOf(']]', index + 2);
        if (end > index) {
          if (buffer.length > 0) {
            segments.push({ kind: 'text', text: buffer });
            buffer = '';
          }
          segments.push({ kind: 'link', text: line.substring(index, end + 2) });
          index = end + 2;
          continue;
        }
      }
      if (char === '#' && (index === 0 || /[\s(]/.test(line.charAt(index - 1)))) {
        const tag: string = this.readTag(line, index);
        if (tag.length > 0) {
          if (buffer.length > 0) {
            segments.push({ kind: 'text', text: buffer });
            buffer = '';
          }
          segments.push({ kind: 'tag', text: tag });
          index += tag.length;
          continue;
        }
      }
      buffer += char;
      index++;
    }

    if (buffer.length > 0) {
      segments.push({ kind: 'text', text: buffer });
    }
    return segments;
  }

  /** 读取 #标签（要求 # 后紧跟非空白字符） */
  private readTag(line: string, start: number): string {
    let index: number = start + 1;
    while (index < line.length) {
      const char: string = line.charAt(index);
      if (char === ' ' || char === '\t' || char === '#' || char === '，' || char === '。') {
        break;
      }
      index++;
    }
    if (index === start + 1) {
      return '';
    }
    return line.substring(start, index);
  }

  // ------------------------------------------------------------------
  // 格式工具栏：Markdown 语法插入
  // ------------------------------------------------------------------

  private handleFormatAction(action: string): void {
    this.applyEdit(MarkdownEditing.command(this.editorSelection(), action));
    this.isFormatBarVisible = true;
  }

  /** 进入编辑模式并弹出键盘 */
  private enterEdit(): void {
    if (this.documentLoading) { return; }
    animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
      this.isEditing = true;
    });
  }

  /** 退出编辑模式：收起格式栏 + 落盘 */
  private exitEdit(): void {
    this.editorFocused = false;
    animateTo({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }, () => {
      this.isEditing = false;
      this.isFormatBarVisible = false;
    });
    this.flushSave();
  }


  // ------------------------------------------------------------------
  // 渲染
  // ------------------------------------------------------------------

  @Builder
  richLine(text: string, fontSize: number, weight: FontWeight, color: string) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.splitSegments(text), (segment: TextSegment) => {
        Text() {
          ForEach(DocumentTextParser.spans(segment.text), (span: DocumentSpan) => {
            Span(span.text).fontWeight(span.style === 'bold' ? FontWeight.Bold : weight)
              .fontColor(span.style === 'link' ? this.palette().link : segment.kind === 'link' ? this.palette().link : segment.kind === 'tag' ? this.palette().accent : color)
              .fontStyle(span.style === 'italic' ? FontStyle.Italic : FontStyle.Normal)
              .fontFamily(span.style === 'code' ? 'monospace' : 'sans-serif')
              .decoration({ type: span.style === 'strike' ? TextDecorationType.LineThrough : TextDecorationType.None })
              .onClick(() => {
                if (span.target) { this.openWebLink(span.target); }
                else if (segment.kind === 'link') { this.onOpenNoteByTitle(segment.text.slice(2, -2).split('|')[0].trim()); }
              })
          })
        }
          .fontSize(fontSize)
          .fontWeight(weight)
          .fontColor(segment.kind === 'link' ? this.palette().link
            : (segment.kind === 'tag' ? this.palette().accent : color))
          .decoration(segment.kind === 'link'
            ? { type: TextDecorationType.Underline, color: this.palette().link, style: TextDecorationStyle.DOTTED }
            : { type: TextDecorationType.None })
          .copyOption(CopyOptions.LocalDevice).hoverEffect(segment.kind === 'link' ? HoverEffect.Highlight : HoverEffect.None)

      }, (segment: TextSegment, index: number) => `${index}-${segment.text}`)
    }
    .width('100%')
  }

  private async openWebLink(target: string): Promise<void> {
    try { await MarkdownLinkService.open(this.getUIContext().getHostContext() as common.UIAbilityContext, target); }
    catch { promptAction.showToast({ message: '网页链接未能打开，请检查链接或浏览器', duration: 2000 }); }
  }

  @Builder
  blockView(block: MarkdownBlock) {
    if (block.kind === 'heading') {
      Column() {
        this.richLine(block.text,
          block.level === 1 ? TypographyTokens.TITLE_SECTION + 4
            : (block.level === 2 ? TypographyTokens.TITLE_SUB + 2 : TypographyTokens.TITLE_SUB),
          FontWeight.Bold,
          this.palette().inkPrimary)
      }
      .width('100%')
      .margin({ top: block.level === 1 ? 14 : 10, bottom: 4 })
    } else if (block.kind === 'quote') {
      Column() {
        this.richLine(block.text, TypographyTokens.BODY_REGULAR, FontWeight.Normal, this.palette().inkSecondary)
      }
      .width('100%')
      .padding({ left: 12, top: 2, bottom: 2 })
      .border({ width: { left: 3 }, color: { left: this.palette().border } })
      .margin({ top: 4, bottom: 4 })
    } else if (block.kind === 'task') {
      Row({ space: 8 }) {
        Button(block.checked === true ? '☑' : '☐', { type: ButtonType.Normal })
          .width(44).height(44).padding(0).backgroundColor(Color.Transparent).fontSize(20)
          .fontColor(block.checked === true ? this.palette().accent : this.palette().inkMuted)
          .accessibilityText((block.checked ? '取消完成 ' : '完成 ') + block.text)
          .onClick(() => this.applyEdit(MarkdownEditing.toggleTask(this.editorSelection(), block.line)))
        Column() {
          this.richLine(block.text, TypographyTokens.BODY_LARGE, FontWeight.Normal,
            block.checked === true ? this.palette().inkMuted : this.palette().inkPrimary)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: 6 })
      .margin({ top: 2, bottom: 2 })
    } else if (block.kind === 'bullet') {
      Row({ space: 8 }) {
        Text('•')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkMuted)
        Column() {
          this.richLine(block.text, TypographyTokens.BODY_LARGE, FontWeight.Normal, this.palette().inkPrimary)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: 6 })
      .margin({ top: 2, bottom: 2 })
    } else if (block.kind === 'ordered') {
      Row({ space: 8 }) {
        Text(block.marker || '1.')
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkMuted)
        Column() {
          this.richLine(block.text, TypographyTokens.BODY_LARGE, FontWeight.Normal, this.palette().inkPrimary)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ left: 6 })
      .margin({ top: 2, bottom: 2 })
    } else if (block.kind === 'table' || block.kind === 'math' || block.kind === 'code') {
      DocumentText({ text: block.text })
    } else if (block.kind === 'divider') {
      Divider()
        .strokeWidth(1)
        .color(this.palette().border)
        .margin({ top: 10, bottom: 10 })
    } else if (block.kind === 'gap') {
      Column().height(8).width('100%')
    } else {
      Column() {
        this.richLine(block.text, TypographyTokens.BODY_LARGE, FontWeight.Normal, this.palette().inkPrimary)
      }
      .width('100%')
      .margin({ top: 2, bottom: 2 })
    }
  }

  @Builder
  metaRow() {
    Row({ space: 8 }) {
      Text(this.note.type.length === 0 ? '笔记' : this.note.type)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().inkSecondary)
        .padding({ left: 8, right: 8, top: 2, bottom: 2 })
        .borderRadius(4)
        .backgroundColor(this.palette().surfaceSubtle)
      Text(this.note.tag)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.note.tagColor.length === 0 ? this.palette().inkSecondary : this.note.tagColor)
      Text(`更新于 ${this.displayUpdateTime.length === 0 ? this.note.updateTime : this.displayUpdateTime}`)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().inkMuted)
      Text(`#${this.note.category}`)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().inkMuted)
    }
    .width('100%')
    .margin({ top: 6, bottom: 14 })
  }

  private async handleBackRequest(): Promise<void> {
    if (this.outputAction) { this.closeOutput(); return; }
    if (this.actionMenuOpen) { this.actionMenuOpen = false; return; }
    if (this.isEditing) { this.exitEdit(); }
    await this.flushSave();
    if (this.isDirty || this.documentLoading) { return; }
    this.onRequestClose();
  }

  private async saveForHost(): Promise<void> {
    const token = this.saveRequestToken, noteId = this.loadedNoteId;
    await this.flushSave();
    const ok = !this.isDirty && !this.documentLoading && !this.shareBusy && this.saveState === SAVE_IDLE &&
      noteId === this.loadedNoteId && token === this.saveRequestToken;
    this.onSaveRequestFinished(ok, noteId, token);
  }

  private async openCompanion(): Promise<void> {
    await this.flushSave();
    if (!this.isDirty && !this.documentLoading) { this.onOpenCompanion(); }
  }

  private openOutput(action: HuaweiDocDialogType): void {
    if (this.shareBusy) { return; }
    this.actionMenuOpen = false;
    this.outputAction = action; this.outputMessage = ''; this.outputFailed = false;
  }

  private closeOutput(): void {
    if (!this.shareBusy) { this.outputAction = ''; this.outputMessage = ''; this.outputFailed = false; }
  }

  private async performOutput(extension: string): Promise<void> {
    if (this.shareBusy || !this.outputAction || this.editingNote === null) { return; }
    const snapshot = this.buildSnapshot(this.editingNote);
    const action = this.outputAction;
    this.shareBusy = true; this.outputMessage = ''; this.outputFailed = false;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (action === 'share_text') {
        await SystemShareService.shareText(context, snapshot.title, snapshot.contentDetail);
        if (this.loadedNoteId === snapshot.id) { this.outputMessage = '已打开系统分享面板。是否发送以你在面板中的操作为准。'; }
      } else {
        const result = action === 'export_image' ? await ReaderOutputService.saveScreenshot(context, this.getUIContext(), `markdown-body-${snapshot.id}`, snapshot.title) :
          await this.storage.exportDocument(context, snapshot, extension);
        if (this.loadedNoteId !== snapshot.id) { return; }
        if (result.status === 'cancelled') { this.outputAction = ''; }
        else { this.outputMessage = result.message; this.outputFailed = result.status !== 'exported'; }
      }
    } catch (error) {
      if (this.loadedNoteId === snapshot.id) { this.outputMessage = error instanceof Error ? error.message : '操作未完成，请重试'; this.outputFailed = true; }
    } finally { if (this.loadedNoteId === snapshot.id) { this.shareBusy = false; } }
  }

  private formatIcon(action: string): Resource {
    if (action === 'bold') { return $r('app.media.ic_bold'); }
    if (action === 'italic') { return $r('app.media.ic_italic'); }
    if (action === 'strike') { return $r('app.media.ic_strike'); }
    if (action === 'h1') { return $r('app.media.ic_h1'); }
    if (action === 'h2') { return $r('app.media.ic_h2'); }
    if (action === 'h3') { return $r('app.media.ic_h3'); }
    if (action === 'bullet') { return $r('app.media.ic_list'); }
    if (action === 'ordered') { return $r('app.media.ic_ordered'); }
    if (action === 'task') { return $r('app.media.ic_check'); }
    if (action === 'quote') { return $r('app.media.ic_quote'); }
    if (action === 'code' || action === 'fence') { return $r('app.media.ic_code'); }
    if (action === 'table') { return $r('app.media.ic_page'); }
    if (action === 'url') { return $r('app.media.ic_link'); }
    if (action === 'divider') { return $r('app.media.ic_divider'); }
    if (action === 'link') { return $r('app.media.ic_link'); }
    return $r('app.media.ic_tag');
  }

  @Builder
  formatBarButton(item: FormatAction) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 3 }) {
      AppIcon({ source: this.formatIcon(item.action), tint: this.palette().inkSecondary })
      Text(item.tip).fontSize(10).fontColor(this.palette().inkSecondary).maxLines(1)
      }
    }.width(56).height(56).padding(0).borderRadius(5).backgroundColor(Color.Transparent)
      .accessibilityText(item.tip).bindTips(item.tip).onClick(() => this.handleFormatAction(item.action))
  }

  /** 编辑态底部格式工具栏：紧凑可横向滚动，贴合键盘 */
  @Builder
  formatToolbar() {
    Scroll() {
      Row({ space: 2 }) {
        ForEach(FORMAT_ACTIONS, (item: FormatAction) => {
          this.formatBarButton(item)
        }, (item: FormatAction) => item.action)
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(64)
    .backgroundColor(this.palette().surface)
    .border({ width: { top: 1 }, color: { top: this.palette().borderSubtle } })
    .expandSafeArea([SafeAreaType.KEYBOARD])
    // 消费工具栏区域的点击，避免冒泡到根节点触发退出编辑
    .onClick(() => {})
    .transition(
      TransitionEffect.move(TransitionEdge.BOTTOM)
        .combine(TransitionEffect.OPACITY)
        .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
    )
  }

  /** 顶部极简工具栏：阅读/编辑切换 + 双链快捷动作 + 落盘状态 */
  @Builder
  readerActionsMenu() {
    Menu() {
      if (this.showCompanionAction) {
        MenuItem({ content: '分屏阅读', startIcon: $r('app.media.ic_split') })
          .onClick(() => { this.actionMenuOpen = false; this.openCompanion(); })
      }
      MenuItem({ content: '分享笔记文字', startIcon: $r('app.media.ic_share') }).onClick(() => this.openOutput('share_text'))
      if (!this.companionPane) {
      MenuItem({ content: '更换或移除封面', startIcon: $r('app.media.ic_cover') }).onClick(() => { this.actionMenuOpen = false; this.onChooseCover(); })
      MenuItem({ content: '移至回收站', startIcon: $r('app.media.ic_trash') }).onClick(() => { this.actionMenuOpen = false; this.requestDelete(); })
      }
    }
  }

  private async requestDelete(): Promise<void> {
    if (this.shareBusy) { return; }
    if (this.isEditing || this.isDirty) { await this.flushSave(); }
    if (this.isDirty) { return; }
    const noteId = this.note.id;
    const result = await promptAction.showDialog({ title: '移至回收站？', message: '之后可在回收站恢复',
      buttons: [{ text: '取消', color: this.palette().inkSecondary }, { text: '移至回收站', color: this.palette().danger }] });
    if (result.index === 1 && this.note.id === noteId) { this.onDeleteNote(); }
  }

  @Builder
  editorToolbar() {
    Row({ space: this.isPhone ? 4 : 8 }) {
      if (this.showBackButton) { IconButton({ icon: $r('app.media.ic_back'), label: this.companionPane ? '收起分屏文档' : '返回资料库', compact: true, onAction: () => this.handleBackRequest() }) }
      IconButton({ icon: this.isEditing ? $r('app.media.ic_check') : $r('app.media.ic_pen'),
        label: this.isEditing ? '完成编辑' : '编辑笔记', compact: true, selected: this.isEditing,
        onAction: () => { if (this.isEditing) { this.exitEdit(); } else { this.enterEdit(); } } })
      if (this.isEditing) {
        IconButton({ icon: $r('app.media.ic_undo'), label: '撤销', available: this.canUndo, compact: true, onAction: () => this.undoEdit() })
        IconButton({ icon: $r('app.media.ic_redo'), label: '重做', available: this.canRedo, compact: true, onAction: () => this.undoEdit(true) })
        IconButton({ icon: $r('app.media.ic_split'), label: this.previewVisible ? '返回源码编辑' : '实时预览', selected: this.previewVisible,
          compact: true, onAction: () => { this.previewVisible = !this.previewVisible; } })
      } else if (!this.isPhone) {
        IconButton({ icon: $r('app.media.ic_star'), label: this.favorite ? '取消收藏' : '收藏笔记', selected: this.favorite, compact: true, onAction: () => this.onToggleFavorite() })
      }
      Blank()
      if (this.showCompanionAction && !this.isEditing) {
        IconButton({ icon: $r('app.media.ic_split'), label: '分屏阅读', compact: true, onAction: () => this.openCompanion() })
      }
      if (!this.isPhone && !this.companionPane) {
        IconButton({ icon: $r('app.media.ic_split'), label: this.annotationPaneOpen ? '收起随堂稿纸' : '打开随堂稿纸', selected: this.annotationPaneOpen,
          compact: true, onAction: () => this.onToggleAnnotation() })
      }
      if (!this.isEditing) {
        IconButton({ icon: $r('app.media.ic_screenshot'), label: '保存正文截图', available: !this.shareBusy,
          onAction: () => this.openOutput('export_image') })
      }
      IconButton({ icon: $r('app.media.ic_export'), label: '导出笔记文字', available: !this.shareBusy,
        onAction: () => this.openOutput('export_text') })
      if (!this.isEditing) {
        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_more'), tint: this.palette().inkSecondary })
        }.width(44).height(44).padding(0).borderRadius(5).backgroundColor(Color.Transparent).accessibilityText('更多笔记操作')
          .onClick(() => { this.actionMenuOpen = !this.actionMenuOpen; })
          .bindMenu(this.actionMenuOpen, this.readerActionsMenu, { onDisappear: () => { this.actionMenuOpen = false; } })
      }
    }.width('100%').height(56).padding({ left: 8, right: 8 }).backgroundColor(this.palette().surface)
      .border({ width: { bottom: 1 }, color: this.palette().borderSubtle }).onClick(() => {})
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
    Column() {
      this.editorToolbar()
      Column() {
      // ---- 固定头部：工具栏 + 大标题 + 元数据 ----
      Column() {
        if (!this.compactPane && !this.isEditing && this.note.coverUrl && this.note.coverUrl.length > 0) {
          NoteCoverVisual({ source: this.note.coverUrl }).width('100%').height(this.isPhone ? 104 : 140)
            .borderRadius(5).clip(true).margin({ bottom: 16 }).onClick(() => {})
        }

        if (this.isEditing) {
          TextInput({ text: this.title, placeholder: '无标题' })
            .fontSize(this.compactPane ? 22 : TypographyTokens.TITLE_HERO)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
            .placeholderColor(this.palette().inkMuted)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .width('100%')
            .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
            .onChange((value: string) => {
              this.title = value;
              this.scheduleSave();
            })
            .onFocus(() => { this.editorFocused = true; }).onBlur(() => { this.editorFocused = false; })
        } else {
          Text(this.title.length === 0 ? '无标题' : this.title)
            .fontSize(this.compactPane ? 22 : TypographyTokens.TITLE_HERO)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
            .width('100%')
            .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
            .onClick(() => this.enterEdit())
        }

        if (!this.compactPane) { this.metaRow() }
      }
      .width('100%')

      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.compactPane ? 16 : this.isPhone ? 20 : 40, right: this.compactPane ? 16 : this.isPhone ? 20 : 40,
        top: this.compactPane ? 12 : this.isPhone ? 28 : 56, bottom: this.compactPane ? 8 : 20 })
      .onClick(() => {
        // 头部区域点击消费，防止触发根节点退出编辑
      })

      // Source and preview share the same content and history.
      if (this.isEditing) {
        Row({ space: 0 }) {
          if (!this.isPhone || !this.previewVisible) {
            this.sourceEditor()
          }
          if (this.previewVisible) {
            this.documentBody(true)
          }
        }.layoutWeight(1).width('100%').alignItems(VerticalAlign.Top)
        Row({ space: 8 }) {
          Text(`${this.content.length} 字符`).fontSize(12).fontColor(this.palette().inkMuted)
          Blank()
          Text(this.saveState === SAVE_FAILED ? '保存失败，点击重试' : this.saveState === SAVE_SAVING ? '正在保存…' : '已保存到本机')
            .fontSize(12).fontColor(this.saveState === SAVE_FAILED ? this.palette().danger : this.palette().inkMuted)
            .onClick(() => { if (this.saveState === SAVE_FAILED) { this.flushSave(); } })
        }.height(32).padding({ left: 20, right: 20 }).width('100%').onClick(() => {})
        if (!this.isPhone || !this.previewVisible) { this.formatToolbar() }
      } else { this.documentBody(false) }
      }.width('100%').constraintSize({ maxWidth: this.isEditing && this.previewVisible && !this.isPhone ? 1360 : 880 }).layoutWeight(1).alignItems(HorizontalAlign.Start)
        .clip(true).backgroundColor(this.palette().canvas)
        .id(`markdown-paper-${this.note.id}`)
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.isPhone || this.compactPane ? 0 : 24, right: this.isPhone || this.compactPane ? 0 : 24 })
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.palette().canvas)
      .onClick(() => {
        // 点击空白处退出编辑模式（TextArea/按钮等交互元素会消费自身点击，不会冒泡至此）
        if (this.isEditing && !this.editorFocused) {
          this.exitEdit();
        }
      })
      if (this.outputAction) {
        HuaweiDocActionDialog({ note: this.note, documentTitle: this.title, dialogType: this.outputAction, busy: this.shareBusy,
          resultMessage: this.outputMessage, failed: this.outputFailed,
          onClose: () => this.closeOutput(), onConfirm: (extension: string) => this.performOutput(extension) })
      }
    }
    .width('100%')
    .height('100%').enabled(!this.inputLocked)
  }

  private handleEditorKey(event: KeyEvent): boolean {
    if (!event.getModifierKeyState || !event.getModifierKeyState(['Ctrl'])) { return false; }
    const key = event.keyCode;
    const known = key === KeyCode.KEYCODE_Z || key === KeyCode.KEYCODE_Y || key === KeyCode.KEYCODE_B || key === KeyCode.KEYCODE_I || key === KeyCode.KEYCODE_S;
    if (!known) { return false; }
    if (event.type !== KeyType.Down) { return true; }
    if (key === KeyCode.KEYCODE_Z) { this.undoEdit(event.getModifierKeyState(['Shift'])); }
    else if (key === KeyCode.KEYCODE_Y) { this.undoEdit(true); }
    else if (key === KeyCode.KEYCODE_B) { this.handleFormatAction('bold'); }
    else if (key === KeyCode.KEYCODE_I) { this.handleFormatAction('italic'); }
    else { this.flushSave(); }
    return true;
  }

  @Builder
  sourceEditor() {
    TextArea({ text: this.content, placeholder: '开始书写，用 [[双链]] 连接你的思考…', controller: this.textAreaController })
      .fontSize(TypographyTokens.BODY_LARGE).fontFamily('monospace')
      .fontColor(this.palette().inkPrimary).placeholderColor(this.palette().inkMuted)
      .backgroundColor(Color.Transparent).padding({ left: 20, right: 20, top: 8, bottom: 20 })
      .height('100%').layoutWeight(1).accessibilityText('Markdown 源码')
      .onChange((value: string) => this.changeText(value))
      .onTextSelectionChange((start: number, end: number) => { this.selStart = start; this.selEnd = end; })
      .onFocus(() => { this.editorFocused = true; this.isFormatBarVisible = true; })
      .onBlur(() => { this.editorFocused = false; }).onClick(() => {})
      .onKeyPreIme((event: KeyEvent): boolean => this.handleEditorKey(event))
  }

  @Builder
  documentBody(preview: boolean) {
    List({ space: 0, scroller: this.scroller }) {
      ForEach(this.blocks, (block: MarkdownBlock, index: number) => {
        ListItem() {
          Column() { this.blockView(block) }.width('100%').alignItems(HorizontalAlign.Start)
            .padding({ left: this.isPhone ? 20 : 28, right: this.isPhone ? 20 : 28 })
        }
      }, (block: MarkdownBlock, index: number) => `${index}-${block.kind}-${block.line}-${block.text}-${block.checked === true ? 1 : 0}`)
    }.layoutWeight(1).height('100%').scrollBar(BarState.Auto)
      .id(preview ? `markdown-preview-${this.note.id}` : `markdown-body-${this.note.id}`)
      .backgroundColor(this.palette().surface).clip(true).onClick(() => {})
  }
}
