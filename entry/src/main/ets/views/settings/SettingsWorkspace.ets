import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { ThemeManager } from '../../common/theme/ThemeManager';
import { THEME_MODE_OPTIONS, ThemeModeOption, ThemeMode } from '../../common/theme/ThemeMode';
import { THEME_STYLE_OPTIONS, ThemeStyleOption, paletteForStyle } from '../../common/theme/ThemeStyle';
import { ColorPalette } from '../../common/constants/DesignTokens';
import { SETTINGS_GROUPS, SettingsGroup, SettingsEntry, SettingsCatalog } from '../../common/constants/SettingsCatalog';
import { AppIcon } from '../common/AppIcon';
import { IconButton } from '../common/IconButton';
import { BrandMark } from '../brand/BrandMark';
import { ModelSettingsSheet } from './ModelSettingsSheet';
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
  onOpenPrivacy: () => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @StorageProp('flowmindReduceMotion') reduceMotion: boolean = false;
  @State paths: NavPathStack = new NavPathStack();
  @State section: string = 'overview';
  @State search: string = '';
  @State themeMode: ThemeMode = ThemeMode.SYSTEM;
  @State themeBusy: boolean = false;
  @State motionBusy: boolean = false;
  @State motionValue: boolean = false;
  @State modelCloseToken: number = 0;
  @State sampleBusy: boolean = false;
  @State version: string = '';
  private pendingSection: string = 'overview';
  private leavePending: boolean = false;
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
    this.leavePending = false;
    this.pendingSection = target;
    if (this.section === 'ai') { this.modelCloseToken++; return; }
    this.applyNavigation();
  }
  private applyNavigation(): void {
    if (this.leavePending) { this.leavePending = false; this.onExitConfirmed(); return; }
    const target = this.pendingSection;
    if (target === 'overview') { this.paths.clear(!this.reduceMotion); }
    else if (this.paths.size() === 0) { this.paths.pushPath({ name: target }, !this.reduceMotion); }
    else { this.paths.replacePath({ name: target }, !this.reduceMotion); }
    this.section = target;
  }
  private requestExit(): void {
    this.leavePending = true;
    if (this.section === 'ai') { this.modelCloseToken++; } else { this.applyNavigation(); }
  }
  private icon(id: string): Resource {
    if (id === 'theme') { return $r('app.media.ic_cover'); }
    if (id === 'ai' || id === 'capture') { return $r('app.media.ic_sparkle'); }
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
    Button(label).type(ButtonType.Normal).constraintSize({ minHeight: 48 }).width('100%').padding(12).borderRadius(12)
      .fontColor(primary ? this.palette().onAccent : this.palette().inkPrimary)
      .backgroundColor(primary ? this.palette().accent : this.palette().surfaceSubtle)
      .enabled(available).onClick(handler)
  }
  @Builder
  entry(item: SettingsEntry) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        AppIcon({ source: this.icon(item.id), iconSize: 21, tint: this.palette().accent })
        Column({ space: 4 }) {
          Text(item.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
          Text(item.detail).fontSize(12).fontColor(this.palette().inkMuted)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        AppIcon({ source: $r('app.media.ic_chevron_right'), iconSize: 16, tint: this.palette().inkMuted })
      }.width('100%')
    }.width('100%').constraintSize({ minHeight: 64 }).padding(14).borderRadius(12)
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
          this.paragraph('试试“主题”“备份”或“API”，也可以清空搜索浏览分类。')
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
  themePage() {
    this.heading('主题配色')
    this.paragraph('配色与明暗模式分别选择，手机与 Pad 使用同一套界面样式。')
    ForEach(THEME_STYLE_OPTIONS, (option: ThemeStyleOption) => {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Row({ space: 3 }) {
            Column().width(18).height(34).backgroundColor(paletteForStyle(this.dark, option.id).canvas)
            Column().width(18).height(34).backgroundColor(paletteForStyle(this.dark, option.id).accent)
          }.padding(4).borderRadius(8).backgroundColor(paletteForStyle(this.dark, option.id).surfaceSubtle)
          Column({ space: 4 }) {
            Text(option.label).fontSize(15).fontColor(this.palette().inkPrimary)
            Text(option.hint).fontSize(12).fontColor(this.palette().inkMuted)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.themeStyle === option.id) { AppIcon({ source: $r('app.media.ic_check'), tint: this.palette().accent }) }
        }.width('100%')
      }.width('100%').padding(14).borderRadius(12).backgroundColor(this.themeStyle === option.id ? this.palette().accentSoft : this.palette().surface)
        .accessibilityText(`${option.label}，${option.hint}`).accessibilityDescription(this.themeStyle === option.id ? '已选中' : '')
        .enabled(!this.themeBusy).onClick(() => this.changeAppearance(undefined, option.id))
    }, (option: ThemeStyleOption) => option.id)
    this.heading('明暗模式')
    ForEach(THEME_MODE_OPTIONS, (option: ThemeModeOption) => {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 12 }) {
          Column({ space: 5 }) {
            Text(option.label).fontSize(15).fontColor(this.palette().inkPrimary)
            Text(option.hint).fontSize(12).fontColor(this.palette().inkMuted)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.themeMode === option.mode) { AppIcon({ source: $r('app.media.ic_check'), tint: this.palette().accent }) }
        }.width('100%')
      }.width('100%').padding(14).borderRadius(12).backgroundColor(this.palette().surface).enabled(!this.themeBusy)
        .accessibilityText(option.label).accessibilityDescription(this.themeMode === option.mode ? '已选中' : '')
        .onClick(() => this.changeAppearance(option.mode))
    })
    Row({ space: 12 }) {
      Text('减少动态效果').fontSize(15).fontColor(this.palette().inkPrimary).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.motionValue }).selectedColor(this.palette().accent).enabled(!this.motionBusy).onChange(async (value: boolean) => {
        this.motionValue = value; this.motionBusy = true;
        try { await ThemeManager.setReduceMotion(value); }
        catch { this.motionValue = this.reduceMotion; promptAction.showToast({ message: '设置保存失败，请重试' }); }
        finally { if (this.alive) { this.motionBusy = false; } }
      })
    }.width('100%').padding(16).borderRadius(12).backgroundColor(this.palette().surface)
    this.paragraph('文档封面、纸色和笔迹保留原色。桌面备用图标随明暗切换，需要系统 API 26 及启动器支持。')
  }
  @Builder
  detail(name: string) {
    if (name === 'theme') {
      this.themePage()
    } else if (name === 'library') {
      this.heading(`${this.noteCount} 份资料 · ${this.projectCount} 个项目`)
      this.paragraph('课程笔记、PDF 和手写记录在资料库中统一管理。按项目分类，收藏常用内容，通过搜索快速返回原文。')
      this.action('打开资料库', this.onOpenLibrary, true)
      this.heading('数据存放在哪里')
      this.paragraph('资料保存在应用沙箱。卸载前或换机前，请导出本地备份；重新安装不会自动找回旧资料。')
      this.action('备份与传递', () => this.navigate('backup'))
    } else if (name === 'capture') {
      this.heading('不配置大模型，也能收集和整理')
      this.paragraph('图片由鸿蒙系统文字识别处理，识别后先校对，再使用本地规则排版。粘贴文字也可以直接整理，不需要 Key。')
      this.action('识别与整理文字', this.onOpenCapture, true)
      this.heading('两种整理方式')
      this.paragraph('保留原文：保留原顺序与段落。学习笔记：将明确的标题和项目符号整理成层级，不补写原文没有的知识。')
      this.paragraph('图片断行可主动合并，代码、表格、公式和空段受到保护。保存前可修改标题与正文；待办由你逐项选择。')
      this.heading('获得更清晰的结果')
      this.paragraph('优先选正向、清晰、无反光的单栏图片。姓名、日期、数字、公式及多栏阅读顺序需要核对；模糊或严重倾斜的图片请重新拍摄。')
    } else if (name === 'backup') {
      this.heading('本地备份与附近传递')
      this.paragraph('导出文件留作换机备份；恢复时创建副本。附近传递需要双方主动确认，是否发现设备取决于系统授权、可信设备与网络条件。')
      this.action('打开备份与传递', this.onOpenBackup, true)
      this.heading('备份范围')
      this.paragraph('备份是明文文件，包含资料、原 PDF、封面、笔迹与题卡。不含待办、对话、回收站和模型密钥，请妥善保存文件。')
      this.heading('云服务状态')
      this.paragraph('团队云盘、云备份与云 AI 尚未开放。当前不会在后台自动上传资料，也不提供华为账号自动云同步。')
      this.action('AI 与模型', () => this.navigate('ai'))
    } else if (name === 'ecosystem') {
      this.heading('与系统能力协作')
      this.paragraph('手机保留底部导航；Pad 使用同一组图标。布局跟随窗口宽度，分屏或小窗口会收为单页。')
      this.heading('系统分享与文件')
      this.paragraph('使用系统文件选择器导入 PDF，通过系统分享选择接收方。分享原 PDF 不包含应用内笔迹，完整笔迹可通过资料备份传递。')
      this.heading('手写笔')
      this.paragraph('笔在系统中配对。应用处理笔/手指分流、压力、撤销与重做；双击与轻捏依赖 Penkit、笔型号和设备支持，需在支持设备上验收。')
      this.heading('文字识别与密钥')
      this.paragraph(canIUse('SystemCapability.AI.OCR.TextRecognition') ? '系统声明支持文字识别；无大模型配置即可从图片提取文字，实际效果与图片清晰度有关。' : '此设备未声明系统文字识别能力，可粘贴文字进行本地排版。')
      this.paragraph('自配 API 密钥由系统 HUKS 加密保护。不包含在资料备份中，换设备需要重新填写并授权。')
      this.action('备份与附近传递', () => this.navigate('backup'))
      this.action('文字识别与排版', () => this.navigate('capture'))
    } else if (name === 'guide') {
      ForEach(GUIDE_STEPS, (step: GuideStep) => {
        Column({ space: 8 }) { this.heading(step.title); this.paragraph(step.text) }
          .padding(16).borderRadius(12).backgroundColor(this.palette().surface).width('100%')
      })
      this.heading('阅读测试资料')
      this.paragraph('包含中文、英文和符号的两页 PDF，仅在主动导入后加入资料库，适合检查阅读与批注。')
      this.action(this.sampleBusy ? '正在导入…' : '导入阅读测试 PDF', async () => {
        this.sampleBusy = true;
        try { await this.onImportExample(); } finally { if (this.alive) { this.sampleBusy = false; } }
      }, false, !this.sampleBusy)
    } else if (name === 'legal') {
      this.heading('默认本地，联网由你选择')
      this.paragraph('离线助手按原文检索和摘录；图片识别与本地整理无需模型服务。自配 API 需要配置和授权，选用后相关输入才发送至你指定的服务商。')
      this.action('阅读隐私说明与数据协议', this.onOpenPrivacy, true)
      this.heading('控制你的数据')
      this.paragraph('删除资料先进入回收站；清空需确认。系统分享由你选择接收方，附近传递接收的是副本。本地备份是明文，请自行保护。')
      this.action('AI 授权与密钥配置', () => this.navigate('ai'))
    } else {
      BrandMark({ markSize: 64 })
      this.heading(`墨语 · FlowMind ${this.version}`)
      this.paragraph('面向校园的本地知识工作空间：资料整理、PDF 阅读、手写记录、日程与复习，配合离线检索和可选的自配 API。')
      this.heading('开源与反馈')
      this.paragraph('开源项目：github.com/RETEMPT/moyu。反馈时请注明版本、设备和复现步骤，避免附带密钥或私人资料。')
      this.action('使用指引', () => this.navigate('guide'))
      this.action('隐私与数据', () => this.navigate('legal'))
    }
  }
  @Builder
  destinationTitle(name: string) {
    Row({ space: 8 }) {
      IconButton({ icon: $r('app.media.ic_back'), label: '返回设置', onAction: () => this.navigate('overview') })
      Text(SettingsCatalog.find(name)?.title || '设置').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
    }.width('100%')
  }
  @Builder
  destination(name: string) {
    NavDestination() {
      if (name === 'ai') {
        ModelSettingsSheet({ embedded: true, closeToken: this.modelCloseToken, onClose: () => this.applyNavigation() })
      } else {
        Scroll() {
          Column({ space: 18 }) { this.detail(name) }
            .width('100%').constraintSize({ maxWidth: 760 }).padding(this.phone ? 16 : 24).alignItems(HorizontalAlign.Start)
        }.width('100%').height('100%').scrollBar(BarState.Auto)
      }
    }.title(this.destinationTitle(name)).hideBackButton(true).backgroundColor(this.palette().canvas)
      .onBackPressed(() => { this.navigate('overview'); return true; })
  }
  build() {
    Navigation(this.paths) { this.directory() }
      .hideTitleBar(true).navDestination(this.destination).mode(this.section === 'overview' ? NavigationMode.Stack : NavigationMode.Auto)
      .navBarWidth(280).navBarWidthRange([240, 320]).minContentWidth(440)
      .width('100%').height('100%').backgroundColor(this.palette().canvas)
  }
}
