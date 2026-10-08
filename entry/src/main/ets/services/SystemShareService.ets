import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { fileIo, fileUri } from '@kit.CoreFileKit';

/** Opens the OS chooser; show() completion means the panel opened, not delivery. */
export class SystemShareService {
  private static controller: systemShare.ShareController | null = null;

  static async shareText(context: common.UIAbilityContext, title: string, text: string): Promise<void> {
    if (text.trim().length === 0) { throw new Error('先写入文字再分享'); }
    // Conservative UTF-16 limit keeps worst-case UTF-8 content below the 200KB IPC budget.
    if (text.length > 48 * 1024) { throw new Error('文字较长，请导出文件后分享'); }
    const data = new systemShare.SharedData({ utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      content: text, title: title.substring(0, 120) });
    await SystemShareService.open(context, data);
  }

  static async sharePdf(context: common.UIAbilityContext, title: string, source: string): Promise<void> {
    if (!source.startsWith(context.filesDir + '/') || source.includes('/../') || source.includes('/./') ||
      !source.toLowerCase().endsWith('.pdf') || !await fileIo.access(source)) {
      throw new Error('原 PDF 不可用，请重新导入');
    }
    const data = new systemShare.SharedData({ utd: uniformTypeDescriptor.UniformDataType.PDF,
      uri: fileUri.getUriFromPath(source), title: title.substring(0, 120), description: '原 PDF，不包含应用内笔迹' });
    await SystemShareService.open(context, data);
  }

  private static async open(context: common.UIAbilityContext, data: systemShare.SharedData): Promise<void> {
    if (!canIUse('SystemCapability.Collaboration.SystemShare')) { throw new Error('当前设备不支持系统分享，请使用导出'); }
    SystemShareService.controller = new systemShare.ShareController(data);
    await SystemShareService.controller.show(context, { selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL });
  }
}
