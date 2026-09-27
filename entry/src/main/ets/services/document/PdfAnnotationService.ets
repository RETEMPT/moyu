/**
 * PDF 批注数据服务 (PdfAnnotationService)
 *
 * 负责：
 *   1. 序列化与反序列化归一化矢量笔迹 (u, v 坐标系统)
 *   2. 页面批注历史栈与 Undo / Redo 控制
 *   3. 清空单页或全部批注
 *   4. 导出批注摘要与墨迹统计
 */
import {
  DocumentAnnotationData,
  PageAnnotationStroke
} from '../../common/types/PdfAnnotationTypes';

export class PdfAnnotationService {
  /**
   * 解析保存的 JSON 批注数据
   */
  static parseAnnotations(rawJson?: string): Record<number, PageAnnotationStroke[]> {
    if (!rawJson || rawJson.trim().length === 0) {
      return {};
    }
    try {
      const data = JSON.parse(rawJson) as DocumentAnnotationData;
      return data.pages ?? {};
    } catch (e) {
      console.warn(`批注数据反序列化异常: ${e}`);
      return {};
    }
  }

  /**
   * 将页面批注数据集打包序列化为持久化 JSON
   */
  static serializeAnnotations(pages: Record<number, PageAnnotationStroke[]>): string {
    const data: DocumentAnnotationData = {
      version: 1,
      updatedAt: Date.now(),
      pages: pages
    };
    return JSON.stringify(data);
  }

  /**
   * 统计整篇文档的总笔画数
   */
  static totalStrokesCount(pages: Record<number, PageAnnotationStroke[]>): number {
    let count = 0;
    const keys = Object.keys(pages);
    for (const k of keys) {
      const p = pages[Number(k)];
      if (Array.isArray(p)) {
        count += p.length;
      }
    }
    return count;
  }
}
