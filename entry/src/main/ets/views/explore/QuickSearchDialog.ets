/**
 * 全局快速搜索弹窗 (T5.1)
 *
 * Notion 风格居中浮层：对全库标题、正文与 #标签做实时匹配检索。
 * 检索走 NoteSearchService，正文来源是沙箱中的 .md 文件，不依赖任何网络。
 */
import { common } from '@kit.AbilityKit';
import { ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { NoteSearchResult } from '../../common/types/NoteSearchResult';
import { NoteSearchService } from '../../services/NoteSearchService';

/** 输入停止后再发起检索，避免逐字符读盘 */
const SEARCH_DEBOUNCE_MS: number = 260;

@Component
export struct QuickSearchDialog {
  @Prop notes: NoteItem[] = [];

  onClose: () => void = () => {};
  onSelectNote: (note: NoteItem) => void = () => {};

  @State keyword: string = '';
  @State results: NoteSearchResult[] = [];
  @State searching: boolean = false;

  private searchService: NoteSearchService = new NoteSearchService();
  private searchTimer: number = -1;

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToDisappear(): void {
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
  }

  private onKeywordChanged(value: string): void {
    this.keyword = value;
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
    }
    if (value.trim().length === 0) {
      this.results = [];
      this.searching = false;
      return;
    }
    this.searching = true;
    this.searchTimer = setTimeout(() => {
      this.runSearch(value);
    }, SEARCH_DEBOUNCE_MS);
  }

  private async runSearch(keyword: string): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      const found: NoteSearchResult[] = await this.searchService.search(context, this.notes, keyword);
      // 输入可能已经变化，丢弃过期结果
      if (this.keyword === keyword) {
        this.results = found;
      }
    } catch (error) {
      console.error(`全文检索失败: ${JSON.stringify(error)}`);
      if (this.keyword === keyword) {
        this.results = [];
      }
    } finally {
      if (this.keyword === keyword) {
        this.searching = false;
      }
    }
  }

  private resolveNote(noteId: string): NoteItem | undefined {
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].id === noteId) {
        return this.notes[i];
      }
    }
    return undefined;
  }

  build() {
    Column() {
      Column() {
        // ---- 搜索输入 ----
        Row({ space: 8 }) {
          Text('⌕')
            .fontSize(TypographyTokens.TITLE_SUB)
            .fontColor(this.palette().inkMuted)
          TextInput({ text: this.keyword, placeholder: '搜索全部笔记的标题、正文与标签' })
            .fontSize(TypographyTokens.BODY_LARGE)
            .fontColor(this.palette().inkPrimary)
            .placeholderColor(this.palette().inkMuted)
            .backgroundColor(Color.Transparent)
            .padding(0)
            .layoutWeight(1)
            .onChange((value: string) => this.onKeywordChanged(value))
          Text(this.searching ? '检索中' : 'Esc 关闭')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .onClick(() => this.onClose())
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })

        Divider()
          .strokeWidth(1)
          .color(this.palette().borderSubtle)

        // ---- 结果列表 ----
        if (this.keyword.trim().length === 0) {
          Column({ space: 6 }) {
            Text('输入关键词开始检索')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkSecondary)
            Text('支持中文标题、正文片段与 #标签，全部在本地完成。')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
          .width('100%')
          .padding({ top: 22, bottom: 22 })
          .alignItems(HorizontalAlign.Center)
        } else if (this.results.length === 0) {
          Column() {
            Text(this.searching ? '正在检索…' : '没有匹配的笔记')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkMuted)
          }
          .width('100%')
          .padding({ top: 22, bottom: 22 })
        } else {
          List({ space: 2 }) {
            ForEach(this.results, (result: NoteSearchResult) => {
              ListItem() {
                Column({ space: 3 }) {
                  Row({ space: 8 }) {
                    Text(result.title)
                      .fontSize(TypographyTokens.BODY_REGULAR)
                      .fontColor(this.palette().inkPrimary)
                      .fontWeight(FontWeight.Medium)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    if (result.matchedTags.length > 0) {
                      Text(result.matchedTags.join(' '))
                        .fontSize(TypographyTokens.TINY)
                        .fontColor(this.palette().accent)
                    }
                  }
                  .width('100%')

                  if (result.preview.length > 0) {
                    Text(result.preview)
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().inkMuted)
                      .maxLines(2)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .width('100%')
                  }
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .borderRadius(6)
                .hoverEffect(HoverEffect.Highlight)
                .onClick(() => {
                  const note: NoteItem | undefined = this.resolveNote(result.noteId);
                  if (note !== undefined) {
                    this.onSelectNote(note);
                  }
                })
              }
            }, (result: NoteSearchResult) => result.noteId)
          }
          .width('100%')
          .constraintSize({ maxHeight: 360 })
          .padding({ left: 6, right: 6, top: 6, bottom: 6 })
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .borderRadius(10)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 32, color: 'rgba(0,0,0,0.22)' })
      .border({ width: 1, color: this.palette().border })
      .transition(
        TransitionEffect.scale({ x: 0.95, y: 0.95 })
          .combine(TransitionEffect.OPACITY)
          .animation({ duration: 180, curve: Curve.EaseInOut })
      )
      .onClick(() => {
        // 消费卡片内的点击，避免冒泡到遮罩导致弹窗被关闭
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 96 })
    .backgroundColor('rgba(0,0,0,0.25)')
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    .onClick(() => this.onClose())
  }
}
