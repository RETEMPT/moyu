import { Context } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { NoteCoverService } from './NoteCoverService';
import { preferences } from '@kit.ArkData';
import { fileIo, picker } from '@kit.CoreFileKit';
import { NoteItem } from '../common/types/NoteItem';
import { SpaceFolder } from '../common/types/SpaceFolder';
import { DocumentTransferResult, MarkdownDocument } from '../common/types/MarkdownDocument';
import { PdfDocumentService } from './document/PdfDocumentService';
import { SnapshotStore } from './storage/SnapshotStore';
import { AtomicTextFile } from './storage/AtomicTextFile';
import { NoteIdentity } from './storage/NoteIdentity';
import { RdbSnapshotRepository, SnapshotWrite } from './storage/RdbSnapshotRepository';
import { TrashedProject } from '../common/types/TrashedProject';
import BuildProfile from 'BuildProfile';
import { ImageDocumentPolicy } from './document/ImageDocumentPolicy';
import { ImageDocumentService } from './document/ImageDocumentService';
import { DocumentSourceKind, DocumentSourceLocation, DocumentSourcePolicy } from './document/DocumentSourcePolicy';

const PREFERENCES_NAME: string = 'flowmind_notes';
const NOTES_KEY: string = 'notes';
const PROJECTS_KEY: string = 'projects';
const TRASH_KEY: string = 'trash';
const TRASH_PROJECTS_KEY: string = 'trash_projects';
const NOTES_DIRECTORY_NAME: string = 'notes';
const NOTE_READ_CONCURRENCY: number = 4;
const DEBUG_PDF_ID: string = 'debug-pdf-demo-v1';
const DEBUG_PDF_INSTALLED_KEY: string = 'debug_pdf_demo_v1';
const PENDING_DELETIONS_KEY: string = 'pending_deletions_v1';
interface PendingDeletion { id: string; sourceUri: string; coverUrl: string; }

export class NoteStorageService {
  private notePreferences: preferences.Preferences | null = null;
  private notesDirectory: string = '';
  /** 最近一次初始化时传入的应用上下文，用于补建 Preferences 实例 */
  private storageContext: Context | null = null;
  private snapshots: SnapshotStore = new SnapshotStore();
  private textFiles: AtomicTextFile = new AtomicTextFile();
  private repository: RdbSnapshotRepository | null = null;
  private relationalFailed: boolean = false;

  /** Explicit application composition keeps platform-free adapters and migrations independently testable. */
  async enableRelational(context: Context): Promise<void> {
    const repository = new RdbSnapshotRepository();
    try { await repository.open(context); }
    catch {
      this.relationalFailed = true;
      this.snapshots.block(NOTES_KEY); this.snapshots.block(TRASH_KEY); this.snapshots.block(PROJECTS_KEY);
      throw new Error('本地关系数据库初始化失败，旧资料已保留，已阻止空值覆盖');
    }
    this.repository = repository;
  }

  private async readCollection<T>(prefs: preferences.Preferences, key: string, valid: (value: T) => boolean): Promise<T | null> {
    const repository = this.repository;
    if (repository === null) { return this.snapshots.read<T>(prefs, key, valid); }
    try {
      const json = await repository.read(key);
      if (json !== null) {
        const value = JSON.parse(json) as T;
        if (!valid(value)) { throw new Error('资料格式异常'); }
        return value;
      }
      // Migrate only a validated legacy snapshot. No old snapshot or file is deleted.
      const legacy = await this.snapshots.read<T>(prefs, key, valid);
      if (legacy !== null) { await repository.write(key, JSON.stringify(legacy)); }
      return legacy;
    } catch {
      repository.block(key); this.snapshots.block(key);
      throw new Error('本地资料库读取或迁移失败，旧资料和原库已保留');
    }
  }

  private async writeCollection(prefs: preferences.Preferences, key: string, json: string): Promise<void> {
    if (this.relationalFailed) { throw new Error('本地资料库初始化失败，已阻止覆盖'); }
    if (this.repository === null) { await this.snapshots.write(prefs, key, json); return; }
    await this.repository.write(key, json);
    // Current readers use the committed database. Keep a best-effort legacy recovery copy.
    try { await this.snapshots.write(prefs, key, json); }
    catch { console.warn('关系数据库已提交，旧版恢复快照未能更新'); }
  }

  /**
   * 读取本地笔记快照，并用沙箱中的 .md 正文回填 contentDetail。
   * @param context 应用上下文
   * @param fallbackNotes 首次启动为空；损坏快照保留并报错
   * @returns 已回填正文的笔记列表
   */
  async load(context: Context, fallbackNotes: NoteItem[]): Promise<NoteItem[]> {
    try { return await this.loadNotes(context, fallbackNotes); }
    catch (error) { this.snapshots.block(NOTES_KEY); this.repository?.block(NOTES_KEY); throw new Error(error instanceof Error ? error.message : '本地笔记读取失败'); }
  }

  private async loadNotes(context: Context, fallbackNotes: NoteItem[]): Promise<NoteItem[]> {
    const prefs: preferences.Preferences = await this.ensureInitialized(context);
    const parsedNotes = await this.readCollection<NoteItem[]>(prefs, NOTES_KEY, (value: NoteItem[]) => this.isNoteItemArray(value));
    if (parsedNotes === null) {
      // 发布版首次启动为空；调试示例由独立启动步骤加入。
      await this.reconcileFiles(fallbackNotes);
      await this.saveSnapshot(fallbackNotes);
      return fallbackNotes;
    }

    const contents: (string | null)[] = await this.readNoteContents(parsedNotes);
    const hydratedNotes: NoteItem[] = [];
    for (let index = 0; index < parsedNotes.length; index++) {
      const note: NoteItem = parsedNotes[index];
      const content: string | null = contents[index];
      if (content === null) {
        await this.migrateLegacyContent(note);
      } else {
        note.contentDetail = content;
      }
      hydratedNotes.push(note);
    }
    await this.restorePdfSources(context, hydratedNotes, NOTES_KEY);
    return hydratedNotes;
  }

  /**
   * Read independent Markdown files with a fixed worker cap and restore them by note index.
   * A read failure is reported for the whole load; it is never converted into an empty body.
   */
  private async readNoteContents(notes: NoteItem[]): Promise<(string | null)[]> {
    const contents: (string | null)[] = [];
    for (let index = 0; index < notes.length; index++) { contents.push(null); }
    let next: number = 0;
    const worker = async (): Promise<void> => {
      while (next < notes.length) {
        const index: number = next++;
        const note: NoteItem = notes[index];
        try {
          contents[index] = await this.tryRead(note.id);
        } catch (error) {
          const detail: string = error instanceof Error ? `：${error.message}` : '';
          throw new Error(`笔记正文读取失败，原文件已保留，请检查存储后重试${detail}`);
        }
      }
    };
    const workers: Promise<void>[] = [];
    for (let index = 0; index < Math.min(NOTE_READ_CONCURRENCY, notes.length); index++) { workers.push(worker()); }
    await Promise.all(workers);
    return contents;
  }

  /**
   * 保存笔记元数据快照。
   * 仅提交元数据快照，不重写任何 .md 文件——自动保存热路径专用，
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
   * 删除笔记正文和应用内 PDF 副本。不存在时跳过，失败向调用方报告。
   */
  async delete(context: Context, noteId: string, sourceUri: string = '', coverUrl: string = '', protectedNotes: NoteItem[] = []): Promise<void> {
    await this.ensureInitialized(context);
    const prefix: string = `${context.filesDir}/documents/`;
    const name: string = sourceUri.startsWith(prefix) ? sourceUri.substring(prefix.length) : '';
    // 只清理 documents 的直接子文件，外部选择器 URI 或异常路径不得删除。
    if (name.length > 0 && name !== '.' && name !== '..' &&
      !name.includes('/') && !name.includes('\\')) {
      if (!protectedNotes.some((note: NoteItem) => note.sourceUri === sourceUri || note.coverUrl === sourceUri) &&
        await fileIo.access(sourceUri)) { await fileIo.unlink(sourceUri); }
    }
    const filePath: string = this.filePath(noteId);
    if (!protectedNotes.some((note: NoteItem) => this.filePath(note.id) === filePath) &&
      await fileIo.access(filePath)) { await fileIo.unlink(filePath); }
    if (!protectedNotes.some((note: NoteItem) => note.coverUrl === coverUrl || note.sourceUri === coverUrl)) {
      await NoteCoverService.removeManaged(context, coverUrl);
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
   * 导入正文、真实 PDF 与图片原件；Word 格式明确提示转换。
   */
  async importDocument(context: Context): Promise<DocumentTransferResult> {
    try {
      const uris: string[] = await this.selectDocumentUris(context, 1);
      if (uris.length === 0) {
        return { status: 'cancelled', message: '未选择文件' };
      }
      return await this.importDocumentUri(context, uris[0]);
    } catch (error) {
      return { status: 'failed', message: error instanceof Error ? error.message : '文件选择失败，请重试' };
    }
  }

  async selectDocumentUris(context: Context, limit: number = 20): Promise<string[]> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = Math.max(1, Math.min(20, limit));
    options.fileSuffixFilters = ['支持的资料|.pdf,.md,.markdown,.txt,.png,.jpg,.jpeg,.webp,.bmp,.gif',
      'PDF|.pdf', '文字|.md,.markdown,.txt', '图片|.png,.jpg,.jpeg,.webp,.bmp,.gif'];
    return new picker.DocumentViewPicker(context).select(options);
  }

  /** All document entry points materialize a local source before publishing an import. */
  async importDocumentUri(context: Context, uri: string): Promise<DocumentTransferResult> {
    try {
      const fileName: string = this.fileNameFromUri(uri);
      const id: string = `import_${Date.now()}_${Math.floor(Math.random() * 1000000)}`;

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
          message: `已保存到本机资料库：${fileName}`
        };
      }

      if (/\.pdf$/i.test(fileName)) {
        const savedPath = await PdfDocumentService.getInstance().savePdfToSandbox(context, uri, fileName);
        return await this.importPdfCopy(context, savedPath, fileName, id);
      }
      if (ImageDocumentPolicy.extension(fileName)) {
        const imported = await ImageDocumentService.importFile(context, uri, fileName);
        const content = `# ${fileName}\n\n图片资料 · 原件保留，批注独立保存\n\n${imported.info.format} · ${imported.info.width} × ${imported.info.height}`;
        const note = this.noteFromImportedFile(id, fileName, content);
        try { await this.ensureInitialized(context); await this.writeMarkdown(id, content); }
        catch { try { await fileIo.unlink(imported.path); } catch {} throw new Error('图片资料保存失败，请检查存储空间后重试'); }
        return { status: 'imported', document: this.documentFor(context, note, content), fileName, noteType: 'Image',
          sourceUri: imported.path, sourceFileName: imported.path.split('/').pop(), pageCount: 1,
          documentMeta: JSON.stringify(imported.info), message: `图片资料已导入：${fileName}` };
      }
      if (/\.(docx|doc)$/i.test(fileName)) {
        return { status: 'unsupported', fileName: fileName,
          message: '暂不支持 Word 正文解析，请转换为 PDF、Markdown 或 TXT 后导入。' };
      }

      return {
        status: 'unsupported',
        fileName,
        message: `${fileName} 格式不受支持`
      };
    } catch (error) {
      console.error(`文件导入失败: ${JSON.stringify(error)}`);
      return { status: 'failed', message: error instanceof Error ? error.message : '文件导入失败，请检查文件权限或重试' };
    }
  }

  /** Debug builds add one real PDF once, including on upgrade; deletion is respected. */
  async ensureDebugPdf(context: Context, notes: NoteItem[]): Promise<NoteItem[]> {
    if (!BuildProfile.DEBUG) { return notes; }
    const prefs = await this.ensureInitialized(context);
    if (await prefs.get(DEBUG_PDF_INSTALLED_KEY, false) === true) { return notes; }
    const trash = await this.readCollection<NoteItem[]>(prefs, TRASH_KEY, (value: NoteItem[]) => this.isNoteItemArray(value)) || [];
    if (notes.concat(trash).some((note: NoteItem) => note.id === DEBUG_PDF_ID)) {
      await prefs.put(DEBUG_PDF_INSTALLED_KEY, true); await prefs.flush();
      return notes;
    }
    const path = await PdfDocumentService.getInstance().saveBundledExample(context);
    const result = await this.importPdfCopy(context, path, '墨语阅读测试.pdf', DEBUG_PDF_ID);
    if (result.status !== 'imported' || result.document === undefined) { throw new Error(result.message); }
    const note: NoteItem = {
      id: DEBUG_PDF_ID, title: '墨语阅读测试.pdf', category: '示例资料', type: 'PDF',
      sourceType: 'pdf', sourceUri: result.sourceUri, sourceFileName: result.sourceFileName,
      pageCount: result.pageCount, pageInfo: `${result.pageCount} 页`, previewText: '两页真实 PDF，打开即可测试阅读、翻页与批注。',
      tag: '阅读示例', tagColor: '#7C3AED', updateTime: '刚刚', contentDetail: result.document.content,
      createdAt: Date.now(), updatedAt: Date.now()
    };
    const next = [note].concat(notes);
    try { await this.saveSnapshot(next); }
    catch (error) {
      try { await this.delete(context, note.id, path); } catch { /* Only the new example is uncommitted. */ }
      throw new Error(error instanceof Error ? error.message : '阅读示例保存失败');
    }
    // A failed marker write must not roll back the already committed note. The stable ID prevents duplication.
    try { await prefs.put(DEBUG_PDF_INSTALLED_KEY, true); await prefs.flush(); }
    catch { console.warn('阅读示例标记保存失败，下次启动按资料 ID 检查'); }
    return next;
  }

  /** Manual imports of real bundled PDFs are available in debug builds. */
  async importExamplePdf(context: Context, snapshot: boolean = false): Promise<DocumentTransferResult> {
    if (!BuildProfile.DEBUG) { return { status: 'unsupported', message: '阅读测试资料仅在调试版中提供' }; }
    try {
      const path = await PdfDocumentService.getInstance().saveBundledExample(context, snapshot);
      return await this.importPdfCopy(context, path, snapshot ? '墨语快照测试.pdf' : '墨语阅读测试.pdf', `example_${Date.now()}_${Math.floor(Math.random() * 1000000)}`);
    } catch (error) {
      return { status: 'failed', message: error instanceof Error ? error.message : '测试 PDF 导入失败' };
    }
  }

  private async importPdfCopy(context: Context, savedPath: string, fileName: string, id: string): Promise<DocumentTransferResult> {
    let count: number = 0;
    try {
      count = (await PdfDocumentService.getInstance().validateImport(savedPath)).pageCount;
    } catch (error) {
      try { await fileIo.unlink(savedPath); } catch { /* 不残留失败导入文件 */ }
      return { status: 'failed', message: error instanceof Error ? error.message : 'PDF 读取失败' };
    }
    const note: NoteItem = {
      id: id, title: fileName.replace(/\.pdf$/i, ''), category: '未分类', type: 'PDF',
      previewText: 'PDF · ' + count + ' 页', tag: 'PDF', tagColor: '#E11D48', updateTime: '刚刚',
      contentDetail: '# ' + fileName + '\n\n来源：导入的 PDF，共 ' + count + ' 页。',
      sourceUri: savedPath, sourceFileName: savedPath.split('/').pop(), sourceType: 'pdf', pageCount: count
    };
    try {
      await this.ensureInitialized(context);
      await this.writeMarkdown(note.id, note.contentDetail);
    } catch (error) {
      try { await PdfDocumentService.getInstance().removeManagedPdf(context, savedPath); } catch { /* 无引用的导入副本清理 */ }
      throw new Error('PDF 笔记保存失败，请检查存储空间或重试');
    }
    return { status: 'imported', document: this.documentFor(context, note, note.contentDetail),
      fileName: fileName, noteType: 'PDF', sourceUri: savedPath, sourceFileName: note.sourceFileName, pageCount: count,
      message: '已保存到本机资料库：' + fileName };
  }

  /** Reattach a user-selected original without creating another note or changing saved annotations. */
  async selectReplacementPdf(context: Context, note: NoteItem): Promise<NoteItem | null> {
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1; options.fileSuffixFilters = ['.pdf'];
    const uris = await new picker.DocumentViewPicker(context).select(options);
    if (!uris.length) { return null; }
    const service = PdfDocumentService.getInstance();
    const path = await service.savePdfToSandbox(context, uris[0], this.fileNameFromUri(uris[0]));
    try {
      const info = await service.validateImport(path);
      const hasAnnotations = typeof note.pageAnnotations === 'string' && note.pageAnnotations.length > 0;
      if (hasAnnotations && note.pageCount && info.pageCount !== note.pageCount) {
        throw new Error(`所选 PDF 为 ${info.pageCount} 页，与现有 ${note.pageCount} 页批注不一致。请选择原文件；其他资料请单独导入。`);
      }
      const updated = JSON.parse(JSON.stringify(note)) as NoteItem;
      updated.sourceUri = path; updated.sourceFileName = path.split('/').pop(); updated.sourceType = 'pdf'; updated.type = 'PDF';
      updated.pageCount = info.pageCount; updated.pageInfo = `${info.pageCount} 页`;
      updated.documentMeta = JSON.stringify(info); updated.updatedAt = Date.now();
      // Page count alone cannot prove this is the same content. Rebuild reviewed page text from the selected original.
      updated.pdfTextJson = undefined;
      return updated;
    } catch (error) {
      try { await service.removeManagedPdf(context, path); } catch { /* No existing source is deleted. */ }
      throw new Error(error instanceof Error ? error.message : '原 PDF 未能关联');
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
        const expected = new util.TextEncoder().encodeInto(note.contentDetail).length;
        if (await fileIo.write(file.fd, note.contentDetail) !== expected) { throw new Error('导出文件未完整写入'); }
        await fileIo.fsync(file.fd);
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
    NoteIdentity.requireNotes(notes);
    const json = JSON.stringify(notes);
    let prefs: preferences.Preferences | null = this.notePreferences;
    if (prefs === null) {
      const context: Context | null = this.storageContext;
      if (context === null) {
        throw new Error('本地笔记存储尚未初始化');
      }
      prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
      this.notePreferences = prefs;
    }
    await this.writeCollection(prefs, NOTES_KEY, json);
  }

  /**
   * 读取已保存的项目列表。从未保存过时返回 null，由调用方回退到默认项目。
   * @param context 应用上下文
   * @returns 项目列表；无历史数据时为 null
   */
  async loadProjects(context: Context): Promise<SpaceFolder[] | null> {
    try { return await this.readProjects(context); }
    catch (error) { this.snapshots.block(PROJECTS_KEY); this.repository?.block(PROJECTS_KEY); throw new Error(error instanceof Error ? error.message : '项目读取失败'); }
  }

  private async readProjects(context: Context): Promise<SpaceFolder[] | null> {
    const prefs: preferences.Preferences = await this.ensureInitialized(context);
    // 与 load() 里的 NOTES_KEY 读法一致：不显式标注类型，交给推断得到 ValueType
    return this.readCollection<SpaceFolder[]>(prefs, PROJECTS_KEY, (rows: SpaceFolder[]) => Array.isArray(rows) &&
      rows.every((row: SpaceFolder) => row !== null && typeof row.id === 'string' && typeof row.name === 'string'));
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
    await this.writeCollection(prefs, PROJECTS_KEY, JSON.stringify(slim));
  }

  /**
   * 读取回收站中的笔记（软删除快照）。从未保存过时返回空数组，损坏时保留并报错。
   * 回收站与资料库分开存储：正文 .md 文件在软删除阶段保留，只有彻底删除才移除。
   * @param context 应用上下文
   * @returns 回收站笔记列表
   */
  async loadTrash(context: Context): Promise<NoteItem[]> {
    try { return await this.readTrash(context); }
    catch (error) { this.snapshots.block(TRASH_KEY); this.repository?.block(TRASH_KEY); throw new Error(error instanceof Error ? error.message : '回收站读取失败'); }
  }

  private async readTrash(context: Context): Promise<NoteItem[]> {
    const prefs: preferences.Preferences = await this.ensureInitialized(context);
    const notes = await this.readCollection<NoteItem[]>(prefs, TRASH_KEY, (value: NoteItem[]) => this.isNoteItemArray(value)) || [];
    await this.restorePdfSources(context, notes, TRASH_KEY);
    return notes;
  }

  /**
   * Recover owned originals after a sandbox change and migrate readable legacy references.
   *
   * A stored filename is only a hint for an exact path inside the current managed directory;
   * it is never treated as proof that the file exists. Existing local copies are accepted
   * after a stat check only (no PDF parse/render during startup). Legacy URIs are copied and
   * validated once before replacing a reference. A failed repair keeps the original sourceUri
   * and annotations untouched.
   *
   * Every update is staged in cloned notes and committed to the repository before the in-memory
   * notes are changed, so a failed save cannot publish only part of the repaired references.
   * Copies created during a failed run are removed.
   */
  private async restorePdfSources(context: Context, notes: NoteItem[], key: string): Promise<void> {
    const staged: NoteItem[] = notes.slice();
    const created: string[] = [];
    let changed: boolean = false;
    try {
      for (let index = 0; index < notes.length; index++) {
        const note: NoteItem = notes[index];
        const kind: DocumentSourceKind | null = DocumentSourcePolicy.kind({
          sourceType: note.sourceType, type: note.type
        });
        if (kind === null) { continue; }
        const restored: DocumentSourceLocation | null = await this.resolveSource(context, note, kind, created);
        if (restored === null) { continue; }
        if (note.sourceUri === restored.path && note.sourceFileName === restored.fileName &&
          note.sourceType === restored.kind) { continue; }
        const draft: NoteItem = JSON.parse(JSON.stringify(note)) as NoteItem;
        draft.sourceUri = restored.path;
        draft.sourceFileName = restored.fileName;
        draft.sourceType = restored.kind;
        staged[index] = draft;
        changed = true;
      }
      if (!changed) { return; }
      const prefs: preferences.Preferences = await this.ensureInitialized(context);
      await this.writeCollection(prefs, key, JSON.stringify(staged));
    } catch (error) {
      await this.removeCreatedCopies(created, notes);
      throw new Error(error instanceof Error ? error.message : '本机 PDF 引用保存失败，请重试');
    }
    // The committed repository now references these paths; only then expose them to the caller's notes.
    for (let index = 0; index < notes.length; index++) {
      if (staged[index] === notes[index]) { continue; }
      notes[index].sourceUri = staged[index].sourceUri;
      notes[index].sourceFileName = staged[index].sourceFileName;
      notes[index].sourceType = staged[index].sourceType;
    }
  }

  /** Existing local copy first; only a readable legacy source is migrated afterwards. */
  private async resolveSource(context: Context, note: NoteItem, kind: DocumentSourceKind,
    created: string[]): Promise<DocumentSourceLocation | null> {
    const candidates: DocumentSourceLocation[] =
      DocumentSourcePolicy.localCandidates(context.filesDir, {
        sourceUri: note.sourceUri, sourceFileName: note.sourceFileName
      }, kind);
    for (const candidate of candidates) {
      if (await this.isReadableSource(candidate.path)) { return candidate; }
    }
    return this.migrateLegacySource(context, note, kind, created);
  }

  /** Open once to verify bytes are present; never invoke the PDF parser or decode an image. */
  private async isReadableSource(path: string): Promise<boolean> {
    let file: fileIo.File | null = null;
    try {
      file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      return fileIo.statSync(file.fd).size > 0;
    } catch {
      return false;
    } finally {
      if (file !== null) { try { await fileIo.close(file); } catch { /* Read-only probe. */ } }
    }
  }

  /** Copy a readable old URI once; validation happens before the new path may replace the old one. */
  private async migrateLegacySource(context: Context, note: NoteItem, kind: DocumentSourceKind,
    created: string[]): Promise<DocumentSourceLocation | null> {
    const source: string = DocumentSourcePolicy.sourceValue(note.sourceUri);
    if (source.length === 0) { return null; }
    // A path already inside our documents directory was checked above; it is missing, not migratable.
    if (DocumentSourcePolicy.isManagedPath(context.filesDir, source)) { return null; }
    if (!await this.isReadableSource(source)) { return null; }
    let local: string = '';
    try {
      if (kind === 'image') {
        local = (await ImageDocumentService.importFile(context, source, this.fileNameFromUri(source))).path;
      } else {
        const service = PdfDocumentService.getInstance();
        local = await service.savePdfToSandbox(context, source, this.fileNameFromUri(source));
        try {
          await service.validateImport(local);
        } catch (error) {
          // A missing PDF reader component is a reader problem, not proof that the original is wrong.
          // Keep a byte-complete PDF copy for later reading instead of dropping the association.
          const message: string = error instanceof Error ? error.message : '';
          const readerUnavailable: boolean = message.includes('PDF 阅读组件') || message.includes('离线阅读组件');
          if (!readerUnavailable || !await this.hasPdfHeader(local)) {
            throw new Error(message.length > 0 ? message : 'PDF 迁移校验失败');
          }
        }
      }
    } catch {
      await this.removeFile(local);
      return null;
    }
    const fileName: string = local.split('/').pop() || '';
    if (!DocumentSourcePolicy.isSafeFileName(fileName) || !DocumentSourcePolicy.matchesKind(fileName, kind)) {
      await this.removeFile(local);
      return null;
    }
    created.push(local);
    return { path: local, fileName: fileName, kind: kind };
  }

  /** A minimal header check lets a copied legacy PDF survive a temporarily unavailable reader. */
  private async hasPdfHeader(path: string): Promise<boolean> {
    let file: fileIo.File | null = null;
    try {
      file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      const header: ArrayBuffer = new ArrayBuffer(5);
      if (await fileIo.read(file.fd, header) < 5) { return false; }
      const bytes: Uint8Array = new Uint8Array(header);
      return bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 &&
        bytes[3] === 0x46 && bytes[4] === 0x2D;
    } catch {
      return false;
    } finally {
      if (file !== null) { try { await fileIo.close(file); } catch { /* Read-only probe. */ } }
    }
  }

  /** Only copies created by this run are removed, and never a path already referenced by a note. */
  private async removeCreatedCopies(paths: string[], notes: NoteItem[]): Promise<void> {
    for (const path of paths) {
      if (notes.some((note: NoteItem) => note.sourceUri === path)) { continue; }
      await this.removeFile(path);
    }
  }

  private async removeFile(path: string): Promise<void> {
    if (path.length === 0) { return; }
    try {
      if (await fileIo.access(path)) { await fileIo.unlink(path); }
    } catch { /* Keep the original reference; a transient cleanup failure is not data loss. */ }
  }

  /**
   * 保存回收站元数据快照，不动任何 .md 文件。
   * @param context 应用上下文
   * @param trash 回收站笔记列表
   */
  async saveTrash(context: Context, trash: NoteItem[]): Promise<void> {
    NoteIdentity.requireNotes(trash);
    const json = JSON.stringify(trash);
    const prefs: preferences.Preferences = await this.ensureInitialized(context);
    await this.writeCollection(prefs, TRASH_KEY, json);
  }

  async loadTrashedProjects(context: Context): Promise<TrashedProject[]> {
    const prefs = await this.ensureInitialized(context);
    return await this.readCollection<TrashedProject[]>(prefs, TRASH_PROJECTS_KEY, (rows: TrashedProject[]) =>
      Array.isArray(rows) && rows.every((row: TrashedProject) => row !== null && typeof row.id === 'string' &&
        row.project !== null && row.project !== undefined && typeof row.project.id === 'string' && typeof row.project.name === 'string' &&
        Array.isArray(row.noteIds) && row.noteIds.every((id: string) => typeof id === 'string') && Number.isFinite(row.deletedAt))) || [];
  }

  async saveWorkspace(context: Context, notes: NoteItem[], projects: SpaceFolder[], trash: NoteItem[],
    trashedProjects: TrashedProject[], purgeCandidates: NoteItem[] = []): Promise<void> {
    NoteIdentity.requireNotes(notes.concat(trash));
    const slim = projects.map((project: SpaceFolder): SpaceFolder => ({ id: project.id, name: project.name,
      count: 0, isOpen: false, children: [], color: project.color, icon: project.icon, description: project.description }));
    const writes: SnapshotWrite[] = [{ scope: NOTES_KEY, json: JSON.stringify(notes) },
      { scope: PROJECTS_KEY, json: JSON.stringify(slim) }, { scope: TRASH_KEY, json: JSON.stringify(trash) },
      { scope: TRASH_PROJECTS_KEY, json: JSON.stringify(trashedProjects) }];
    const removals: PendingDeletion[] = purgeCandidates.map((note: NoteItem): PendingDeletion => {
      NoteIdentity.fileName(note.id);
      return { id: note.id, sourceUri: note.sourceUri || '', coverUrl: note.coverUrl || '' };
    });
    const prefs = await this.ensureInitialized(context);
    const repository = this.repository;
    if (repository === null || this.relationalFailed) { throw new Error('本地事务资料库未就绪，已阻止修改'); }
    if (removals.length > 0) {
      const pending = await this.readPendingDeletions(prefs);
      writes.push({ scope: PENDING_DELETIONS_KEY, json: JSON.stringify(pending.concat(removals)) });
    }
    await repository.writeMany(writes);
  }

  private async readPendingDeletions(prefs: preferences.Preferences): Promise<PendingDeletion[]> {
    return await this.readCollection<PendingDeletion[]>(prefs, PENDING_DELETIONS_KEY, (rows: PendingDeletion[]) => {
      if (!Array.isArray(rows)) { return false; }
      return rows.every((row: PendingDeletion): boolean => {
        if (!row || typeof row.sourceUri !== 'string' || typeof row.coverUrl !== 'string') { return false; }
        try { NoteIdentity.fileName(row.id); return true; } catch { return false; }
      });
    }) || [];
  }

  /** Caller holds the workspace mutation queue. Jobs are durable before any file is removed. */
  async cleanupPendingDeletions(context: Context, protectedNotes: NoteItem[]): Promise<number> {
    const prefs = await this.ensureInitialized(context);
    const pending = await this.readPendingDeletions(prefs);
    if (!pending.length) { return 0; }
    const failed: PendingDeletion[] = [];
    for (const job of pending) {
      try { await this.delete(context, job.id, job.sourceUri, job.coverUrl, protectedNotes); }
      catch { failed.push(job); }
    }
    // A failed acknowledgement leaves the old jobs intact. Replaying deletes is idempotent.
    await this.writeCollection(prefs, PENDING_DELETIONS_KEY, JSON.stringify(failed));
    return failed.length;
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
    await this.textFiles.write(this.filePath(id), content);
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
    const path = this.filePath(id);
    if (!await fileIo.access(path)) { return null; }
    return fileIo.readText(path);
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
    const title: string = fileName.replace(/\.(md|markdown|txt|json)$/i, '');
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
    return NoteIdentity.fileName(id);
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
    return NoteIdentity.validNotes(value);
  }
}
