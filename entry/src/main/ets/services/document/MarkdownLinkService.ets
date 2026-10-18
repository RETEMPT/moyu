import { common } from '@kit.AbilityKit';

/** External URLs open only after an explicit tap; preview never fetches resources. */
export class MarkdownLinkService {
  static async open(context: common.UIAbilityContext, target: string): Promise<void> {
    if (!/^https?:\/\/[^\s<>]+$/i.test(target)) { throw new Error('仅支持打开 HTTP 或 HTTPS 网页链接'); }
    await context.openLink(target, { appLinkingOnly: false });
  }
}
