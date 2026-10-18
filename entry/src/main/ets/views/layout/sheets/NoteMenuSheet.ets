/**
 * 资料操作菜单，供资料库按钮及侧栏共用。
 * 删除需确认，先移入回收站，可恢复或从提示条撤销。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import { DestructiveConfirm, SheetActionRow, SheetCancelButton, SheetOverlay } from './SheetScaffold';
import { AppIcon } from '../../common/AppIcon';
import { documentIcon } from '../../../common/utils/DocumentPresentation';

@Component
export struct NoteMenuSheet {
  @Prop note: NoteItem;

  onClose: () => void = () => {};
  onOpenNote: (note: NoteItem) => void = () => {};
  onDeleteNote: (noteId: string) => void = () => {};
  onRequestRename: (note: NoteItem) => void = () => {};
  onRequestMove: (note: NoteItem) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          AppIcon({ source: documentIcon(this.note.type), tint: this.palette().accent })
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
          label: '打开阅读', icon: $r('app.media.ic_read'),
          onAction: () => this.onOpenNote(this.note)
        })

        SheetActionRow({
          label: '重命名资料', icon: $r('app.media.ic_format'),
          onAction: () => this.onRequestRename(this.note)
        })

        SheetActionRow({
          label: '移动到项目', icon: $r('app.media.ic_folder'),
          onAction: () => this.onRequestMove(this.note)
        })

        DestructiveConfirm({
          triggerLabel: '移入回收站',
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
