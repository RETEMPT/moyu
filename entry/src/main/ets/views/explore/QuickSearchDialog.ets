/**
 * 全局快速搜索弹窗 (T5.1)
 *
 * Notion 风格居中浮层：对全库标题、正文与 #标签做实时匹配检索。
 * 检索走 NoteSearchService，正文来源是沙箱中的 .md 文件，不依赖任何网络。
 * 功能8：支持正则模式、命中高亮，搜索历史本地持久化（SearchHistoryService）。
 */
import { common } from '@kit.AbilityKit';
import { ColorPalette, LayoutTokens, TypographyTokens, AnimationTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { NoteSearchResult } from '../../common/types/NoteSearchResult';
import { NoteSearchService } from '../../services/NoteSearchService';
import { SearchHistoryService } from '../../services/SearchHistoryService';

/** 输入停止后再发起检索，避免逐字符读盘 */
const SEARCH_DEBOUNCE_MS: number = 260;

/** 功能8：命中高亮的文本片段（视图用） */
interface HighlightSeg {
  text: string;
  hit: boolean;
}

@Component
export struct QuickSearchDialog {
  @Prop notes: NoteItem[] = [];

  onClose: () => void = () => {};
  onSelectNote: (note: NoteItem) => void = () => {};

  @State keyword: string = '';
  @State results: NoteSearchResult[] = [];
  @State searching: boolean = false;
  /** 功能8：正则模式开关，开启后检索按正则匹配 */
  @State regexOn: boolean = false;
  /** 功能8：搜索历史（本地持久化，最新在前） */
  @State history: string[] = [];

  private searchService: NoteSearchService = new NoteSearchService();
  private historyService: SearchHistoryService = new SearchHistoryService();
  private searchTimer: number = -1;

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.loadHistory();
  }

  aboutToDisappear(): void {
    if (this.searchTimer !== -1) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
  }

  private async loadHistory(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      this.history = await this.historyService.load(context);
    } catch (error) {
      console.error(`搜索历史读取失败: ${JSON.stringify(error)}`);
      this.history = [];
    }
  }

  /** 记录本次查询到历史（去重置顶、截断、落盘） */
  private async recordHistory(keyword: string): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    try {
      this.history = await this.historyService.push(context, this.history, keyword);
    } catch (error) {
      console.error(`搜索历史写入失败: ${JSON.stringify(error)}`);
    }
  }

  private async clearHistory(): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    this.history = [];
    try {
      await this.historyService.clear(context);
    } catch (error) {
      console.error(`搜索历史清空失败: ${JSON.stringify(error)}`);
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

  /** 切换正则开关后，若已有关键词则立即按新模式重检索 */
  private toggleRegex(): void {
    this.regexOn = !this.regexOn;
    if (this.keyword.trim().length > 0) {
      this.searching = true;
      this.runSearch(this.keyword);
    }
  }

  private async runSearch(keyword: string): Promise<void> {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const useRegex: boolean = this.regexOn;
    try {
      const found: NoteSearchResult[] = await this.searchService.search(context, this.notes, keyword, useRegex);
      // 输入或模式可能已经变化，丢弃过期结果
      if (this.keyword === keyword && this.regexOn === useRegex) {
        this.results = found;
        if (found.length > 0) {
          this.recordHistory(keyword);
        }
      }
    } catch (error) {
      console.error(`全文检索失败: ${JSON.stringify(error)}`);
      if (this.keyword === keyword && this.regexOn === useRegex) {
        this.results = [];
      }
    } finally {
      if (this.keyword === keyword && this.regexOn === useRegex) {
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

  /** 功能8：把文本按当前关键词切成命中/未命中片段，用于高亮（支持正则模式） */
  private highlightSegs(text: string): HighlightSeg[] {
    const segs: HighlightSeg[] = [];
    const kw: string = this.keyword.trim();
    if (kw.length === 0) {
      const whole: HighlightSeg = { text: text, hit: false };
      segs.push(whole);
      return segs;
    }
    if (this.regexOn) {
      let re: RegExp | null = null;
      try {
        re = new RegExp(kw, 'gi');
      } catch (error) {
        re = null;
      }
      if (re === null) {
        segs.push({ text: text, hit: false });
        return segs;
      }
      let last: number = 0;
      let m: RegExpExecArray | null = re.exec(text);
      while (m !== null) {
        const idx: number = m.index;
        const len: number = m[0].length;
        if (len === 0) {
          // 零宽匹配：手动前进，避免死循环
          re.lastIndex = idx + 1;
          m = re.exec(text);
          continue;
        }
        if (idx > last) {
          segs.push({ text: text.substring(last, idx), hit: false });
        }
        segs.push({ text: text.substring(idx, idx + len), hit: true });
        last = idx + len;
        m = re.exec(text);
      }
      if (last < text.length) {
        segs.push({ text: text.substring(last), hit: false });
      }
      return segs;
    }
    const lower: string = text.toLowerCase();
    const klower: string = kw.toLowerCase();
    let i: number = 0;
    while (i < text.length) {
      const idx: number = lower.indexOf(klower, i);
      if (idx < 0) {
        const tail: HighlightSeg = { text: text.substring(i), hit: false };
        segs.push(tail);
        break;
      }
      if (idx > i) {
        const before: HighlightSeg = { text: text.substring(i, idx), hit: false };
        segs.push(before);
      }
      const hit: HighlightSeg = { text: text.substring(idx, idx + kw.length), hit: true };
      segs.push(hit);
      i = idx + kw.length;
    }
    return segs;
  }

  @Builder
  highlightedPreview(text: string) {
    Text() {
      ForEach(this.highlightSegs(text), (seg: HighlightSeg, index: number) => {
        Span(seg.text)
          .fontColor(seg.hit ? this.palette().accent : this.palette().inkMuted)
          .fontWeight(seg.hit ? FontWeight.Bold : FontWeight.Normal)
      }, (seg: HighlightSeg, index: number) => `${index}-${seg.hit ? 1 : 0}-${seg.text}`)
    }
    .fontSize(TypographyTokens.TINY)
    .maxLines(2)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .width('100%')
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
          // 功能8：正则模式开关
          Text('.*')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.regexOn ? Color.White : this.palette().inkMuted)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(6)
            .backgroundColor(this.regexOn ? this.palette().accent : this.palette().surfaceSubtle)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.toggleRegex())
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
          // 功能8：空输入时展示搜索历史
          Column({ space: 10 }) {
            Row() {
              Text('最近搜索')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
              Blank()
              Text('清除')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
                .onClick(() => this.clearHistory())
            }
            .width('100%')

            if (this.history.length === 0) {
              Text('输入关键词开始检索，全部在本地完成。')
                .fontSize(TypographyTokens.CAPTION)
                .fontColor(this.palette().inkSecondary)
                .width('100%')
                .padding({ top: 8, bottom: 8 })
            } else {
              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.history, (item: string) => {
                  Row({ space: 4 }) {
                    Text('🕘')
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().inkMuted)
                    Text(item)
                      .fontSize(TypographyTokens.CAPTION)
                      .fontColor(this.palette().inkSecondary)
                  }
                  .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  .borderRadius(12)
                  .backgroundColor(this.palette().surfaceSubtle)
                  .hoverEffect(HoverEffect.Highlight)
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => this.onKeywordChanged(item))
                }, (item: string) => item)
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 14, bottom: 18 })
          .alignItems(HorizontalAlign.Start)
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
                    this.highlightedPreview(result.preview)
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
        TransitionEffect.scale({ x: AnimationTokens.SCALE_MODAL_ENTER, y: AnimationTokens.SCALE_MODAL_ENTER })
          .combine(TransitionEffect.OPACITY)
          .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
      )
      .onClick(() => {
        // 消费卡片内的点击，避免冒泡到遮罩导致弹窗被关闭
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: this.isPhone ? 48 : 96 })
    .backgroundColor('rgba(0,0,0,0.25)')
    .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }))
    .onClick(() => this.onClose())
  }
}
