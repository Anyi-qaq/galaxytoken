import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { registerBuiltinSources } from '../sources/Bootstrap';
import { Log } from '../common/Logger';

/**
 * 应用入口。
 *
 * 启动时完成一次全局初始化：
 * - 注册全部内置来源（适配器 + 描述符 + 窗口支持矩阵）；
 * - preferences 与 Asset Store 的首次访问在页面层按需初始化。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Log.i('Ability onCreate');
    try {
      registerBuiltinSources();
      Log.i('sources registered');
    } catch (error) {
      Log.e(`register sources failed: ${error}`);
    }
  }

  onDestroy(): void {
    Log.i('Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    Log.i('Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        Log.e(`Failed to load the content. Cause: ${JSON.stringify(err)}`);
        return;
      }
      Log.i('Succeeded in loading the content.');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (err) {
      Log.e(`Failed to set colorMode. Cause: ${err}`);
    }
  }

  onWindowStageDestroy(): void {
    Log.i('Ability onWindowStageDestroy');
  }

  onForeground(): void {
    Log.i('Ability onForeground');
  }

  onBackground(): void {
    Log.i('Ability onBackground');
  }
}
