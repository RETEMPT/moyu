/**
 * 研读正文 (T3.1)
 *
 * Notion 风格排版：28vp 大标题 + 轻量元数据行 + Markdown 块级渲染。
 * 支持「阅读 / 编辑」模式切换；输入变化触发 800ms 防抖，
 * 通过 NoteStorageService.saveDocument 落盘到沙箱应用目录的 .md 文件。
 */
import { common } from '@kit.AbilityKit';
import { curves } from '@kit.ArkUI';
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { MarkdownDocument } from '../../common/types/MarkdownDocument';
import { MarkdownOutlineItem } from '../../common/types/MarkdownOutlineItem';
import { NoteStorageService } from '../../services/NoteStorageService';
import { TimeFormat } from '../../common/utils/TimeFormat';
import { SAVE_FAILED, SAVE_IDLE, SAVE_SAVING } from '../../common/constants/WorkspaceConstants';

/** 输入停止后延迟落盘的毫秒数 */
const AUTOSAVE_DELAY_MS: number = 800;

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
}

/** 待办行解析结果 */
interface TaskParse {
  checked: boolean;
  text: string;
}

@Component
export struct MarkdownReader {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  /** 大纲锚点跳转令牌：每次自增即触发一次定位 */
  @Prop @Watch('onJumpRequest') jumpToken: number = 0;
  /** 待定位的目标行号（0 基），配合 jumpToken 使用 */
  @Prop jumpLine: number = -1;
  /** 标题或正文落盘成功后回调，父组件据此刷新列表快照 */
  onSaved: (note: NoteItem, content: string) => void = () => {};
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
  @State displayUpdateTime: string = '';

  private storage: NoteStorageService = new NoteStorageService();
  private scroller: Scroller = new Scroller();
  private saveTimer: number = -1;
  private loadedNoteId: string = '';
  private isDirty: boolean = false;
  /**
   * 当前正文（this.content）真正归属的笔记。
   * 必须与 @Prop note 解耦：切换笔记时 ArkUI 会先替换 this.note，
   * 若落盘时读取 this.note 会把 A 的正文写进 B 的 .md 文件。
   */
  private editingNote: NoteItem | null = null;

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.loadDocument();
  }

  aboutToDisappear(): void {
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
    if (this.editingNote !== null) {
      this.editingNote.title = this.note.title;
      this.editingNote.category = this.note.category;
    }
    this.title = this.note.title;
  }

  /** 切换笔记：等待上一篇落盘完成后再读取新笔记正文 */
  private async switchNote(): Promise<void> {
    await this.flushSave();
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
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    // 绑定正文归属：复制一份笔记元数据，避免 @Prop note 被切换时连带改写归属
    this.editingNote = this.cloneNote(this.note);
    this.loadedNoteId = this.note.id;
    this.title = this.note.title;
    this.displayUpdateTime = this.note.updateTime;
    this.isDirty = false;
    try {
      const document: MarkdownDocument = await this.storage.read(context, this.note);
      this.applyContent(document.content);
    } catch (error) {
      // 文件不可读时回退到元数据快照中的正文，绝不丢弃用户内容
      console.error(`研读正文读取失败: ${JSON.stringify(error)}`);
      this.applyContent(this.note.contentDetail);
    }
  }

  /** 复制笔记元数据，用于把「正文归属」与可变的 @Prop note 彻底解耦 */
  private cloneNote(source: NoteItem): NoteItem {
    return {
      id: source.id,
      title: source.title,
      category: source.category,
      type: source.type,
      previewText: source.previewText,
      tag: source.tag,
      tagColor: source.tagColor,
      updateTime: source.updateTime,
      contentDetail: source.contentDetail,
      pageInfo: source.pageInfo,
      extraInfo: source.extraInfo,
      coverUrl: source.coverUrl,
      strokes: source.strokes,
      scratchpadStrokes: source.scratchpadStrokes,
      pageAnnotations: source.pageAnnotations
    };
  }

  private applyContent(next: string): void {
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
    // 落盘对象取自正文归属笔记 this.editingNote，绝不使用可能已被切换的 this.note
    const target: NoteItem | null = this.editingNote;
    if (!this.isDirty || target === null || target.id.length === 0) {
      return;
    }
    this.isDirty = false;

    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const snapshot: NoteItem = this.buildSnapshot(target);
    try {
      await this.storage.saveDocument(context, snapshot, this.content);
      this.saveState = SAVE_IDLE;
      this.displayUpdateTime = snapshot.updateTime;
      this.onSaveStateChange(SAVE_IDLE);
      this.onSaved(snapshot, this.content);
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
    return {
      id: note.id,
      title: this.title.trim().length === 0 ? '未命名笔记' : this.title.trim(),
      category: note.category,
      type: note.type,
      previewText: preview,
      tag: note.tag,
      tagColor: note.tagColor,
      updateTime: TimeFormat.now(),
      contentDetail: this.content,
      pageInfo: note.pageInfo,
      extraInfo: note.extraInfo,
      coverUrl: note.coverUrl,
      strokes: note.strokes,
      scratchpadStrokes: note.scratchpadStrokes,
      pageAnnotations: note.pageAnnotations
    };
  }

  // ------------------------------------------------------------------
  // 解析：块级与行内
  // ------------------------------------------------------------------

  private parseBlocks(source: string): MarkdownBlock[] {
    const result: MarkdownBlock[] = [];
    const lines: string[] = source.split('\n');
    let inCode: boolean = false;
    let codeLines: string[] = [];
    let codeStart: number = 0;

    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i];
      const trimmed: string = line.trim();

      if (trimmed.startsWith('```')) {
        if (inCode) {
          result.push({ kind: 'code', level: 0, text: codeLines.join('\n'), line: codeStart });
          codeLines = [];
          inCode = false;
        } else {
          inCode = true;
          codeStart = i;
        }
        continue;
      }
      if (inCode) {
        codeLines.push(line);
        continue;
      }
      if (trimmed.length === 0) {
        result.push({ kind: 'gap', level: 0, text: '', line: i });
        continue;
      }
      if (trimmed === '---' || trimmed === '***') {
        result.push({ kind: 'divider', level: 0, text: '', line: i });
        continue;
      }
      if (trimmed.startsWith('### ')) {
        result.push({ kind: 'heading', level: 3, text: trimmed.substring(4), line: i });
        continue;
      }
      if (trimmed.startsWith('## ')) {
        result.push({ kind: 'heading', level: 2, text: trimmed.substring(3), line: i });
        continue;
      }
      if (trimmed.startsWith('# ')) {
        result.push({ kind: 'heading', level: 1, text: trimmed.substring(2), line: i });
        continue;
      }
      if (trimmed.startsWith('> ')) {
        result.push({ kind: 'quote', level: 0, text: trimmed.substring(2), line: i });
        continue;
      }
      // 待办项必须在 bullet 之前判断：`- [ ]` 也以 `- ` 开头
      const task: TaskParse | null = this.parseTask(trimmed);
      if (task !== null) {
        result.push({ kind: 'task', level: 0, text: task.text, line: i, checked: task.checked });
        continue;
      }
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        result.push({ kind: 'bullet', level: 0, text: trimmed.substring(2), line: i });
        continue;
      }
      const orderedIndex: number = this.orderedMarkerLength(trimmed);
      if (orderedIndex > 0) {
        result.push({ kind: 'ordered', level: 0, text: trimmed.substring(orderedIndex), line: i });
        continue;
      }
      result.push({ kind: 'paragraph', level: 0, text: trimmed, line: i });
    }

    if (inCode && codeLines.length > 0) {
      result.push({ kind: 'code', level: 0, text: codeLines.join('\n'), line: codeStart });
    }
    return result;
  }

  /** 返回 "1. " 这类有序列表标记的长度，非有序列表返回 0 */
  private orderedMarkerLength(line: string): number {
    let index: number = 0;
    while (index < line.length && line.charAt(index) >= '0' && line.charAt(index) <= '9') {
      index++;
    }
    if (index > 0 && index + 1 < line.length && line.charAt(index) === '.' && line.charAt(index + 1) === ' ') {
      return index + 2;
    }
    return 0;
  }

  /**
   * 解析待办项：`- [ ] 文本` / `- [x] 文本`（`*` 亦可，`[X]` 视为已勾选）。
   * 非待办项返回 null。方括号后允许紧跟空格或直接结束。
   */
  private parseTask(trimmed: string): TaskParse | null {
    let rest: string = '';
    if (trimmed.startsWith('- ')) {
      rest = trimmed.substring(2);
    } else if (trimmed.startsWith('* ')) {
      rest = trimmed.substring(2);
    } else {
      return null;
    }
    let checked: boolean = false;
    if (rest.startsWith('[ ]')) {
      checked = false;
    } else if (rest.startsWith('[x]') || rest.startsWith('[X]')) {
      checked = true;
    } else {
      return null;
    }
    // 去掉勾选框标记，再去掉紧随其后的前导空格
    const text: string = rest.substring(3).replace(/^\s+/, '');
    const result: TaskParse = { checked: checked, text: text };
    return result;
  }

  /** 阅读模式下点击待办：翻转对应行的勾选标记，重解析并触发落盘 */
  private toggleTask(block: MarkdownBlock): void {
    if (block.line < 0) {
      return;
    }
    const lines: string[] = this.content.split('\n');
    if (block.line >= lines.length) {
      return;
    }
    const original: string = lines[block.line];
    const flipped: string = this.flipCheckbox(original);
    if (flipped === original) {
      return;
    }
    lines[block.line] = flipped;
    this.content = lines.join('\n');
    this.blocks = this.parseBlocks(this.content);
    this.onOutlineUpdated(this.collectOutline(this.blocks));
    this.scheduleSave();
  }

  /** 翻转一行里首个勾选标记：`[ ]`→`[x]`，`[x]`/`[X]`→`[ ]`；无标记则原样返回 */
  private flipCheckbox(line: string): string {
    if (line.includes('[ ]')) {
      return line.replace('[ ]', '[x]');
    }
    if (line.includes('[x]')) {
      return line.replace('[x]', '[ ]');
    }
    if (line.includes('[X]')) {
      return line.replace('[X]', '[ ]');
    }
    return line;
  }

  /** 把一行拆成普通文本 / [[双链]] / #标签 三类片段 */
  private splitSegments(line: string): TextSegment[] {
    const segments: TextSegment[] = [];
    let buffer: string = '';
    let index: number = 0;

    while (index < line.length) {
      const char: string = line.charAt(index);
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
      if (char === '#') {
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
  // 渲染
  // ------------------------------------------------------------------

  @Builder
  richLine(text: string, fontSize: number, weight: FontWeight, color: string) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.splitSegments(text), (segment: TextSegment) => {
        Text(segment.text)
          .fontSize(fontSize)
          .fontWeight(weight)
          .fontColor(segment.kind === 'link' ? this.palette().link
            : (segment.kind === 'tag' ? this.palette().accent : color))
          .decoration(segment.kind === 'link'
            ? { type: TextDecorationType.Underline, color: this.palette().link, style: TextDecorationStyle.DOTTED }
            : { type: TextDecorationType.None })
          .hoverEffect(segment.kind === 'link' ? HoverEffect.Highlight : HoverEffect.None)
          .onClick(() => {
            if (segment.kind === 'link') {
              const cleaned = segment.text.replace(/^\[\[/, '').replace(/\]\]$/, '');
              const parts = cleaned.split('|');
              const targetTitle = parts[0].trim();
              if (targetTitle.length > 0) {
                this.onOpenNoteByTitle(targetTitle);
              }
            }
          })
      }, (segment: TextSegment, index: number) => `${index}-${segment.text}`)
    }
    .width('100%')
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
        Text(block.checked === true ? '☑' : '☐')
          .fontSize(TypographyTokens.BODY_LARGE)
          .fontColor(block.checked === true ? this.palette().accent : this.palette().inkMuted)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => this.toggleTask(block))
        Column() {
          this.richLine(block.text, TypographyTokens.BODY_LARGE, FontWeight.Normal,
            block.checked === true ? this.palette().inkMuted : this.palette().inkPrimary)
        }
        .layoutWeight(1)
        .onClick(() => this.toggleTask(block))
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
        Text('·')
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
    } else if (block.kind === 'code') {
      Text(block.text)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().inkSecondary)
        .width('100%')
        .padding(10)
        .borderRadius(6)
        .backgroundColor(this.palette().surfaceSubtle)
        .margin({ top: 6, bottom: 6 })
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

  @Builder
  editorToolbar() {
    Row({ space: 8 }) {
      Text(this.isEditing ? '◉ 编辑中' : '◎ 阅读')
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.isEditing ? this.palette().accent : this.palette().inkSecondary)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(6)
        .backgroundColor(this.isEditing ? this.palette().accentSoft : this.palette().surfaceSubtle)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          animateTo({ curve: curves.springMotion(0.25, 0.76) }, () => {
            this.isEditing = !this.isEditing;
          });
          if (!this.isEditing) {
            this.flushSave();
          }
        })

      Blank()

      Text(this.saveState)
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.saveState === SAVE_FAILED ? this.palette().danger : this.palette().inkMuted)
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  build() {
    Column() {
      // ---- 固定头部：工具栏 + 大标题 + 元数据 ----
      Column() {
        this.editorToolbar()

        if (this.isEditing) {
          TextInput({ text: this.title, placeholder: '无标题' })
            .fontSize(TypographyTokens.TITLE_HERO)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
            .placeholderColor(this.palette().inkMuted)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .width('100%')
            .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.25, 0.76) }))
            .onChange((value: string) => {
              this.title = value;
              this.scheduleSave();
            })
        } else {
          Text(this.title.length === 0 ? '无标题' : this.title)
            .fontSize(TypographyTokens.TITLE_HERO)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
            .width('100%')
            .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.25, 0.76) }))
        }

        this.metaRow()
      }
      .width('100%')
      .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH })
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 32, right: 32, top: 20 })

      // ---- 正文区 ----
      if (this.isEditing) {
        Scroll() {
          Column() {
            TextArea({ text: this.content, placeholder: '开始书写，用 [[双链]] 连接你的思考…' })
              .fontSize(TypographyTokens.BODY_LARGE)
              .fontColor(this.palette().inkPrimary)
              .placeholderColor(this.palette().inkMuted)
              .backgroundColor(Color.Transparent)
              .padding(0)
              .width('100%')
              .height(this.editorHeight())
              .onChange((value: string) => {
                this.content = value;
                this.blocks = this.parseBlocks(value);
                this.onOutlineUpdated(this.collectOutline(this.blocks));
                this.scheduleSave();
              })
          }
          .width('100%')
          .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH })
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 32, right: 32, top: 4, bottom: 64 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
        .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.25, 0.76) }))
      } else {
        // 使用 List 承载块级内容，以便大纲点击可平滑锚点定位
        List({ space: 0, scroller: this.scroller }) {
          ForEach(this.blocks, (block: MarkdownBlock, index: number) => {
            ListItem() {
              Column() {
                this.blockView(block)
              }
              .width('100%')
              .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH })
              .alignItems(HorizontalAlign.Start)
              .padding({ left: 32, right: 32 })
            }
          }, (block: MarkdownBlock, index: number) =>
            `${index}-${block.kind}-${block.line}-${block.checked === true ? 1 : 0}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .transition(TransitionEffect.OPACITY.animation({ curve: curves.springMotion(0.25, 0.76) }))
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.palette().canvas)
  }

  private editorHeight(): number {
    const estimated: number = this.content.split('\n').length * 26 + 40;
    return estimated < 320 ? 320 : estimated;
  }
}
