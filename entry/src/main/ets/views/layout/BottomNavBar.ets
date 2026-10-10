/** Compact-width primary navigation. Labels follow the tablet workspace; icons reuse its SVG set. */
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NAV_HOME, NAV_LIBRARY, NAV_AI, NAV_TODO, NAV_GRAPH } from '../../common/constants/WorkspaceConstants';

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
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
  @State private keyboardVisible: boolean = false;

  private windowInstance: window.Window | undefined = undefined;
  private active: boolean = false;
  private tabs: BottomTabItem[] = [
    { icon: $r('app.media.ic_home'), label: '首页', navKey: NAV_HOME },
    { icon: $r('app.media.ic_note'), label: '资料', navKey: NAV_LIBRARY },
    { icon: $r('app.media.ic_sparkle'), label: '墨客', navKey: NAV_AI },
    { icon: $r('app.media.ic_check'), label: '待办', navKey: NAV_TODO },
    { icon: $r('app.media.ic_graph'), label: '图谱', navKey: NAV_GRAPH }
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
    Column({ space: 2 }) {
      Image(tab.icon)
        .width(20)
        .height(20)
        .objectFit(ImageFit.Contain)
        .fillColor(this.activeNav === tab.navKey ? this.palette().accent : this.palette().inkSecondary)
      Text(tab.label)
        .fontSize(TypographyTokens.TINY)
        .fontWeight(this.activeNav === tab.navKey ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.activeNav === tab.navKey ? this.palette().accent : this.palette().inkSecondary)
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(LayoutTokens.BOTTOM_NAV_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(10)
    .backgroundColor(this.activeNav === tab.navKey ? this.palette().accentSoft : Color.Transparent)
    .accessibilityText(tab.label)
    .onClick(() => {
      if (this.activeNav !== tab.navKey) { this.onSelectNav(tab.navKey); }
    })
  }

  build() {
    Row({ space: 2 }) {
      ForEach(this.tabs, (tab: BottomTabItem) => {
        this.tabItem(tab)
      }, (tab: BottomTabItem) => tab.navKey)
    }
    .width('100%')
    .height(LayoutTokens.BOTTOM_NAV_HEIGHT)
    .padding({ left: 4, right: 4 })
    .backgroundColor(this.palette().surface)
    .border({ width: { top: 1 }, color: this.palette().borderSubtle })
    .visibility(this.keyboardVisible ? Visibility.None : Visibility.Visible)
  }
}
