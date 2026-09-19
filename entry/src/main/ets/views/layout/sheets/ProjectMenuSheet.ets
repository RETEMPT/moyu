/**
 * 项目长按操作面板。
 *
 * 由 Sidebar 在 activeSheet === 'project_menu' 时挂载。
 * 面板本身不持有项目数据，只接收当前项目与一组回调，
 * 所有状态改动都回到 Index（见 pages/Index.ets 的 createNoteInProject 等）。
 */
import { TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { ColorPalette } from '../../../common/constants/DesignTokens';
import { SpaceFolder } from '../../../common/types/SpaceFolder';
import { DestructiveConfirm, SheetActionRow, SheetCancelButton, SheetOverlay } from './SheetScaffold';

@Component
export struct ProjectMenuSheet {
  @Prop project: SpaceFolder;

  onClose: () => void = () => {};
  /** 在项目内新建指定类型的资料（'Markdown' | 'Canvas' | 'Doc'） */
  onCreateNoteInProject: (title: string, projectName: string, type: string) => void = () => {};
  /** 请求切换到重命名表单（由 Sidebar 决定挂载哪个 sheet） */
  onRequestRename: (project: SpaceFolder) => void = () => {};
  onDeleteProject: (name: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 6 }) {
        Row({ space: 6 }) {
          Text(this.project.icon || '📁')
            .fontSize(TypographyTokens.BODY_REGULAR)
          Text(this.project.name)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.project.count} 项`)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
        .padding({ bottom: 4 })
        .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })

        SheetActionRow({
          label: '📝 新建 Markdown 笔记',
          onAction: () => this.onCreateNoteInProject('未命名笔记', this.project.name, 'Markdown')
        })
        SheetActionRow({
          label: '⬡ 新建白板导图',
          onAction: () => this.onCreateNoteInProject('未命名导图', this.project.name, 'Canvas')
        })
        SheetActionRow({
          label: '🗎 新建参考资料',
          onAction: () => this.onCreateNoteInProject('未命名参考资料', this.project.name, 'Doc')
        })
        SheetActionRow({
          label: '✏️ 重命名项目',
          onAction: () => this.onRequestRename(this.project)
        })

        DestructiveConfirm({
          triggerLabel: '🗑️ 删除项目',
          question: `确定删除「${this.project.name}」？`,
          consequence: '下辖资料将自动归入「未分类」，不会丢失。',
          onConfirm: () => this.onDeleteProject(this.project.name)
        })

        SheetCancelButton({ onCancel: this.onClose })
      }
      .width('100%')
    }
  }
}
