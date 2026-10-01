/**
 * 手机端底部 Tab 导航栏（仅 <840vp 单栏模式显示）
 *
 * 镜像侧栏的主要导航入口，绑定 Index.activeNav，小屏下用拇指可达的
 * 底部栏替代占屏 72% 的抽屉。次要入口（白板/收藏/回收站/设置）仍留在
 * 由顶栏汉堡唤起的抽屉里。图标沿用工程既有的单色几何字符风格，不引入图片资源。
 */
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NAV_HOME, NAV_LIBRARY, NAV_AI, NAV_TODO, NAV_GRAPH } from '../../common/constants/WorkspaceConstants';

interface BottomTabItem {
  icon: string;
  label: string;
  navKey: string;
}

@Component
export struct BottomNavBar {
  @Prop activeNav: string = '';
  onSelectNav: (navKey: string) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  // 键盘弹出时整条 Tab 栏退出布局（Visibility.None），避免浮在键盘上方
  // 与阅读器的贴键盘格式工具栏叠罗汉；键盘收起后自动恢复。
  // 用 Window avoidAreaChange（API 9+）监听键盘区域，低版本 SDK 没有 UIContext.on。
  @State keyboardVisible: boolean = false;

  private windowInstance: window.Window | undefined = undefined;

  private onAvoidAreaChange = (options: window.AvoidAreaOptions): void => {
    if (options.type === window.AvoidAreaType.TYPE_KEYBOARD) {
      this.keyboardVisible = options.area.bottomRect.height > 0;
    }
  };

  aboutToAppear(): void {
    const context = getContext(this) as common.UIAbilityContext;
    window.getLastWindow(context).then((win: window.Window) => {
      this.windowInstance = win;
      win.on('avoidAreaChange', this.onAvoidAreaChange);
    }).catch((error: Error) => {
      console.error(`BottomNavBar 获取窗口失败: ${error.message}`);
    });
  }

  aboutToDisappear(): void {
    if (this.windowInstance !== undefined) {
      this.windowInstance.off('avoidAreaChange', this.onAvoidAreaChange);
      this.windowInstance = undefined;
    }
  }

  private tabs: BottomTabItem[] = [
    { icon: '⌂', label: '首页', navKey: NAV_HOME },
    { icon: '▤', label: '资料', navKey: NAV_LIBRARY },
    { icon: '✦', label: 'AI墨客', navKey: NAV_AI },
    { icon: '☑', label: '待办', navKey: NAV_TODO },
    { icon: '◍', label: '图谱', navKey: NAV_GRAPH }
  ];

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  @Builder
  tabItem(tab: BottomTabItem) {
    Column() {
      Text(tab.icon)
        .fontSize(20)
        .lineHeight(22)
        .fontColor(this.activeNav === tab.navKey ? this.palette().accent : this.palette().inkSecondary)
      Text(tab.label)
        .fontSize(TypographyTokens.TINY)
        .margin({ top: 2 })
        .fontColor(this.activeNav === tab.navKey ? this.palette().accent : this.palette().inkSecondary)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.activeNav !== tab.navKey) {
        this.onSelectNav(tab.navKey);
      }
    })
  }

  build() {
    Row() {
      ForEach(this.tabs, (tab: BottomTabItem) => {
        this.tabItem(tab)
      }, (tab: BottomTabItem) => tab.navKey)
    }
    .width('100%')
    .height(LayoutTokens.BOTTOM_NAV_HEIGHT)
    .backgroundColor(this.palette().surface)
    .border({ width: { top: 0.5 }, color: this.palette().borderSubtle })
    .visibility(this.keyboardVisible ? Visibility.None : Visibility.Visible)
  }
}
