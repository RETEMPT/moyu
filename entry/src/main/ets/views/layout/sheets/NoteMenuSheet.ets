/**
 * 资料（文件）长按操作菜单。
 *
 * 删除是本地即刻生效、且会连带清掉沙箱 .md 的破坏性动作，
 * 因此这里做二次确认；真正的「后悔药」由 Index 的 Toast 撤销按钮提供
 * （见 pages/Index.ets 的 notifyUndoable）。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import { DestructiveConfirm, SheetActionRow, SheetCancelButton, SheetOverlay } from './SheetScaffold';
import { ResourceTypeTokens } from '../../../common/constants/DesignTokens';

@Component
export struct NoteMenuSheet {
  @Prop note: NoteItem;

  onClose: () => void = () => {};
  onOpenNote: (note: NoteItem) => void = () => {};
  onDeleteNote: (noteId: string) => void = () => {};
  onRequestRename: (note: NoteItem) => void = () => {};
  onRequestMove: (note: NoteItem) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private typeIcon(): string {
    const t: string = this.note.type.toLowerCase();
    if (t === 'canvas' || t === '白板') {
      return '⬡';
    }
    if (t === 'doc' || t === '资料') {
      return '🗎';
    }
    if (t === 'task' || t === '待办') {
      return '☑';
    }
    return '▤';
  }

  private typeColor(): string {
    const t: string = this.note.type.toLowerCase();
    if (t === 'canvas' || t === '白板') {
      return ResourceTypeTokens.COLOR_CANVAS;
    }
    if (t === 'doc' || t === '资料') {
      return ResourceTypeTokens.COLOR_DOC;
    }
    if (t === 'task' || t === '待办') {
      return ResourceTypeTokens.COLOR_TASK;
    }
    return ResourceTypeTokens.COLOR_MARKDOWN;
  }

  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text(this.typeIcon())
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.typeColor())
          Text(this.note.title)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .padding({ bottom: 4 })
        .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })

        SheetActionRow({
          label: '📖 打开研读',
          onAction: () => this.onOpenNote(this.note)
        })

        SheetActionRow({
          label: '✏️ 重命名',
          onAction: () => this.onRequestRename(this.note)
        })

        SheetActionRow({
          label: '⇄ 移动到项目',
          onAction: () => this.onRequestMove(this.note)
        })

        DestructiveConfirm({
          triggerLabel: '🗑️ 删除资料',
          question: `确定删除「${this.note.title}」？`,
          consequence: '将移入回收站，可随时恢复；也可在提示条上点「撤销」立即找回。',
          onConfirm: () => this.onDeleteNote(this.note.id)
        })

        SheetCancelButton({ onCancel: this.onClose })
      }
      .width('100%')
    }
  }
}
