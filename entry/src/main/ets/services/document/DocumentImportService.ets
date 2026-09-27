/**
 * 文档导入管线服务 (DocumentImportService)
 *
 * 统一处理：
 *   1. 外部文档 Picker 调起 (PDF / Word / Markdown / 图片)
 *   2. 自动分流：PDF 走沙箱深拷贝与元数据提取，Markdown 走文本解析
 *   3. 构造带真实 sourceUri 与 pageCount 的 NoteItem 实体
 */
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { NoteItem } from '../../common/types/NoteItem';
import { PdfDocumentService } from './PdfDocumentService';

export class DocumentImportService {
  private static instance: DocumentImportService | null = null;

  static getInstance(): DocumentImportService {
    if (DocumentImportService.instance === null) {
      DocumentImportService.instance = new DocumentImportService();
    }
    return DocumentImportService.instance;
  }

  /**
   * 调起系统文档选择器并生成 NoteItem
   */
  async pickAndImport(context: common.UIAbilityContext, targetCategory: string = '未分类'): Promise<NoteItem | null> {
    try {
      const docPicker = new picker.DocumentViewPicker(context);
      const uris = await docPicker.select({
        maxSelectNumber: 1
      });

      if (!uris || uris.length === 0) {
        return null;
      }

      const selectedUri = uris[0];
      const decodedName = decodeURIComponent(selectedUri.split('/').pop() ?? '未命名文档');
      const isPdf = decodedName.toLowerCase().endsWith('.pdf');
      const now = Date.now();

      if (isPdf) {
        // PDF 专属管线：持久化拷贝到沙箱 documents 目录
        const pdfService = PdfDocumentService.getInstance();
        const savedPath = await pdfService.savePdfToSandbox(context, selectedUri, decodedName);
        const info = await pdfService.getPdfInfo(savedPath);

        const pdfNote: NoteItem = {
          id: `doc-${now}`,
          title: decodedName,
          category: targetCategory,
          type: 'PDF',
          sourceUri: savedPath,
          sourceType: 'pdf',
          pageCount: info.pageCount,
          previewText: `PDF 试卷文档 · ${info.pageCount} 页 · 沙箱已存储`,
          tag: 'PDF文献',
          tagColor: '#E11D48',
          updateTime: '刚刚',
          contentDetail: `[PDF 原盘文献]: ${decodedName}`,
          tags: ['PDF文献', targetCategory],
          createdAt: now,
          updatedAt: now
        };
        return pdfNote;
      }

      // 普通通用文档导入 (Markdown / TXT / 源码等)
      let fileText: string = '';
      try {
        const srcFile = fs.openSync(selectedUri, fs.OpenMode.READ_ONLY);
        const buf = new ArrayBuffer(64 * 1024);
        const len = fs.readSync(srcFile.fd, buf);
        fs.closeSync(srcFile);
        if (len > 0) {
          const decoder = util.TextDecoder.create('utf-8', { ignoreBOM: true });
          fileText = decoder.decodeToString(new Uint8Array(buf.slice(0, len)));
        }
      } catch (readErr) {
        console.warn(`读取导入文件文本内容跳过: ${readErr}`);
      }

      if (fileText.length === 0) {
        fileText = `# ${decodedName}\n\n已导入的外部参考文档。`;
      }

      const genericNote: NoteItem = {
        id: `doc-${now}`,
        title: decodedName,
        category: targetCategory,
        type: 'Markdown',
        sourceUri: selectedUri,
        sourceType: 'document',
        previewText: fileText.slice(0, 100).replace(/\n/g, ' '),
        tag: '外部资料',
        tagColor: '#2563EB',
        updateTime: '刚刚',
        contentDetail: fileText,
        tags: ['外部资料', targetCategory],
        createdAt: now,
        updatedAt: now
      };
      return genericNote;
    } catch (err) {
      console.warn(`文档选择与导入取消或异常: ${err}`);
      return null;
    }
  }
}
