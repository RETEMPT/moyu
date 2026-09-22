/**
 * 添加 / 编辑待办弹窗
 *
 * 输入标题并勾选要引用的笔记（形成跳转链接）。沿用自绘居中浮层写法，
 * 模拟器上比系统弹窗更稳；数据与副作用由上层处理，本组件只收集输入并回调。
 */
import { ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { CalendarUtil } from '../../common/utils/CalendarUtil';

@Component
export struct TodoEditDialog {
  /** 归属日期键 YYYY-MM-DD */
  @Prop dateKey: string = '';
  /** 可引用的笔记列表 */
  @Prop notes: NoteItem[] = [];
  /** 编辑已有待办时的初始标题；新增时为空 */
  @Prop initialTitle: string = '';
  /** 编辑已有待办时的初始引用；新增时为空 */
  @Prop initialRefs: string[] = [];

  onClose: () => void = () => {};
  onSave: (title: string, noteRefs: string[]) => void = () => {};

  @State titleInput: string = '';
  @State selected: string[] = [];

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.titleInput = this.initialTitle;
    this.selected = this.initialRefs.slice();
  }

  private isSelected(noteId: string): boolean {
    for (let i = 0; i < this.selected.length; i++) {
      if (this.selected[i] === noteId) {
        return true;
      }
    }
    return false;
  }

  private toggleRef(noteId: string): void {
    const next: string[] = [];
    let removed: boolean = false;
    for (let i = 0; i < this.selected.length; i++) {
      if (this.selected[i] === noteId) {
        removed = true;
        continue;
      }
      next.push(this.selected[i]);
    }
    if (!removed) {
      next.push(noteId);
    }
    this.selected = next;
  }

  private commit(): void {
    const trimmed: string = this.titleInput.trim();
    if (trimmed.length === 0) {
      return;
    }
    this.onSave(trimmed, this.selected.slice());
  }

  @Builder
  noteRow(note: NoteItem) {
    Row({ space: 8 }) {
      Text(this.isSelected(note.id) ? '☑' : '☐')
        .fontSize(TypographyTokens.BODY_LARGE)
        .fontColor(this.isSelected(note.id) ? this.palette().accent : this.palette().inkMuted)
      Column({ space: 2 }) {
        Text(note.title.length === 0 ? '未命名笔记' : note.title)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(note.category.length === 0 ? '未分类' : note.category)
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    .borderRadius(6)
    .backgroundColor(this.isSelected(note.id) ? this.palette().activeBg : Color.Transparent)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.toggleRef(note.id))
  }

  build() {
    Column() {
      Column() {
        Text('添加待办')
          .fontSize(TypographyTokens.TITLE_SUB)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
          .width('100%')
        Text(this.dateKey.length === 0 ? '' : CalendarUtil.formatKeyCn(this.dateKey))
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
          .width('100%')
          .margin({ top: 2, bottom: 12 })

        TextInput({ text: this.titleInput, placeholder: '待办标题' })
          .fontSize(TypographyTokens.BODY_LARGE)
          .fontColor(this.palette().inkPrimary)
          .placeholderColor(this.palette().inkMuted)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(6)
          .height(40)
          .width('100%')
          .onChange((value: string) => {
            this.titleInput = value;
          })

        Text('引用笔记（可选，点击可跳转）')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkSecondary)
          .width('100%')
          .margin({ top: 14, bottom: 6 })

        if (this.notes.length === 0) {
          Text('还没有可引用的笔记')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
            .width('100%')
            .padding({ top: 8, bottom: 8 })
        } else {
          List({ space: 2 }) {
            ForEach(this.notes, (note: NoteItem) => {
              ListItem() {
                this.noteRow(note)
              }
            }, (note: NoteItem) => note.id)
          }
          .width('100%')
          .constraintSize({ maxHeight: 220 })
          .scrollBar(BarState.Auto)
        }

        Row({ space: 10 }) {
          Blank()
          Text('取消')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .padding({ left: 18, right: 18, top: 8, bottom: 8 })
            .borderRadius(6)
            .backgroundColor(this.palette().surfaceSubtle)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onClose())
          Text('保存')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(Color.White)
            .padding({ left: 18, right: 18, top: 8, bottom: 8 })
            .borderRadius(6)
            .backgroundColor(this.palette().accent)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.commit())
        }
        .width('100%')
        .margin({ top: 18 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 480 })
      .padding({ left: 22, right: 22, top: 20, bottom: 18 })
      .borderRadius(12)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 32, color: 'rgba(0,0,0,0.22)' })
      .border({ width: 1, color: this.palette().border })
      .onClick(() => {
        // 消费卡片内点击，避免冒泡到遮罩导致弹窗关闭
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('rgba(0,0,0,0.28)')
    .onClick(() => this.onClose())
  }
}
