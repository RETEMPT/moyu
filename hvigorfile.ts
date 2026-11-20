import { appTasks, OhosHapContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { hvigor, HvigorNode } from '@ohos/hvigor';

hvigor.nodesEvaluated(() => {
  if (hvigor.getParameter().getExtParam('moyuStudyDemo') !== 'true') { return; }
  hvigor.getRootNode().subNodes((node: HvigorNode) => {
    const hap = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext | undefined;
    if (!hap) { return; }
    const options = hap.getModuleJsonOpt();
    if (options.module.name !== 'entry') { return; }
    if (hap.getBuildMode() !== 'debug') { throw new Error('模拟器学习助手只允许 Debug 构建。'); }
    const permissions = options.module.requestPermissions || [];
    if (!permissions.some(permission => permission.name === 'ohos.permission.INTERNET')) {
      options.module.requestPermissions = permissions.concat([{ name: 'ohos.permission.INTERNET' }]);
      hap.setModuleJsonOpt(options);
    }
  });
});

export default {
  system: appTasks, /* Built-in plugin of Hvigor. It cannot be modified. */
  plugins: []       /* Custom plugin to extend the functionality of Hvigor. */
}
