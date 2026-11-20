/**
 * 「在当前项目内新建」的类型选择面板（对齐华为笔记与 Notion 卡片网格风格）。
 *
 * 这是主目录侧边栏「＋」的落点：让用户先选类型，再决定是新建还是从系统导入。
 * DocumentViewPicker 支持 PDF、图片、文本和 Office 文字版，导入后
 * 直接归入当前项目而不是落到「未分类」。
 */
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { SpaceFolder } from '../../../common/types/SpaceFolder';
import { SheetCancelButton, SheetOverlay } from './SheetScaffold';
import { AppIcon } from '../../common/AppIcon';

@Component
export struct NewContentSheet {
  @Prop project: SpaceFolder;

  onClose: () => void = () => {};
  onCreateNoteInProject: (title: string, projectName: string, type: string) => void = () => {};
  onImportIntoProject: (projectName: string) => void = () => {};
  onRequestTemplate: (projectName: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  private projectName(): string {
    return this.project && this.project.name ? this.project.name : '笔记本';
  }

  @Builder
  gridItem(title: string, desc: string, icon: Resource, onAction: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          AppIcon({ source: icon, iconSize: 22, tint: this.palette().accent })
        }
        .width(44).height(44).borderRadius(12)
        .backgroundColor(this.palette().surfaceSubtle)
        .border({ width: 1, color: this.palette().borderSubtle })

        Column({ space: 3 }) {
          Text(title)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary)
          Text(desc)
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 10, right: 10 })
    }
    .width('100%')
    .height(56)
    .borderRadius(10)
    .backgroundColor(Color.Transparent)
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText(title)
    .onClick(() => onAction())
  }

  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 10 }) {
        Row() {
          Text(`添加至「${this.projectName()}」`)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button({ type: ButtonType.Normal }) {
            AppIcon({ source: $r('app.media.ic_close'), iconSize: 16, tint: this.palette().inkMuted })
          }
          .width(32).height(32).padding(0).backgroundColor(Color.Transparent)
          .accessibilityText('关闭添加')
          .onClick(() => this.onClose())
        }.width('100%')

        Column({ space: 4 }) {
          this.gridItem('文字笔记', '支持 Markdown、[[双链]] 与 #标签', $r('app.media.ic_note'),
            () => this.onCreateNoteInProject('未命名笔记', this.projectName(), 'Markdown'))
          this.gridItem('手写笔记', '自由笔迹画布与随堂稿纸', $r('app.media.ic_pen'),
            () => this.onCreateNoteInProject('未命名手写笔记', this.projectName(), 'Handwriting'))
          this.gridItem('从模板新建', '常用课堂、会议与复习模板', $r('app.media.ic_read'),
            () => this.onRequestTemplate(this.projectName()))
        this.gridItem('导入文档', 'PDF、图片、文本及 DOCX / PPTX 文字版', $r('app.media.ic_import'),
            () => this.onImportIntoProject(this.projectName()))
        }.width('100%')

        SheetCancelButton({ onCancel: this.onClose })
      }
      .width('100%')
    }
  }
}
