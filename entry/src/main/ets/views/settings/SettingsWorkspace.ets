import { ThemeHelper } from '../../common/theme/ThemeHelper';
import BuildProfile from 'BuildProfile';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { THEME_MODE_OPTIONS, ThemeModeOption, ThemeMode } from '../../common/theme/ThemeMode';
import { THEME_STYLE_OPTIONS, ThemeStyleOption, paletteForStyle } from '../../common/theme/ThemeStyle';
import { ColorPalette } from '../../common/constants/DesignTokens';
import { SETTINGS_GROUPS, SettingsGroup, SettingsEntry, SettingsCatalog } from '../../common/constants/SettingsCatalog';
import { AppIcon } from '../common/AppIcon';
import { IconButton } from '../common/IconButton';
import { BrandMark } from '../brand/BrandMark';
import { GUIDE_STEPS, GuideStep } from './UsageGuideSheet';
import { promptAction } from '@kit.ArkUI';
import { NoteItem } from '../../common/types/NoteItem';
import { bundleManager } from '@kit.AbilityKit';

@Component
export struct SettingsWorkspace {
  @Prop @Watch('selectInitial') initialSection: string = 'overview';
  @Prop @Watch('selectInitial') openRequestToken: number = 0;
  @Prop noteCount: number = 0;
  @Prop projectCount: number = 0;
  @Prop @Watch('handleBack') backRequestToken: number = 0;
  @Prop @Watch('requestExit') exitRequestToken: number = 0;
  onExit: () => void = () => {};
  onExitConfirmed: () => void = () => {};
  onOpenLibrary: () => void = () => {};
  onOpenBackup: () => void = () => {};
  onOpenCapture: () => void = () => {};
  onImportExample: () => Promise<NoteItem | null> = async () => null;
  onImportSnapshot: () => Promise<NoteItem | null> = async () => null;
  onOpenPrivacy: () => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @StorageProp('flowmindReduceMotion') reduceMotion: boolean = false;
  @State section: string = 'overview';
  @State search: string = '';
  @State themeMode: ThemeMode = ThemeMode.SYSTEM;
  @State themeBusy: boolean = false;
  @State motionBusy: boolean = false;
  @State motionValue: boolean = false;
  @State detailCloseToken: number = 0;
  @State sampleBusy: boolean = false;
  @State version: string = '';
  @State detailReveal: number = 1;
  @State detailShift: number = 0;
  private alive: boolean = true;

  aboutToAppear(): void {
    this.alive = true; this.themeMode = ThemeManager.currentMode(); this.motionValue = this.reduceMotion; this.selectInitial();
    bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      .then((info: bundleManager.BundleInfo) => { if (this.alive) { this.version = info.versionName; } }).catch(() => {});
  }
  aboutToDisappear(): void { this.alive = false; }
  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark, this.themeStyle); }
  private selectInitial(): void { this.navigate(this.initialSection); }
  private handleBack(): void {
    if (this.section === 'overview') { this.onExit(); } else { this.navigate('overview'); }
  }
  private navigate(id: string): void {
    const target = SettingsCatalog.normalize(id);
    if (this.section === target) { return; }
    // A single rendered layout owns both the directory and the detail. Navigation's
    // Stack->Auto mode switch used to paint a full-width destination over the fading
    // directory and then re-lay it out into a split pane on the next frame.
    this.section = target;
    if (target === 'overview') { this.detailReveal = 1; this.detailShift = 0; return; }
    // A short reveal replaces the old Navigation page transition. It runs on one stable
    // layout, so it can never expose a second full-width destination behind the content.
    this.detailReveal = 0.86;
    this.detailShift = 6;
    animateTo({ duration: this.reduceMotion ? 0 : 150, curve: Curve.EaseOut }, () => {
      this.detailReveal = 1;
      this.detailShift = 0;
    });
  }
  private requestExit(): void { this.onExitConfirmed(); }
  private icon(id: string): Resource {
    if (id === 'theme') { return $r('app.media.ic_cover'); }
    if (id === 'capture') { return $r('app.media.ic_format'); }
    if (id === 'backup') { return $r('app.media.ic_cloud'); }
    if (id === 'ecosystem') { return $r('app.media.ic_pen'); }
    if (id === 'guide' || id === 'about') { return $r('app.media.ic_help'); }
    if (id === 'legal') { return $r('app.media.ic_read'); }
    return $r('app.media.ic_folder');
  }
  private async changeAppearance(mode?: ThemeMode, style?: string): Promise<void> {
    if (this.themeBusy) { return; }
    this.themeBusy = true;
    try {
      if (mode !== undefined) { await ThemeManager.setMode(mode); }
      if (style !== undefined) { await ThemeManager.setStyle(style); }
      if (this.alive) { this.themeMode = ThemeManager.currentMode(); }
    } catch { promptAction.showToast({ message: '外观保存失败，请重试' }); }
    finally { if (this.alive) { this.themeBusy = false; } }
  }
  @Builder
  paragraph(text: string) {
    Text(text).fontSize(14).lineHeight(23).width('100%').fontColor(this.palette().inkSecondary)
  }
  @Builder
  heading(text: string) {
    Text(text).fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
  }
  @Builder
  action(label: string, handler: () => void, primary: boolean = false, available: boolean = true) {
    Button(label).type(ButtonType.Normal).constraintSize({ minHeight: 48 }).width('100%').padding(12).borderRadius(5)
      .fontColor(primary ? this.palette().onAccent : this.palette().inkPrimary)
      .backgroundColor(primary ? this.palette().accent : this.palette().surfaceSubtle)
      .enabled(available).onClick(handler)
  }
  @Builder
  entry(item: SettingsEntry) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        AppIcon({ source: this.icon(item.id), iconSize: 21, tint: this.palette().inkSecondary })
        Column({ space: 4 }) {
          Text(item.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
          Text(item.detail).fontSize(12).fontColor(this.palette().inkMuted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        AppIcon({ source: $r('app.media.ic_chevron_right'), iconSize: 16, tint: this.palette().inkMuted })
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 64 }).padding(14).borderRadius(5)
      .backgroundColor(this.section === item.id ? this.palette().accentSoft : this.palette().surface)
      .accessibilityText(`${item.title}，${item.detail}`).accessibilityDescription(this.section === item.id ? '当前页面' : '打开详情')
      .onClick(() => this.navigate(item.id))
  }
  @Builder
  directory() {
    Scroll() {
      Column({ space: 18 }) {
        Row({ space: 10 }) {
          BrandMark({ markSize: 38 })
          Column({ space: 4 }) {
            Text('设置').fontSize(24).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
            Text('让工作空间适合你的习惯').fontSize(12).fontColor(this.palette().inkMuted)
          }.alignItems(HorizontalAlign.Start)
        }.width('100%')
        TextInput({ text: this.search, placeholder: '搜索设置，如主题、备份、OCR' }).height(48)
          .fontSize(14).fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
          .accessibilityText('搜索设置').onChange((value: string) => { this.search = value; })
        if (SettingsCatalog.search(this.search).length === 0) {
          this.heading('没有找到设置')
          this.paragraph('试试“主题”“备份”或“文字识别”，也可以清空搜索浏览分类。')
          this.action('清空搜索', () => { this.search = ''; })
        }
        ForEach(SETTINGS_GROUPS, (group: SettingsGroup) => {
          if (SettingsCatalog.search(this.search, group.id).length > 0) {
            Column({ space: 6 }) {
              Text(group.title).fontSize(12).fontWeight(FontWeight.Medium).fontColor(this.palette().inkMuted).width('100%').padding({ bottom: 4 })
              ForEach(SettingsCatalog.search(this.search, group.id), (item: SettingsEntry) => { this.entry(item) }, (item: SettingsEntry) => item.id)
            }.width('100%')
          }
        }, (group: SettingsGroup) => group.id)
      }.width('100%').constraintSize({ maxWidth: 760 }).padding(16).alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Auto)
  }
  @Builder
  themePreview(style: string) {
    Row() {
      Column({ space: 6 }) {
        Row().width(12).height(5).borderRadius(2).backgroundColor(paletteForStyle(this.dark, style).accent)
        Row().width(14).height(12).borderRadius(3).backgroundColor(paletteForStyle(this.dark, style).accentSoft)
        Row().width(12).height(3).borderRadius(2).backgroundColor(paletteForStyle(this.dark, style).border)
        Row().width(12).height(3).borderRadius(2).backgroundColor(paletteForStyle(this.dark, style).border)
      }.width(30).height(68).padding(8).backgroundColor(paletteForStyle(this.dark, style).sidebar)
      Column({ space: 7 }) {
        Row() {
          Row().width('42%').height(4).borderRadius(2).backgroundColor(paletteForStyle(this.dark, style).inkMuted)
          Blank()
          Circle({ width: 7, height: 7 }).fill(paletteForStyle(this.dark, style).accent)
        }.width('100%')
        Row().width('100%').height(12).borderRadius(3).backgroundColor(paletteForStyle(this.dark, style).accentSoft)
        Row().width('80%').height(4).borderRadius(2).backgroundColor(paletteForStyle(this.dark, style).border)
        Row().width('60%').height(4).borderRadius(2).backgroundColor(paletteForStyle(this.dark, style).border)
      }.layoutWeight(1).height(68).padding(9).alignItems(HorizontalAlign.Start).backgroundColor(paletteForStyle(this.dark, style).surface)
    }.width('100%').height(68).borderRadius(9).clip(true).border({ width: 1, color: paletteForStyle(this.dark, style).borderSubtle })
      .accessibilityLevel('no-hide-descendants')
  }
  @Builder
  themeCard(option: ThemeStyleOption) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        this.themePreview(option.id)
        Row({ space: 4 }) {
          Text(option.label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).layoutWeight(1)
          if (this.themeStyle === option.id) {
            AppIcon({ source: $r('app.media.ic_check'), iconSize: 18, tint: this.palette().accent })
          } else {
            Circle({ width: 16, height: 16 }).fill(Color.Transparent).stroke(this.palette().inkMuted).strokeWidth(1)
          }
        }.width('100%')
        Text(option.hint).fontSize(11).fontColor(this.palette().inkMuted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').padding(12).borderRadius(5)
      .backgroundColor(this.themeStyle === option.id ? this.palette().accentSoft : this.palette().surface)
      .border({ width: 1, color: this.themeStyle === option.id ? this.palette().accent : this.palette().borderSubtle })
      .accessibilityText(`主题配色 ${option.label}`).accessibilityDescription(this.themeStyle === option.id ? '已选中' : option.hint)
      .enabled(!this.themeBusy).onClick(() => this.changeAppearance(undefined, option.id))
  }
  @Builder
  themePage() {
    this.heading('主题配色')
    this.paragraph('配色与明暗分别选择。')
    GridRow({ columns: 2, gutter: 12 }) {
      ForEach(THEME_STYLE_OPTIONS, (option: ThemeStyleOption) => {
        GridCol() { this.themeCard(option) }
      }, (option: ThemeStyleOption) => option.id)
    }.width('100%')
    this.heading('明暗模式')
    Row({ space: 4 }) {
      ForEach(THEME_MODE_OPTIONS, (option: ThemeModeOption) => {
        Button(option.label, { type: ButtonType.Normal }).layoutWeight(1).height(44).padding({ left: 4, right: 4 }).borderRadius(5)
          .fontSize(13).fontColor(this.themeMode === option.mode ? this.palette().accent : this.palette().inkSecondary)
          .backgroundColor(this.themeMode === option.mode ? this.palette().accentSoft : Color.Transparent)
          .border({ width: 1, color: this.themeMode === option.mode ? this.palette().accent : Color.Transparent }).enabled(!this.themeBusy)
          .accessibilityText(option.label).accessibilityDescription(this.themeMode === option.mode ? '已选中' : option.hint)
          .onClick(() => this.changeAppearance(option.mode))
      }, (option: ThemeModeOption) => String(option.mode))
    }.width('100%').padding(4).borderRadius(5).backgroundColor(this.palette().surfaceSubtle)
    Row({ space: 12 }) {
      Text('减少动态效果').fontSize(15).fontColor(this.palette().inkPrimary).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.motionValue }).selectedColor(this.palette().accent).enabled(!this.motionBusy).onChange(async (value: boolean) => {
        this.motionValue = value; this.motionBusy = true;
        try { await ThemeManager.setReduceMotion(value); }
        catch { this.motionValue = this.reduceMotion; promptAction.showToast({ message: '设置保存失败，请重试' }); }
        finally { if (this.alive) { this.motionBusy = false; } }
      })
    }.width('100%').padding(16).borderRadius(5).backgroundColor(this.palette().surface)
    this.paragraph('原图、封面与笔迹保留原色。')
  }
  @Builder
  detail() {
    if (this.section === 'theme') {
      this.themePage()
    } else if (this.section === 'library') {
      this.heading(`${this.noteCount} 份资料 · ${this.projectCount} 个项目`)
      this.paragraph('课程笔记、PDF 和手写记录在资料库中统一管理。按项目分类，收藏常用内容，通过搜索快速返回原文。')
      this.action('打开资料库', this.onOpenLibrary, true)
      this.heading('数据存放在哪里')
      this.paragraph('资料保存在应用沙箱。卸载前或换机前，请导出本地备份；重新安装不会自动找回旧资料。')
      this.action('备份与快传', () => this.navigate('backup'))
    } else if (this.section === 'capture') {
      this.heading('收集和整理原文')
      this.paragraph('图片由鸿蒙系统文字识别处理，识别后先校对，再使用本地规则排版。粘贴文字也可以直接整理，在本机完成。')
      this.action('识别与整理文字', this.onOpenCapture, true)
      this.heading('两种整理方式')
      this.paragraph('保留原文：保留原顺序与段落。学习笔记：将明确的标题和项目符号整理成层级，不补写原文没有的知识。')
      this.paragraph('图片断行可主动合并，代码、表格、公式和空段受到保护。保存前可修改标题与正文；待办由你逐项选择。')
      this.heading('获得更清晰的结果')
      this.paragraph('优先选正向、清晰、无反光的单栏图片。姓名、日期、数字、公式及多栏阅读顺序需要核对；模糊或严重倾斜的图片请重新拍摄。')
    } else if (this.section === 'backup') {
      this.heading('备份与快传')
      this.paragraph('勾选资料后导出文件，或通过系统分享面板选择附近设备。收到资料包后选择导入，恢复为副本。')
      this.action('选择资料', this.onOpenBackup, true)
      this.heading('备份范围')
      this.paragraph('资料包包含所选正文、原 PDF、原始图片、封面、笔迹与题卡，不含待办和回收站。文件未加密，请妥善保管。')
      this.heading('接收设备')
      this.paragraph('设备发现和传输方式由系统提供。请在系统面板确认接收设备，打开面板不表示已送达。')
    } else if (this.section === 'ecosystem') {
      this.heading('与系统能力协作')
      this.paragraph('手机保留底部导航；Pad 使用同一组图标。布局跟随窗口宽度，分屏或小窗口会收为单页。')
      this.heading('系统分享与文件')
      this.paragraph('导入 PDF 会复制到本机资料库，保留外部原文件，重启后可继续阅读。文字整理导入的资料在“外部参考”中查看。系统分享可选择接收方；分享原 PDF 不包含应用内笔迹，完整笔迹可通过资料备份传递。')
      this.heading('手写笔')
      this.paragraph('笔在系统中配对。应用处理笔/手指分流、压力、撤销与重做；双击与轻捏依赖 Penkit、笔型号和设备支持，需在支持设备上验收。')
      this.heading('文字识别')
      this.paragraph(canIUse('SystemCapability.AI.OCR.TextRecognition') ? '系统声明支持文字识别；可以从图片提取文字，实际效果与图片清晰度有关。' : '此设备未声明系统文字识别能力，可粘贴文字进行本地排版。')
      this.paragraph('资料快传调用系统分享，不申请应用级设备数据同步权限。')
      this.action('备份与快传', () => this.navigate('backup'))
      this.action('文字识别与排版', () => this.navigate('capture'))
    } else if (this.section === 'guide') {
      ForEach(GUIDE_STEPS, (step: GuideStep) => {
        Column({ space: 8 }) { this.heading(step.title); this.paragraph(step.text) }
          .padding(16).borderRadius(5).backgroundColor(this.palette().surface).width('100%')
      })
      if (BuildProfile.DEBUG) {
      this.heading('阅读测试资料')
      this.paragraph('已自动加入一份两页 PDF，在「示例资料」打开即可检查阅读与批注。下面可另行导入一份副本。')
      this.action(this.sampleBusy ? '正在导入…' : '导入阅读测试 PDF', async () => {
        this.sampleBusy = true;
        try { await this.onImportExample(); } finally { if (this.alive) { this.sampleBusy = false; } }
      }, false, !this.sampleBusy)
      this.paragraph('快照测试 PDF 由两页图片组成，可检查扫描资料的显示、翻页与批注；提取文字时需要启用图片识别。')
      this.action(this.sampleBusy ? '正在导入…' : '导入快照测试 PDF', async () => {
        if (this.sampleBusy) { return; }
        this.sampleBusy = true;
        try { await this.onImportSnapshot(); } finally { if (this.alive) { this.sampleBusy = false; } }
      }, false, !this.sampleBusy)
      }
    } else if (this.section === 'legal') {
      this.heading('本地整理，分享由你选择')
      this.paragraph('图片由系统文字识别处理，校对后通过本地规则整理。资料保存在本机，分享与传递由你主动发起。')
      this.action('阅读隐私说明与数据协议', this.onOpenPrivacy, true)
      this.heading('控制你的数据')
      this.paragraph('删除资料先进入回收站；清空需确认。系统分享由你选择接收方，附近传递接收的是副本。本地备份是明文，请自行保护。')
    } else {
      BrandMark({ markSize: 64 })
      this.heading(`墨语 · FlowMind ${this.version}`)
      this.paragraph('面向校园的本地知识工作空间：资料整理、PDF 阅读、手写记录、日程与复习，支持原文搜索与本地规则排版。')
      this.heading('当前产品范围')
      this.paragraph('当前迭代专注本地资料、阅读批注、规则排版、待办与复习。图片文字识别使用设备系统能力，资料整理不依赖在线生成服务。')
      this.heading('开源与反馈')
      this.paragraph('开源项目：github.com/RETEMPT/moyu。反馈时请注明版本、设备和复现步骤，避免附带私人资料。')
      this.action('使用指引', () => this.navigate('guide'))
      this.action('隐私与数据', () => this.navigate('legal'))
    }
  }
  @Builder
  destinationTitle() {
    Row({ space: 8 }) {
      IconButton({ icon: $r('app.media.ic_back'), label: '返回设置', onAction: () => this.navigate('overview') })
      Text(SettingsCatalog.find(this.section)?.title || '设置').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
    }.width('100%')
  }
  @Builder
  detailPage() {
    Column() {
      this.destinationTitle()
      Scroll() {
        Column({ space: 18 }) { this.detail() }
          .width('100%').constraintSize({ maxWidth: 760 }).padding(this.phone ? 16 : 24).alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    }.width('100%').height('100%').padding({ left: this.phone ? 0 : 8, right: this.phone ? 0 : 8, top: 8 })
      .opacity(this.detailReveal).translate({ x: this.detailShift })
      .backgroundColor(this.palette().canvas)
  }
  build() {
    if (this.phone) {
      if (this.section === 'overview') { this.directory() }
      else { this.detailPage() }
    } else {
      Row() {
        if (this.section === 'overview') {
          this.directory()
        } else {
          Column() { this.directory() }.width(280).height('100%')
          Divider().vertical(true).strokeWidth(1).height('100%').color(this.palette().borderSubtle)
          Column() { this.detailPage() }.layoutWeight(1).height('100%')
        }
      }.width('100%').height('100%').backgroundColor(this.palette().canvas)
    }
  }
}
