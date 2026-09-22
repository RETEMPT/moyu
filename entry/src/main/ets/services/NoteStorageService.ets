import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { fileIo, picker } from '@kit.CoreFileKit';
import { NoteItem } from '../common/types/NoteItem';
import { SpaceFolder } from '../common/types/SpaceFolder';
import { DocumentTransferResult, MarkdownDocument } from '../common/types/MarkdownDocument';

const PREFERENCES_NAME: string = 'flowmind_notes';
const NOTES_KEY: string = 'notes';
const PROJECTS_KEY: string = 'projects';
const TRASH_KEY: string = 'trash';
const NOTES_DIRECTORY_NAME: string = 'notes';

export class NoteStorageService {
  private notePreferences: preferences.Preferences | null = null;
  private notesDirectory: string = '';
  /** 最近一次初始化时传入的应用上下文，用于补建 Preferences 实例 */
  private storageContext: Context | null = null;

  /**
   * 读取本地笔记快照，并用沙箱中的 .md 正文回填 contentDetail。
   * @param context 应用上下文
   * @param fallbackNotes 快照缺失或损坏时使用的兜底笔记
   * @returns 已回填正文的笔记列表
   */
  async load(context: Context, fallbackNotes: NoteItem[]): Promise<NoteItem[]> {
    const prefs: preferences.Preferences = await this.ensureInitialized(context);
    const storedNotes = await prefs.get(NOTES_KEY, '');
    if (typeof storedNotes !== 'string' || storedNotes.length === 0) {
      // 首次启动：写入快照并把示例正文物化为真实 .md 文件
      await this.saveSnapshot(fallbackNotes);
      await this.reconcileFiles(fallbackNotes);
      return fallbackNotes;
    }

    let parsedNotes: NoteItem[];
    try {
      parsedNotes = JSON.parse(storedNotes) as NoteItem[];
    } catch (error) {
      console.error(`本地笔记快照解析失败: ${JSON.stringify(error)}`);
      await this.saveSnapshot(fallbackNotes);
      return fallbackNotes;
    }
    if (!this.isNoteItemArray(parsedNotes)) {
      console.error('本地笔记快照格式无效，正在恢复示例数据');
      await this.saveSnapshot(fallbackNotes);
      return fallbackNotes;
    }

    const hydratedNotes: NoteItem[] = [];
    for (const note of parsedNotes) {
      const content: string | null = await this.tryRead(note.id);
      if (content === null) {
        await this.migrateLegacyContent(note);
        hydratedNotes.push(note);
      } else {
        note.contentDetail = content;
        hydratedNotes.push(note);
      }
    }
    return hydratedNotes;
  }

  /**
   * 保存笔记元数据快照。
   * 仅写入 Preferences JSON，不重写任何 .md 文件——自动保存热路径专用，
   * 正文文件由 saveDocument / create 单独落盘。
   * @param notes 待写入的笔记列表
   */
  async save(notes: NoteItem[]): Promise<void> {
    await this.saveSnapshot(notes);
  }

  /**
   * 全库对齐：把内存中的笔记正文整批重新写入沙箱 .md 文件。
   * 仅在恢复备份、批量迁移等显式全量场景调用，禁止用于逐次自动保存。
   * @param notes 需要重新物化的笔记列表
   */
  async reconcileFiles(notes: NoteItem[]): Promise<void> {
    if (this.notesDirectory.length === 0) {
      throw new Error('本地笔记存储尚未初始化');
    }
    for (let index = 0; index < notes.length; index++) {
      await this.writeMarkdown(notes[index].id, notes[index].contentDetail);
    }
  }

  /**
   * 创建一篇 Markdown 文档并写入应用沙箱。
   */
  async create(context: Context, note: NoteItem): Promise<MarkdownDocument> {
    await this.ensureInitialized(context);
    await this.writeMarkdown(note.id, note.contentDetail);
    return this.documentFor(context, note, note.contentDetail);
  }

  /**
   * 读取指定笔记的 Markdown 正文。
   */
  async read(context: Context, note: NoteItem): Promise<MarkdownDocument> {
    await this.ensureInitialized(context);
    const content: string = await fileIo.readText(this.filePath(note.id));
    return this.documentFor(context, note, content);
  }

  /**
   * 删除指定笔记的 Markdown 文件。文件不存在时静默返回，不抛异常。
   */
  async delete(context: Context, noteId: string): Promise<void> {
    await this.ensureInitialized(context);
    const filePath: string = this.filePath(noteId);
    try {
      const exists: boolean = await fileIo.access(filePath);
      if (exists) {
        await fileIo.unlink(filePath);
      }
    } catch (error) {
      console.error(`笔记文件删除失败 (${noteId}): ${JSON.stringify(error)}`);
    }
  }

  /**
   * 保存指定笔记的 Markdown 正文。文件写入失败会直接抛出异常。
   */
  async saveDocument(context: Context, note: NoteItem, content: string): Promise<MarkdownDocument> {
    await this.ensureInitialized(context);
    await this.writeMarkdown(note.id, content);
    return this.documentFor(context, note, content);
  }

  /**
   * 使用系统文件选择器导入 Markdown/TXT。PDF/Word 只报告不支持解析，不伪造正文。
   */
  async importDocument(context: Context): Promise<DocumentTransferResult> {
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.md', '.markdown', '.txt', '.pdf', '.doc', '.docx'];
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return { status: 'cancelled', message: '未选择文件' };
      }
      const uri: string = uris[0];
      const fileName: string = this.fileNameFromUri(uri);
      const id: string = `import_${Date.now()}`;

      if (this.isTextDocument(fileName)) {
        const content: string = await fileIo.readText(uri);
        const note: NoteItem = this.noteFromImportedFile(id, fileName, content);
        await this.ensureInitialized(context);
        await this.writeMarkdown(note.id, content);
        return {
          status: 'imported',
          document: this.documentFor(context, note, content),
          fileName,
          noteType: 'Markdown',
          message: `已导入 ${fileName}`
        };
      }

      if (/\.pdf$/i.test(fileName)) {
        const title: string = fileName.replace(/\.pdf$/i, '');
        const content: string = `# ${title}\n\n` +
          `> 来源文件：${fileName} (PDF 文献)\n\n` +
          `## 文献摘要与考点\n\n` +
          `- 本文档已导入至应用沙箱，点击顶栏「◫ 边读边写」可开启右侧白纸草稿板进行随堂公式推演。\n` +
          `- 涉及核心概念可直接在文中使用 \`[[双向链接]]\` 沉淀至知识图谱。\n\n` +
          `#考研 #文献研读`;
        const note: NoteItem = {
          id,
          title,
          category: '参考资料',
          type: 'PDF',
          previewText: `[PDF文献] ${title}，支持边读边写双开草稿批注`,
          tag: 'PDF文献',
          tagColor: '#E11D48',
          updateTime: '刚刚',
          contentDetail: content,
          pageInfo: '文献文档'
        };
        await this.ensureInitialized(context);
        await this.writeMarkdown(note.id, content);
        return {
          status: 'imported',
          document: this.documentFor(context, note, content),
          fileName,
          noteType: 'PDF',
          message: `已导入 PDF 文献「${fileName}」`
        };
      }

      if (/\.(docx|doc)$/i.test(fileName)) {
        const title: string = fileName.replace(/\.(docx|doc)$/i, '');
        let extractedContent: string = '';
        try {
          const raw = await fileIo.readText(uri);
          const matches = raw.match(/<w:t[^>]*>([\s\S]*?)<\/w:t>/g);
          if (matches && matches.length > 0) {
            extractedContent = matches.map((m: string) => m.replace(/<w:t[^>]*>/, '').replace(/<\/w:t>/, '')).join(' ');
          }
        } catch (e) {
          // 二进制容错
        }
        const content: string = `# ${title}\n\n` +
          `> 来源文件：${fileName} (试卷/文档)\n\n` +
          (extractedContent.length > 0 ? `## 试卷题目内容\n\n${extractedContent}\n\n` : '') +
          `## 解题与批注区\n\n` +
          `- 点击顶栏「◫ 边读边写」按钮展开右侧白纸草稿板，使用炭黑/蓝笔演练推导，红笔订正，荧光笔圈出题干关键条件。\n` +
          `- 关联知识点考点：[[线性代数 · 特征值与特征向量]]、[[操作系统 · 死锁与银行家算法]]\n\n` +
          `#试卷 #真题演练`;
        const note: NoteItem = {
          id,
          title,
          category: '试卷题库',
          type: 'Doc',
          previewText: `[试卷文档] ${title}，支持边读边写做题批注与双链`,
          tag: '试卷题目',
          tagColor: '#2563EB',
          updateTime: '刚刚',
          contentDetail: content
        };
        await this.ensureInitialized(context);
        await this.writeMarkdown(note.id, content);
        return {
          status: 'imported',
          document: this.documentFor(context, note, content),
          fileName,
          noteType: 'Doc',
          message: `已导入试卷文档「${fileName}」`
        };
      }

      return {
        status: 'unsupported',
        fileName,
        message: `${fileName} 格式不受支持`
      };
    } catch (error) {
      console.error(`文件导入失败: ${JSON.stringify(error)}`);
      return { status: 'failed', message: '文件导入失败，请检查文件权限或重试' };
    }
  }

  /**
   * 将 Markdown/TXT 导出到用户选择的位置。调用方可将结果直接显示给用户。
   */
  async exportDocument(context: Context, note: NoteItem, extension: string = '.md'): Promise<DocumentTransferResult> {
    try {
      const documentPicker = new picker.DocumentViewPicker(context);
      const options = new picker.DocumentSaveOptions();
      const normalizedExtension: string = extension.toLowerCase() === '.txt' ? '.txt' : '.md';
      options.newFileNames = [this.safeFileName(note.title) + normalizedExtension];
      options.fileSuffixChoices = ['Markdown|.md', 'Text|.txt'];
      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        return { status: 'cancelled', message: '未选择导出位置' };
      }
      const uri: string = uris[0];
      const file = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        await fileIo.write(file.fd, note.contentDetail);
      } finally {
        await fileIo.close(file);
      }
      return { status: 'exported', fileName: this.fileNameFromUri(uri), message: `已导出 ${note.title}` };
    } catch (error) {
      console.error(`文件导出失败: ${JSON.stringify(error)}`);
      return { status: 'failed', message: '文件导出失败，请检查文件权限或重试' };
    }
  }

  /**
   * 读取应用沙箱中已保存的 Markdown 文件列表，不依赖 Preferences 快照。
   * 标题取自正文首个一级标题，缺失时回退为文件名；更新时间取自文件系统 mtime。
   * @param context 应用上下文
   * @returns 沙箱内全部文本型文档（读取失败时返回空数组）
   */
  async listDocuments(context: Context): Promise<MarkdownDocument[]> {
    await this.ensureInitialized(context);
    try {
      const names: string[] = await fileIo.listFile(this.notesDirectory);
      const documents: MarkdownDocument[] = [];
      for (let index = 0; index < names.length; index++) {
        const name: string = names[index];
        if (!this.isTextDocument(name)) {
          continue;
        }
        const filePath: string = `${this.notesDirectory}/${name}`;
        const content: string = await fileIo.readText(filePath);
        const id: string = name.replace(/\.(md|markdown|txt)$/i, '');
        const title: string = this.titleFromContent(content, id);
        const updatedAt: number = await this.modifiedTime(filePath);
        documents.push({ id, title, fileName: name, filePath, content, updatedAt });
      }
      return documents;
    } catch (error) {
      console.error(`Markdown 文件列表读取失败: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /** 从正文首个一级标题提取真实标题，缺失时回退为文件名派生的兜底标题 */
  private titleFromContent(content: string, fallback: string): string {
    const lines: string[] = content.split('\n');
    for (let index = 0; index < lines.length; index++) {
      const trimmed: string = lines[index].trim();
      if (trimmed.startsWith('# ')) {
        const text: string = trimmed.substring(2).trim();
        if (text.length > 0) {
          return text;
        }
      }
    }
    return fallback;
  }

  /** 读取文件最后修改时间（毫秒时间戳），失败时回退为 0 而非捏造当前时间 */
  private async modifiedTime(filePath: string): Promise<number> {
    try {
      const stat = await fileIo.stat(filePath);
      return stat.mtime * 1000;
    } catch (error) {
      console.error(`Markdown 文件时间读取失败 (${filePath}): ${JSON.stringify(error)}`);
      return 0;
    }
  }

  private async saveSnapshot(notes: NoteItem[]): Promise<void> {
    let prefs: preferences.Preferences | null = this.notePreferences;
    if (prefs === null) {
      const context: Context | null = this.storageContext;
      if (context === null) {
        throw new Error('本地笔记存储尚未初始化');
      }
      prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      this.notePreferences = prefs;
    }
    await prefs.put(NOTES_KEY, JSON.stringify(notes));
    await prefs.flush();
  }

  /**
   * 读取已保存的项目列表。从未保存过时返回 null，由调用方回退到默认项目。
   * @param context 应用上下文
   * @returns 项目列表；无历史数据时为 null
   */
  async loadProjects(context: Context): Promise<SpaceFolder[] | null> {
    const prefs: preferences.Preferences = await this.ensureInitialized(context);
    // 与 load() 里的 NOTES_KEY 读法一致：不显式标注类型，交给推断得到 ValueType
    const stored = await prefs.get(PROJECTS_KEY, '');
    if (typeof stored !== 'string' || stored.length === 0) {
      return null;
    }
    try {
      const parsed: SpaceFolder[] = JSON.parse(stored) as SpaceFolder[];
      if (!Array.isArray(parsed)) {
        console.error('项目快照格式无效，回退为默认项目');
        return null;
      }
      return parsed;
    } catch (error) {
      console.error(`项目快照解析失败: ${JSON.stringify(error)}`);
      return null;
    }
  }

  /**
   * 保存项目列表。
   *
   * 只落盘项目的展示元数据，**不保存 `notes` 字段** —— 项目下辖的笔记由
   * `buildSpaces()` 从笔记列表实时派生，存进来等于把所有笔记正文再复制一份，
   * 既撑大 Preferences 又会让两份数据有机会对不上。
   * @param context 应用上下文
   * @param projects 待保存的项目列表
   */
  async saveProjects(context: Context, projects: SpaceFolder[]): Promise<void> {
    const prefs: preferences.Preferences = await this.ensureInitialized(context);
    const slim: SpaceFolder[] = [];
    for (let i = 0; i < projects.length; i++) {
      const p: SpaceFolder = projects[i];
      slim.push({
        id: p.id,
        name: p.name,
        count: p.count,
        isOpen: p.isOpen,
        children: p.children,
        color: p.color,
        icon: p.icon,
        description: p.description
      });
    }
    await prefs.put(PROJECTS_KEY, JSON.stringify(slim));
    await prefs.flush();
  }

  /**
   * 读取回收站中的笔记（软删除快照）。从未保存过或数据损坏时返回空数组。
   * 回收站与资料库分开存储：正文 .md 文件在软删除阶段保留，只有彻底删除才移除。
   * @param context 应用上下文
   * @returns 回收站笔记列表
   */
  async loadTrash(context: Context): Promise<NoteItem[]> {
    const prefs: preferences.Preferences = await this.ensureInitialized(context);
    const stored = await prefs.get(TRASH_KEY, '');
    if (typeof stored !== 'string' || stored.length === 0) {
      return [];
    }
    try {
      const parsed: NoteItem[] = JSON.parse(stored) as NoteItem[];
      return this.isNoteItemArray(parsed) ? parsed : [];
    } catch (error) {
      console.error(`回收站快照解析失败: ${JSON.stringify(error)}`);
      return [];
    }
  }

  /**
   * 保存回收站快照。仅写入 Preferences JSON，不动任何 .md 文件。
   * @param context 应用上下文
   * @param trash 回收站笔记列表
   */
  async saveTrash(context: Context, trash: NoteItem[]): Promise<void> {
    const prefs: preferences.Preferences = await this.ensureInitialized(context);
    await prefs.put(TRASH_KEY, JSON.stringify(trash));
    await prefs.flush();
  }

  /**
   * 确保沙箱笔记目录与 Preferences 实例均已就绪。
   * 首次调用创建 Preferences，重复调用直接复用，避免初始化失败后永久不可用。
   * @param context 应用上下文
   * @returns 已就绪的 Preferences 实例
   */
  private async ensureInitialized(context: Context): Promise<preferences.Preferences> {
    this.notesDirectory = `${context.filesDir}/${NOTES_DIRECTORY_NAME}`;
    this.storageContext = context;
    let prefs: preferences.Preferences | null = this.notePreferences;
    if (prefs === null) {
      prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      this.notePreferences = prefs;
    }
    return prefs;
  }

  private async writeMarkdown(id: string, content: string): Promise<void> {
    if (this.notesDirectory.length === 0) {
      throw new Error('本地笔记存储尚未初始化');
    }
    await this.ensureNotesDirectory();
    const file = await fileIo.open(
      this.filePath(id),
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    try {
      await fileIo.write(file.fd, content);
    } finally {
      await fileIo.close(file);
    }
  }

  /**
   * 确保沙箱笔记目录存在。
   *
   * 注意 fileIo.access() 的签名是 `Promise<boolean>`：路径不存在时它**返回 false**，
   * 而不是抛异常。早期版本写成 `try { access } catch { mkdir }`，catch 永远进不去，
   * 目录因此从未被创建，后续 fileIo.open(CREATE) 一直以 13900002 失败 ——
   * 表现就是「没有任何 .md 文件落盘，正文只存在于 Preferences 快照里」。
   * 这里必须判断返回值，并对并发建目录的竞态做兜底。
   */
  private async ensureNotesDirectory(): Promise<void> {
    if (await this.directoryExists()) {
      return;
    }
    try {
      // recursion=true 等价于 mkdir -p，父目录缺失时一并创建
      await fileIo.mkdir(this.notesDirectory, true);
    } catch (error) {
      // 可能是并发调用已被建好；再确认一次，确实不存在才如实抛出
      if (!await this.directoryExists()) {
        throw new Error(`创建笔记目录失败 (${this.notesDirectory}): ${JSON.stringify(error)}`);
      }
    }
  }

  private async directoryExists(): Promise<boolean> {
    try {
      return await fileIo.access(this.notesDirectory);
    } catch (error) {
      // 个别实现下依然可能以 13900002 抛错，统一按「不存在」处理
      return false;
    }
  }

  private async migrateLegacyContent(note: NoteItem): Promise<void> {
    try {
      await this.writeMarkdown(note.id, note.contentDetail);
    } catch (error) {
      console.error(`旧笔记正文迁移失败 (${note.id}): ${JSON.stringify(error)}`);
    }
  }

  private async tryRead(id: string): Promise<string | null> {
    try {
      return await fileIo.readText(this.filePath(id));
    } catch (error) {
      console.error(`Markdown 正文读取失败 (${id}): ${JSON.stringify(error)}`);
      return null;
    }
  }

  private filePath(id: string): string {
    return `${this.notesDirectory}/${this.safeFileName(id)}.md`;
  }

  private isTextDocument(fileName: string): boolean {
    return /\.(md|markdown|txt)$/i.test(fileName);
  }

  private fileNameFromUri(uri: string): string {
    const cleanUri: string = uri.split('?')[0];
    const parts: string[] = cleanUri.split('/');
    return decodeURIComponent(parts[parts.length - 1] || 'document');
  }

  private noteFromImportedFile(id: string, fileName: string, content: string): NoteItem {
    const title: string = fileName.replace(/\.(md|markdown|txt)$/i, '');
    return {
      id,
      title,
      category: '导入资料',
      type: 'markdown',
      previewText: content.slice(0, 120).replace(/\n/g, ' '),
      tag: '🟢 Markdown',
      tagColor: '#5AB87A',
      updateTime: '刚刚',
      contentDetail: content
    };
  }

  private safeFileName(id: string): string {
    return id.replace(/[^a-zA-Z0-9_-]/g, '_');
  }

  private documentFor(context: Context, note: NoteItem, content: string): MarkdownDocument {
    const fileName: string = `${this.safeFileName(note.id)}.md`;
    return {
      id: note.id,
      title: note.title,
      fileName,
      filePath: `${context.filesDir}/${NOTES_DIRECTORY_NAME}/${fileName}`,
      content,
      updatedAt: Date.now()
    };
  }

  private isNoteItemArray(value: NoteItem[]): boolean {
    if (!Array.isArray(value)) {
      return false;
    }
    for (const note of value) {
      if (note === null
        || typeof note.id !== 'string'
        || typeof note.title !== 'string'
        || typeof note.contentDetail !== 'string') {
        return false;
      }
    }
    return true;
  }
}
