import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ThemeManager } from '../common/theme/ThemeManager';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 首帧渲染前把用户选定的主题恢复到位：调色板、色彩模式、桌面图标一次同步完，
    // 避免先渲染浅色再闪成深色。
    ThemeManager.restore(this.context, this.context.config.colorMode).catch((error: Error) => {
      hilog.error(DOMAIN, 'Moyu', 'Failed to restore theme. Cause: %{public}s', error.message);
    });
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    // 系统深浅色变化：仅当用户选择「跟随系统」时才需要改变呈现
    ThemeManager.onSystemColorModeChanged(newConfig.colorMode);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'Moyu', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
    });
  }

}
