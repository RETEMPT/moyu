/**
 * 「在当前项目内新建」的类型选择面板。
 *
 * 这是主目录侧边栏「＋」的落点：让用户先选类型，再决定是新建还是从系统导入。
 * 导入走 DocumentViewPicker，支持 PDF / Word / Markdown / 纯文本，导入后
 * 直接归入当前项目而不是落到「未分类」。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { SpaceFolder } from '../../../common/types/SpaceFolder';
import { SheetActionRow, SheetCancelButton, SheetOverlay } from './SheetScaffold';

@Component
export struct NewContentSheet {
  @Prop project: SpaceFolder;

  onClose: () => void = () => {};
  onCreateNoteInProject: (title: string, projectName: string, type: string) => void = () => {};
  onImportIntoProject: (projectName: string) => void = () => {};
  onRequestTemplate: (projectName: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 8 }) {
        Text(`新建到「${this.project.name}」`)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        SheetActionRow({
          label: '📝 新建笔记',
          onAction: () => this.onCreateNoteInProject('未命名笔记', this.project.name, 'Markdown')
        })
        SheetActionRow({
          label: '📄 从模板新建',
          onAction: () => this.onRequestTemplate(this.project.name)
        })
        SheetActionRow({
          label: '⬡ 新建白板',
          onAction: () => this.onCreateNoteInProject('未命名导图', this.project.name, 'Canvas')
        })
        SheetActionRow({
          label: '📥 导入 PDF / 文档',
          onAction: () => this.onImportIntoProject(this.project.name)
        })

        SheetCancelButton({ onCancel: this.onClose })
      }
      .width('100%')
    }
  }
}
