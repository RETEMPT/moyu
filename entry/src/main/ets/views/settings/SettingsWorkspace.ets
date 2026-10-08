import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { THEME_MODE_OPTIONS, ThemeModeOption, ThemeMode } from '../../common/theme/ThemeMode';
import { AppIcon } from '../common/AppIcon';
import { BrandMark } from '../brand/BrandMark';
import { ModelSettingsSheet } from './ModelSettingsSheet';
import { GUIDE_STEPS, GuideStep } from './UsageGuideSheet';
import { promptAction } from '@kit.ArkUI';
import { NoteItem } from '../../common/types/NoteItem';

interface SettingsSection { id: string; title: string; detail: string; icon: Resource; }
const SECTIONS: SettingsSection[] = [
  { id: 'library', title: '资料库', detail: '本机内容、备份与恢复', icon: $r('app.media.ic_folder') },
  { id: 'guide', title: '使用指引', detail: '新建、笔控与阅读', icon: $r('app.media.ic_help') },
  { id: 'theme', title: '主题风格', detail: '配色与动态效果', icon: $r('app.media.ic_cover') },
  { id: 'ai', title: 'AI 配置', detail: '本地、自配 API 与云 AI', icon: $r('app.media.ic_sparkle') },
  { id: 'cloud', title: '云服务与备份', detail: '未开放 · 本地备份可用', icon: $r('app.media.ic_cloud') },
  { id: 'legal', title: '协议与关于', detail: '隐私、版本与能力说明', icon: $r('app.media.ic_read') }
];

@Component
export struct SettingsWorkspace {
  @Prop @Watch('selectInitial') initialSection: string = 'overview';
  @Prop noteCount: number = 0;
  @Prop projectCount: number = 0;
  @Prop @Watch('handleBack') backRequestToken: number = 0;
  onExit: () => void = () => {};
  onOpenLibrary: () => void = () => {};
  onOpenBackup: () => void = () => {};
  onImportExample: () => Promise<NoteItem | null> = async () => null;
  onOpenPrivacy: () => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @StorageProp('flowmindReduceMotion') reduceMotion: boolean = false;
  @State section: string = 'overview';
  @State themeMode: ThemeMode = ThemeMode.SYSTEM;
  @State modelCloseToken: number = 0;
  @State sampleBusy: boolean = false;
  aboutToAppear(): void { this.selectInitial(); this.themeMode = ThemeManager.currentMode(); }
  private selectInitial(): void { this.section = this.initialSection; }
  private handleBack(): void {
    if (this.section === 'ai') { this.modelCloseToken++; }
    else if (this.section === 'overview') { this.onExit(); }
    else { this.section = 'overview'; }
  }
  @Builder
  item(item: SettingsSection) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        AppIcon({ source: item.icon, iconSize: 22, tint: ThemeHelper.paletteOfDark(this.dark).accent })
        Column({ space: 4 }) {
          Text(item.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary)
          if (this.section === 'overview') {
            Text(item.detail).fontSize(12).fontColor(ThemeHelper.paletteOfDark(this.dark).inkMuted)
          }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        AppIcon({ source: $r('app.media.ic_chevron_right'), iconSize: 16, tint: ThemeHelper.paletteOfDark(this.dark).inkMuted })
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 56 }).padding(14).borderRadius(14)
      .backgroundColor(this.section === item.id ? ThemeHelper.paletteOfDark(this.dark).accentSoft : ThemeHelper.paletteOfDark(this.dark).surface)
      .accessibilityText(`${item.title}，${item.detail}`).onClick(() => { this.section = item.id; })
  }
  @Builder
  paragraph(text: string) {
    Text(text).fontSize(14).lineHeight(23).width('100%').fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary)
  }
  @Builder
  content() {
    if (this.section === 'ai') {
      ModelSettingsSheet({ embedded: true, closeToken: this.modelCloseToken, onClose: () => { this.section = 'overview'; } })
    } else {
      Scroll() {
        Column({ space: 18 }) {
          if (this.section === 'overview') {
            Row({ space: 14 }) {
              BrandMark({ markSize: 60 })
              Column({ space: 4 }) {
                Text('墨语').fontSize(25).fontWeight(FontWeight.Bold).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary)
                Text('资料、笔记与伴读').fontSize(13).fontColor(ThemeHelper.paletteOfDark(this.dark).inkMuted)
              }.alignItems(HorizontalAlign.Start)
            }.width('100%')
            this.paragraph('在本机整理课程资料、阅读 PDF 和手写记录。默认离线使用，需要生成式问答时再配置自己的 API。')
            ForEach(SECTIONS, (item: SettingsSection) => { this.item(item) })
          } else if (this.section === 'library') {
            this.paragraph(`${this.noteCount} 份资料 · ${this.projectCount} 个项目`)
            this.paragraph('资料留在应用沙箱。卸载和换机前请导出备份，恢复会创建副本。')
            Button('查看资料库').height(48).width('100%').onClick(this.onOpenLibrary)
            Button('本地备份与附近传递').height(48).width('100%').onClick(this.onOpenBackup)
            Button(this.sampleBusy ? '正在导入…' : '导入阅读测试 PDF').height(48).width('100%').enabled(!this.sampleBusy)
              .onClick(async () => {
                this.sampleBusy = true;
                try { await this.onImportExample(); } finally { this.sampleBusy = false; }
              })
            this.paragraph('测试 PDF 含中文、英文、符号与两页内容。仅在点击导入时加入资料库。')
            this.paragraph('云服务与云备份未开放。本地文件备份可正常导出与恢复。')
            this.paragraph('备份为明文，包含资料、原 PDF、封面、笔迹与题卡；不含待办、对话、回收站和模型密钥。')
          } else if (this.section === 'guide') {
            ForEach(GUIDE_STEPS, (step: GuideStep) => {
              Column({ space: 8 }) {
                Text(step.title).fontSize(16).fontWeight(FontWeight.Bold).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary).width('100%')
                this.paragraph(step.text)
              }.padding(16).borderRadius(14).backgroundColor(ThemeHelper.paletteOfDark(this.dark).surface).width('100%')
            })
          } else if (this.section === 'cloud') {
            AppIcon({ source: $r('app.media.ic_cloud'), iconSize: 48, tint: ThemeHelper.paletteOfDark(this.dark).inkMuted })
            this.paragraph('云服务、云 AI 与云备份：未开放。')
            this.paragraph('当前可使用本地文件备份；需要生成式问答时，可在 AI 配置中填写自己的 API。')
            Button('云备份 · 未开放').height(48).width('100%').enabled(false)
            Button('本地备份与附近传递').height(48).width('100%').onClick(this.onOpenBackup)
          } else if (this.section === 'theme') {
            ForEach(THEME_MODE_OPTIONS, (option: ThemeModeOption) => {
              Button({ type: ButtonType.Normal }) {
                Row({ space: 12 }) {
                  Column({ space: 5 }) {
                    Text(option.label).fontSize(15).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary)
                    Text(option.hint).fontSize(12).fontColor(ThemeHelper.paletteOfDark(this.dark).inkMuted)
                  }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                  if (this.themeMode === option.mode) { AppIcon({ source: $r('app.media.ic_check'), tint: ThemeHelper.paletteOfDark(this.dark).accent }) }
                }
              }.width('100%').padding(16).borderRadius(14).backgroundColor(ThemeHelper.paletteOfDark(this.dark).surface)
                .onClick(async () => {
                  try { await ThemeManager.setMode(option.mode); this.themeMode = option.mode; }
                  catch { promptAction.showToast({ message: '主题保存失败，请重试' }); }
                })
            })
            Row({ space: 12 }) {
              Text('减少动态效果').fontSize(15).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.reduceMotion }).onChange(async (value: boolean) => {
                try { await ThemeManager.setReduceMotion(value); }
                catch { promptAction.showToast({ message: '设置保存失败，请重试' }); }
              })
            }.padding(16).borderRadius(14).backgroundColor(ThemeHelper.paletteOfDark(this.dark).surface)
            this.paragraph('应用内主题立即生效；桌面备用图标需要系统 API 26 及启动器支持。')
          } else {
            this.paragraph('FlowMind（墨语）1.0.3')
            this.paragraph('默认本地助手按原文检索和摘录。自配 API 由你授权发送资料，云 AI 尚未开放。')
            Button('隐私说明与数据协议').height(48).width('100%').onClick(this.onOpenPrivacy)
            this.paragraph('系统分享由你选择接收方；原 PDF 分享不含应用内笔迹。附近传递需要双方主动确认，接收到的资料以副本加入本机。')
            this.paragraph('开源项目：RETEMPT/moyu · Github.com/RETEMPT/moyu')
          }
        }.width('100%').constraintSize({ maxWidth: 760 }).padding(this.phone ? 16 : 24).alignItems(HorizontalAlign.Start)
      }.width('100%').height('100%').scrollBar(BarState.Auto)
    }
  }
  build() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        if (this.section !== 'overview') {
          Button({ type: ButtonType.Normal }) { AppIcon({ source: $r('app.media.ic_back'), tint: ThemeHelper.paletteOfDark(this.dark).inkPrimary }) }
            .width(44).height(44).padding(0).backgroundColor(Color.Transparent).accessibilityText('返回设置').onClick(() => this.handleBack())
        }
        Text(this.section === 'overview' ? '设置' : SECTIONS.find((s: SettingsSection) => s.id === this.section)?.title || '设置')
          .fontSize(22).fontWeight(FontWeight.Bold).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary).layoutWeight(1)
      }.width('100%').padding({ left: 16, right: 16, top: 8, bottom: 8 })
      Row({ space: 12 }) {
        if (!this.phone && this.section !== 'overview' && this.section !== 'ai') {
          Column({ space: 8 }) { ForEach(SECTIONS, (item: SettingsSection) => { this.item(item) }) }.width(200).padding(12)
        }
        Column() { this.content() }.layoutWeight(1).height('100%')
      }.layoutWeight(1).width('100%')
    }.width('100%').height('100%').backgroundColor(ThemeHelper.paletteOfDark(this.dark).canvas)
  }
}
