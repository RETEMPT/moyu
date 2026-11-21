import { ColorPalette } from '../../common/constants/DesignTokens';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { LearningCitation, LearningSection } from '../../common/types/LearningResult';
import { NoteItem } from '../../common/types/NoteItem';
import { ReaderPairPolicy } from '../../services/document/ReaderPairPolicy';
import { MarkdownLinkService } from '../../services/document/MarkdownLinkService';
import { StudyRunStep, StudyWebSource } from '../../services/study/StudyAssistantGateway';
import { StudySourceFocus, StudyWorkspaceResult, StudyWorkspaceSources } from '../../services/study/StudyWorkspaceSources';
import { AppIcon } from '../common/AppIcon';
import { DocumentText } from '../common/DocumentText';
import { IconButton } from '../common/IconButton';
import { MarkdownReader } from '../reader/MarkdownReader';
import { PdfAnnotatorView } from '../reader/pdf/PdfAnnotatorView';

export const STUDY_ACCENT: string = '#256D65';

export interface StudyReference extends StudySourceFocus {
  revision: number;
}

@Component
export struct StudyReferencePane {
  @Require @Prop note: NoteItem;
  @Require @Prop @Watch('reset') reference: StudyReference;
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'mono';
  @State private page: number = 1;
  onClose: () => void = () => {};

  aboutToAppear(): void { this.reset(); }
  private reset(): void { this.page = this.reference.page || 1; }
  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark, this.style); }

  build() {
    Column() {
      Row({ space: 6 }) {
        Column({ space: 3 }) {
          Text(this.note.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(this.reference.page ? `引用 · 第 ${this.reference.page} 页` : `引用 · 第 ${this.reference.line || 1} 行`)
            .fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        IconButton({ icon: $r('app.media.ic_close'), label: '关闭引用分屏', onAction: this.onClose })
      }.width('100%').height(58).padding({ left: 12, right: 6 })
      Text(this.reference.quote).fontSize(13).lineHeight(20).fontColor(this.palette().inkSecondary)
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%').padding(10)
        .backgroundColor(this.palette().surfaceSubtle).copyOption(CopyOptions.LocalDevice)
      Column() {
        if (ReaderPairPolicy.isPdf(this.note)) {
          PdfAnnotatorView({ note: this.note, currentPage: this.page, isContinuousScroll: false,
            onPageChanged: (value: number) => { this.page = value; } })
        } else {
          MarkdownReader({ note: this.note, readingOnly: true, compactPane: true, companionPane: true,
            manageKeyboardMode: false, showBackButton: false,
            jumpLine: (this.reference.line || 1) - 1, jumpToken: this.reference.revision })
        }
      }.width('100%').layoutWeight(1).clip(true)
      if (ReaderPairPolicy.isPdf(this.note)) {
        Row() {
          IconButton({ icon: $r('app.media.ic_chevron_left'), label: '引用上一页', available: this.page > 1,
            onAction: () => { this.page--; } })
          Text(`${this.page} / ${this.note.pageCount || 1}`).fontSize(13).fontColor(this.palette().inkPrimary)
          IconButton({ icon: $r('app.media.ic_chevron_right'), label: '引用下一页', available: this.page < (this.note.pageCount || 1),
            onAction: () => { this.page++; } })
        }.width('100%').justifyContent(FlexAlign.Center)
      }
    }.width('100%').height('100%').backgroundColor(this.palette().surface)
      .border({ width: { left: 1 }, color: this.palette().borderSubtle }).id('study-reference-pane')
  }
}

@Component
export struct StudyRunTrace {
  @Prop steps: StudyRunStep[] = [];
  @Prop active: boolean = false;
  @Prop failed: boolean = false;
  @Prop stopped: boolean = false;
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'mono';
  @State private expanded: boolean = false;

  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark, this.style); }

  private toolCount(): number { return this.steps.filter((step: StudyRunStep) => step.kind === 'tool').length; }

  build() {
    Column({ space: 6 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Text(this.active ? '正在运行' : this.failed ? '运行中断' : this.stopped ? '已停止' : '运行轨迹')
            .fontSize(13).fontColor(this.failed ? this.palette().danger : this.palette().inkPrimary)
          Text(`${this.steps.length} 步`).fontSize(12).fontColor(this.palette().inkSecondary)
          if (this.toolCount()) {
            Text(`${this.toolCount()} 次工具调用`).fontSize(12).fontColor(this.palette().inkSecondary)
          }
          Blank()
          Text(this.expanded ? '收起' : '展开').fontSize(12).fontColor(this.palette().inkSecondary)
        }.width('100%')
      }.height(42).width('100%').padding({ left: 10, right: 10 }).borderRadius(8).backgroundColor(Color.Transparent)
        .accessibilityText('查看运行轨迹').onClick(() => { this.expanded = !this.expanded; })
      if (this.expanded) {
        ForEach(this.steps, (step: StudyRunStep, index: number) => {
          Column({ space: 4 }) {
            Text(`${index + 1} · ${step.title}`).fontSize(13).fontWeight(FontWeight.Medium)
              .fontColor(this.palette().inkPrimary).width('100%')
            Text(step.detail).fontSize(13).lineHeight(20).fontColor(this.palette().inkSecondary).width('100%')
              .copyOption(CopyOptions.LocalDevice)
          }.width('100%').padding({ left: 12, right: 12, bottom: 9 })
        }, (step: StudyRunStep, index: number) => `${index}-${step.kind}-${step.detail.length}`)
      } else if (this.active && this.steps.length) {
        Text(this.steps[this.steps.length - 1].title).fontSize(12).fontColor(this.palette().inkSecondary)
          .width('100%').padding({ left: 10, right: 10, bottom: 8 })
      }
    }.width('100%').borderRadius(10).backgroundColor(this.palette().surfaceSubtle).id('study-run-trace')
  }
}

@Component
struct StudySourceLink {
  @Prop label: string = '';
  @Prop locationLabel: string = '';
  @Require @Prop icon: Resource;
  onOpen: () => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'mono';

  private linkColor(): ResourceColor { return ThemeHelper.paletteOfDark(this.dark, this.style).link; }

  build() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 5 }) {
        AppIcon({ source: this.icon, iconSize: 15, tint: this.linkColor() })
        Text(this.label).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.linkColor())
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: this.locationLabel ? '70%' : '93%' })
        if (this.locationLabel) { Text('· ' + this.locationLabel).fontSize(12).fontColor(this.linkColor()).maxLines(1) }
      }.constraintSize({ maxWidth: '100%' })
    }.height(40).constraintSize({ maxWidth: '100%' }).padding({ left: 4, right: 8 })
      .borderRadius(6).backgroundColor(Color.Transparent).hoverEffect(HoverEffect.Highlight)
      .accessibilityText(this.locationLabel ? `${this.label} · ${this.locationLabel}` : this.label).onClick(this.onOpen)
  }
}

@Component
export struct StudyWebSources {
  @Prop sources: StudyWebSource[] = [];
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'mono';

  private async open(source: StudyWebSource): Promise<void> {
    try { await MarkdownLinkService.open(this.getUIContext().getHostContext() as common.UIAbilityContext, source.url); }
    catch { promptAction.showToast({ message: '网页来源未能打开', duration: 2000 }); }
  }

  build() {
    if (this.sources.length > 0) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        ForEach(this.sources, (source: StudyWebSource) => {
          StudySourceLink({ label: source.title, icon: $r('app.media.ic_link'), onOpen: () => { this.open(source); } })
        }, (source: StudyWebSource) => source.url)
      }.width('100%')
    } else {
      Text('本轮未返回网页来源').fontSize(12).fontColor(ThemeHelper.paletteOfDark(this.dark, this.style).inkSecondary)
    }
  }
}

@Component
struct StudyCitationRow {
  @Require @Prop entry: StudyWorkspaceResult;
  @Prop citations: LearningCitation[] = [];
  onOpen: (entry: StudyWorkspaceResult, citation: LearningCitation) => void = () => {};

  private label(citation: LearningCitation): string {
    return this.entry.locations.find(item => item.sourceId === citation.source_id)?.title || '查看引用原文';
  }

  private locationLabel(citation: LearningCitation): string {
    const location = this.entry.locations.find(item => item.sourceId === citation.source_id);
    return location ? StudyWorkspaceSources.position(this.entry, citation, location) : '';
  }

  build() {
    Column({ space: 6 }) {
      Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
        ForEach(this.citations, (citation: LearningCitation, index: number) => {
          StudySourceLink({ label: this.label(citation), locationLabel: this.locationLabel(citation), icon: $r('app.media.ic_note'),
            onOpen: () => this.onOpen(this.entry, citation) })
        }, (citation: LearningCitation, index: number) => this.entry.result.job_id + '-' + citation.source_id + '-' + index)
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct StudyGroundedContent {
  @Require @Prop entry: StudyWorkspaceResult;
  onOpen: (entry: StudyWorkspaceResult, citation: LearningCitation) => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'mono';

  build() {
    Column({ space: 18 }) {
      ForEach(this.entry.result.sections, (section: LearningSection, index: number) => {
        Column({ space: 8 }) {
          Text(section.heading).width('100%').fontSize(index === 0 ? 20 : 17).lineHeight(index === 0 ? 28 : 24)
            .fontWeight(FontWeight.Bold)
            .fontColor(ThemeHelper.paletteOfDark(this.dark, this.style).inkPrimary)
          DocumentText({ text: section.body, allowLinks: false, chatLayout: true })
          StudyCitationRow({ entry: this.entry, citations: section.citations, onOpen: this.onOpen })
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (section: LearningSection, index: number) => this.entry.result.job_id + '-' + index)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
