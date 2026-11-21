/** Compact-width primary navigation. Labels follow the tablet workspace; icons reuse its SVG set. */
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AnimationTokens, ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { AppIcon } from '../common/AppIcon';
import { NAV_HOME, NAV_LIBRARY, NAV_TODO, NAV_FAVORITE, NAV_CHAT } from '../../common/constants/WorkspaceConstants';

interface BottomTabItem {
  icon: Resource;
  label: string;
  navKey: string;
}

@Component
export struct BottomNavBar {
  @Prop activeNav: string = '';
  onSelectNav: (navKey: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @StorageProp('flowmindStudyPreview') studyPreview: boolean = false;
  @State private keyboardVisible: boolean = false;

  private windowInstance: window.Window | undefined = undefined;
  private active: boolean = false;
  private tabs: BottomTabItem[] = [
    { icon: $r('app.media.ic_home'), label: '记录', navKey: NAV_HOME },
    { icon: $r('app.media.ic_folder'), label: '资料', navKey: NAV_LIBRARY },
    { icon: $r('app.media.ic_chat'), label: '墨客', navKey: NAV_CHAT },
    { icon: $r('app.media.ic_check'), label: '待办', navKey: NAV_TODO },
    { icon: $r('app.media.ic_star'), label: '收藏', navKey: NAV_FAVORITE }
  ];

  private onAvoidAreaChange = (options: window.AvoidAreaOptions): void => {
    if (options.type === window.AvoidAreaType.TYPE_KEYBOARD) {
      this.keyboardVisible = options.area.bottomRect.height > 0;
    }
  };

  aboutToAppear(): void {
    this.active = true;
    const context = getContext(this) as common.UIAbilityContext;
    window.getLastWindow(context).then((win: window.Window) => {
      if (!this.active) { return; }
      this.windowInstance = win;
      this.keyboardVisible = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_KEYBOARD).bottomRect.height > 0;
      win.on('avoidAreaChange', this.onAvoidAreaChange);
    }).catch((error: Error) => {
      console.error(`BottomNavBar 获取窗口失败: ${error.message}`);
    });
  }

  aboutToDisappear(): void {
    this.active = false;
    if (this.windowInstance !== undefined) {
      this.windowInstance.off('avoidAreaChange', this.onAvoidAreaChange);
      this.windowInstance = undefined;
    }
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  @Builder
  tabItem(tab: BottomTabItem) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 2 }) {
        AppIcon({ source: tab.icon, iconSize: 20, tint: this.activeNav === tab.navKey ? this.palette().accent : this.palette().inkSecondary })
        Text(tab.navKey === NAV_CHAT && !this.studyPreview ? '学习' : tab.label).fontSize(TypographyTokens.TINY).maxLines(1)
          .fontWeight(this.activeNav === tab.navKey ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.activeNav === tab.navKey ? this.palette().inkPrimary : this.palette().inkSecondary)
      }.width('100%').height('100%').justifyContent(FlexAlign.Center)
    }
    .layoutWeight(1)
    .height(LayoutTokens.BOTTOM_NAV_HEIGHT - 8)
    .padding(0)
    .borderRadius(14)
    .backgroundColor(this.activeNav === tab.navKey ? this.palette().activeBg : Color.Transparent)
    .accessibilityText(tab.navKey === NAV_CHAT && !this.studyPreview ? '学习' : tab.label)
    .accessibilityDescription(this.activeNav === tab.navKey ? '已选中' : '未选中')
    .onClick(() => {
      if (this.activeNav !== tab.navKey) {
        animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_SMOOTH }, () => this.onSelectNav(tab.navKey));
      }
    })
  }

  build() {
    Column() {
      Row({ space: 2 }) {
        ForEach(this.tabs, (tab: BottomTabItem) => { this.tabItem(tab) }, (tab: BottomTabItem) => tab.navKey)
      }.width('100%').height(LayoutTokens.BOTTOM_NAV_HEIGHT).padding(4).borderRadius(19)
        .backgroundColor(this.palette().surface)
        .border({ width: 1, color: this.palette().borderSubtle })
        .shadow({ radius: 12, offsetY: 4, color: this.isDarkMode ? 'rgba(0,0,0,0.30)' : 'rgba(0,0,0,0.10)' })
    }.width('100%').padding({ top: 6, bottom: 8, left: 12, right: 12 }).backgroundColor(this.palette().canvas)
      .visibility(this.keyboardVisible ? Visibility.None : Visibility.Visible)
  }
}
