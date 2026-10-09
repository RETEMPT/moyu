import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { AppIcon } from '../common/AppIcon';

interface SetupStep { title: string; detail: string; }

/** In-app schematic, not a screenshot of a provider console. No real credential is shown. */
@Component
export struct ModelSetupGuide {
  onConfigure: () => void = () => {};
  @State provider: string = 'deepseek';
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'ink';
  private palette() { return ThemeHelper.paletteOfDark(this.dark, this.style); }
  private steps(): SetupStep[] {
    return [
      { title: '获取自己的 API Key', detail: this.provider === 'deepseek' ? '打开 DeepSeek 开放平台并登录，在 API keys 页面创建并复制密钥。聊天网站账号或会员不等于已开通 API；请在开放平台确认余额和模型权限。' : '登录阿里云百炼控制台，在右上角选地域，进入 API Key 页面。选择所属账号和业务空间后创建并复制密钥；地域、业务空间和模型权限需要匹配。' },
      { title: '在应用中添加配置', detail: '进入“设置 → AI 与模型 → 自配 API”，从服务商模板添加配置。名称便于辨认；协议选择 OpenAI 兼容；填写服务地址、模型 ID 和你刚取得的密钥。' },
      { title: '核对地址与模型', detail: this.provider === 'deepseek' ? '使用下图的对话地址。模型 ID 可用 deepseek-flash，也可按官方文档选择账号可调用的其他模型；不要填写网页产品名称。' : '下图示例为北京地域兼容接口。其他地域请从官方文档取得对应地址，不能把不同地域的密钥、地址和模型混用。模型 ID 按控制台可调用列表填写。' },
      { title: '授权、测试、保存', detail: '确认服务地址和发送范围，勾选数据发送授权，再点击“测试连接”。测试会向该地址发送测试请求；成功后保存配置并选用自配 API。修改服务地址或协议后需要重新授权。' },
      { title: '从一份资料开始', detail: '回到墨客，选择模型，点加号 → 引用库内资料，输入关键词选取文件，再选择讲解或自测任务。PDF 先提取并校对文字；未配置时仍可使用本地搜索、原文摘录、待办提取和图片识别。' }
    ];
  }
  private async openOfficial(url: string): Promise<void> {
    try { await (getContext(this) as common.UIAbilityContext).startAbility({ action: 'ohos.want.action.viewData', uri: url }); }
    catch { promptAction.showToast({ message: '无法打开浏览器，请稍后重试' }); }
  }
  @Builder
  fieldExample(label: string, value: string) {
    Column({ space: 4 }) {
      Text(label).fontSize(11).fontColor(this.palette().inkMuted).width('100%')
      Text(value).fontSize(13).fontColor(this.palette().inkPrimary).width('100%').wordBreak(WordBreak.BREAK_ALL)
    }.width('100%').padding(10).borderRadius(8).backgroundColor(this.palette().surfaceSubtle)
  }
  build() {
    Column({ space: 14 }) {
      Text('API 接入图解').fontSize(18).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).width('100%')
      Row({ space: 8 }) {
        Button('DeepSeek').height(44).layoutWeight(1).backgroundColor(this.provider === 'deepseek' ? this.palette().accentSoft : this.palette().surfaceSubtle)
          .fontColor(this.palette().inkPrimary).onClick(() => { this.provider = 'deepseek'; })
        Button('Qwen · 阿里云百炼').height(44).layoutWeight(1).backgroundColor(this.provider === 'qwen' ? this.palette().accentSoft : this.palette().surfaceSubtle)
          .fontColor(this.palette().inkPrimary).onClick(() => { this.provider = 'qwen'; })
      }.width('100%')
      ForEach(this.steps(), (step: SetupStep, index: number) => {
        Row({ space: 12 }) {
          Text(`${index + 1}`).width(28).height(28).textAlign(TextAlign.Center).borderRadius(14)
            .fontColor(this.palette().accent).backgroundColor(this.palette().accentSoft)
          Column({ space: 6 }) {
            Text(step.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
            Text(step.detail).fontSize(14).lineHeight(22).fontColor(this.palette().inkSecondary).width('100%')
          }.layoutWeight(1)
        }.width('100%').alignItems(VerticalAlign.Top)
      }, (step: SetupStep) => `${this.provider}-${step.title}`)
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          AppIcon({ source: $r('app.media.ic_settings'), tint: this.palette().accent })
          Text('配置示意 · 请填写自己的密钥').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
        }.width('100%')
        this.fieldExample('① 协议', 'OpenAI 兼容')
        this.fieldExample('② 服务地址（完整对话地址示例）', this.provider === 'deepseek' ? 'https://api.deepseek.com/chat/completions' : 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions')
        this.fieldExample('③ 模型 ID', this.provider === 'deepseek' ? 'deepseek-flash' : '填写控制台可调用的模型 ID')
        this.fieldExample('④ API Key', '••••••••（你在服务商控制台创建的密钥）')
        Text('⑤ 发送授权 → 测试连接 → 保存 → 选用模型').fontSize(13).fontColor(this.palette().accent).width('100%')
      }.width('100%').padding(14).borderRadius(12).backgroundColor(this.palette().surface).border({ width: 1, color: this.palette().border })
      Text('服务地址可填写完整对话地址；兼容根地址会由应用补上 /chat/completions。不要重复追加路径。密钥由系统加密保存，不写入笔记或资料备份；不要共享密钥截图。自配 API 的用量和费用由你与服务商结算。')
        .fontSize(13).lineHeight(21).fontColor(this.palette().inkSecondary).width('100%')
      Button('打开官方密钥获取教程').height(44).width('100%').fontColor(this.palette().accent).backgroundColor(this.palette().accentSoft)
        .onClick(() => this.openOfficial(this.provider === 'deepseek' ? 'https://platform.deepseek.com/api_keys' : 'https://help.aliyun.com/zh/model-studio/get-api-key'))
      Button('打开官方首次调用说明').height(44).width('100%').fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
        .onClick(() => this.openOfficial(this.provider === 'deepseek' ? 'https://api-docs.deepseek.com/zh-cn/' : 'https://help.aliyun.com/zh/model-studio/first-api-call-to-qwen'))
      Text('连接失败时').fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
      Text('401 / 403：检查密钥、账号和模型权限；404：检查服务路径和模型 ID；429：检查余额、配额或稍后重试。网络失败先确认网络和 HTTPS 地址。切换地址后重新授权，必要时关闭流式输出再测试。')
        .fontSize(14).lineHeight(22).fontColor(this.palette().inkSecondary).width('100%')
      Button('前往 AI 与模型').height(44).width('100%').fontColor(this.palette().onAccent).backgroundColor(this.palette().accent).onClick(this.onConfigure)
    }.width('100%')
  }
}
