import { NoteItem } from '../../common/types/NoteItem';
import { DocumentCover } from './DocumentCover';

/**
 * 文档封面入口。
 *
 * 首页书架、资料库列表与收藏列表都只使用这一个组件，避免三种格式各自
 * 长出不同的封面结构。真正的排版骨架在 DocumentCover：同一书脊、同一
 * 居中标题、同一底部格式 / 真实页数行。这里只负责把 NoteItem 的真实字段
 * 映射过去，不使用 previewText、contentDetail、strokes 或 sourceUri 冒充封面。
 */
@Component
export struct DocumentPreview {
  @Prop note: NoteItem;
  @Prop compact: boolean = false;

  private pageCount(): number {
    const count: number | undefined = this.note.pageCount;
    return count !== undefined && count > 0 ? count : 0;
  }

  build() {
    DocumentCover({
      type: this.note.sourceType === 'pdf' ? 'PDF' : this.note.sourceType === 'image' ? 'Image' : this.note.type,
      title: this.note.title,
      pageCount: this.pageCount(),
      coverUrl: this.note.coverUrl || '',
      compact: this.compact
    })
      .width('100%')
      .height('100%')
  }
}
