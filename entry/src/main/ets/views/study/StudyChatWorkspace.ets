import { AnimationTokens, ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { StudyAssistantGateway, StudyChatMessage, StudyGatewayModel, studyChatContext } from '../../services/study/StudyAssistantGateway';
import { AppIcon } from '../common/AppIcon';
import { DocumentText } from '../common/DocumentText';

export interface StudyChatSession {
  pairingCode: string;
  models: StudyGatewayModel[];
  model: string;
  messages: StudyChatMessage[];
  draft: string;
}

@Component
export struct StudyChatWorkspace {
  @Link session: StudyChatSession;
  onOpenLearning: () => void = () => {};
  onOpenLibrary: () => void = () => {};
  onSave: (title: string, body: string) => Promise<boolean> = async () => false;
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'mono';
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @State private available: boolean = false;
  @State private connecting: boolean = false;
  @State private sending: boolean = false;
  @State private saving: boolean = false;
  @State private code: string = '';
  @State private status: string = '';
  @State private clearArmed: boolean = false;
  @State private showModels: boolean = false;
  private alive: boolean = false;
  private generation: number = 0;
  private gateway: StudyAssistantGateway = new StudyAssistantGateway();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.alive = true;
    StudyAssistantGateway.enabled().then((enabled: boolean) => { if (this.alive) { this.available = enabled; } });
  }

  aboutToDisappear(): void { this.alive = false; this.generation++; this.gateway.cancel(); }

  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark, this.style); }

  private async connect(): Promise<void> {
    if (this.connecting || this.sending) { return; }
    const code = this.code.trim().toLowerCase();
    if (!/^[a-f0-9]{32}$/.test(code)) { this.status = '请输入电脑网关显示的 32 位配对码'; return; }
    this.connecting = true;
    this.status = '正在获取可用模型…';
    const generation = ++this.generation;
    try {
      const models = await this.gateway.models(code);
      if (!this.alive || generation !== this.generation) { return; }
      this.session.pairingCode = code;
      this.session.models = models;
      this.session.model = models[0].id;
      this.code = '';
      this.showModels = models.length > 1;
      this.status = '';
    } catch (error) {
      if (this.alive && generation === this.generation) { this.status = (error as Error).message || '连接失败，请重试'; }
    } finally { if (this.alive && generation === this.generation) { this.connecting = false; } }
  }

  private async send(): Promise<void> {
    const current = this.session;
    const question = current.draft.trim();
    if (this.sending || this.saving || !this.available || !current.model || !question) { return; }
    if (question.length > 1200) { this.status = '问题较长，请缩短后再发送'; return; }
    if (current.messages.length >= 100) { this.status = '本次对话已达 50 轮，可保存为笔记后新建'; return; }
    this.sending = true;
    this.clearArmed = false;
    this.status = '正在等待回复…';
    const generation = ++this.generation;
    try {
      const answer = await this.gateway.chat(studyChatContext(current.messages, question), current.pairingCode, current.model);
      if (!this.alive || generation !== this.generation) { return; }
      const turn: StudyChatMessage[] = [{ role: 'user', content: question }, { role: 'assistant', content: answer }];
      this.session.messages = current.messages.concat(turn);
      this.session.draft = '';
      this.status = '';
      setTimeout(() => { if (this.alive) { this.scroller.scrollEdge(Edge.Bottom); } }, 50);
    } catch (error) {
      if (this.alive && generation === this.generation) { this.status = (error as Error).message || '回复失败，可再次发送'; }
    } finally { if (this.alive && generation === this.generation) { this.sending = false; } }
  }

  private stop(): void {
    this.generation++;
    this.gateway.cancel();
    this.sending = false;
    this.status = '已停止等待，问题仍在输入框中';
  }

  private async save(): Promise<void> {
    if (this.sending || this.saving || !this.session.messages.length) { return; }
    this.saving = true;
    this.clearArmed = false;
    const title = `学习对话 ${new Date().toLocaleDateString('zh-CN')}`;
    const body = '# ' + title + '\n\n' + this.session.messages.map((message: StudyChatMessage) =>
      '## ' + (message.role === 'user' ? '提问' : '回复') + '\n\n' + message.content).join('\n\n');
    try {
      const saved = await this.onSave(title, body);
      if (this.alive) { this.status = saved ? '已保存到资料库' : '保存未完成，可以重试'; }
    } catch { if (this.alive) { this.status = '保存未完成，可以重试'; } }
    finally { if (this.alive) { this.saving = false; } }
  }

  @Builder
  action(label: string, handler: () => void, enabled: boolean = true, primary: boolean = false) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(8)
      .padding({ left: 12, right: 12 }).fontColor(primary ? this.palette().onAccent : this.palette().inkPrimary)
      .backgroundColor(primary ? this.palette().accent : this.palette().surfaceSubtle).enabled(enabled).onClick(handler)
  }

  @Builder
  offline() {
    Column({ space: 12 }) {
      AppIcon({ source: $r('app.media.ic_chat'), iconSize: 28, tint: this.palette().accent })
      Text('学习工作台').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
      Text('导入学习结果，查看对应资料和引用，或创建题卡复习。').fontSize(14).lineHeight(22)
        .fontColor(this.palette().inkSecondary).textAlign(TextAlign.Center)
      Row({ space: 8 }) {
        this.action('打开学习工具', this.onOpenLearning, true, true)
        this.action('浏览资料库', this.onOpenLibrary)
      }
    }.width('100%').padding(20).borderRadius(14).backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().borderSubtle })
  }

  @Builder
  connection() {
    Column({ space: 12 }) {
      Text('连接电脑网关').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
      Text('运行墨语模拟器网关，再输入电脑端显示的配对码。').fontSize(14).lineHeight(22)
        .fontColor(this.palette().inkSecondary).width('100%')
      TextInput({ text: this.code, placeholder: '32 位配对码' }).height(44).width('100%').maxLength(32)
        .type(InputType.Password).enabled(!this.connecting).fontColor(this.palette().inkPrimary)
        .backgroundColor(this.palette().surfaceSubtle).onChange((value: string) => { this.code = value; })
      this.action(this.connecting ? '正在连接…' : '连接网关', () => { this.connect(); }, !this.connecting, true)
    }.width('100%').padding(16).borderRadius(14).backgroundColor(this.palette().surface)
      .alignItems(HorizontalAlign.Start)
  }

  @Builder
  modelPicker() {
    Row({ space: 6 }) {
      this.action('选择模型', () => { this.showModels = !this.showModels; }, !this.sending && !this.saving)
      Text(this.session.models.find((model: StudyGatewayModel) => model.id === this.session.model)?.label || '')
        .fontSize(14).fontColor(this.palette().inkSecondary).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
      this.action('重新配对', () => {
        this.session.model = '';
        this.session.models = [];
        this.session.pairingCode = '';
        this.showModels = false;
        this.status = '';
      }, !this.sending && !this.saving)
    }.width('100%')
    if (this.showModels) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.session.models, (model: StudyGatewayModel) => {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 6 }) {
                AppIcon({ source: model.agent ? $r('app.media.ic_graph') : $r('app.media.ic_cloud'), iconSize: 18,
                  tint: this.palette().accent })
                Text(model.label).fontSize(13).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .constraintSize({ maxWidth: 168 }).fontColor(this.palette().inkPrimary)
              }
            }.height(44).padding({ left: 10, right: 10 }).borderRadius(8).enabled(!this.sending && !this.saving)
              .backgroundColor(this.session.model === model.id ? this.palette().activeBg : this.palette().surfaceSubtle)
              .accessibilityDescription(this.session.model === model.id ? '已选择' : '未选择')
              .onClick(() => { this.session.model = model.id; this.showModels = false; })
          }, (model: StudyGatewayModel) => model.id)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto)
    }
  }

  @Builder
  conversation() {
    if (this.session.model) { this.modelPicker() }
    else { this.connection() }
    List({ space: 10, scroller: this.scroller }) {
      if (this.session.messages.length === 0) {
        ListItem() {
          Column({ space: 8 }) {
            Text('开始对话').fontSize(19).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).width('100%')
            Text('发送时会经电脑网关提交问题和近期对话。要围绕某份资料问答，请在阅读器内打开助手。')
              .fontSize(14).lineHeight(22).fontColor(this.palette().inkSecondary).width('100%')
            this.action('浏览资料库', this.onOpenLibrary)
          }.width('100%').padding(16).alignItems(HorizontalAlign.Start).borderRadius(14).backgroundColor(this.palette().surface)
        }
      }
      ForEach(this.session.messages, (message: StudyChatMessage) => {
        ListItem() {
          Column({ space: 6 }) {
            Text(message.role === 'user' ? '你' : '助手').fontSize(12).fontWeight(FontWeight.Medium)
              .fontColor(this.palette().accent).width('100%')
            DocumentText({ text: message.content, allowLinks: false })
          }.width('100%').padding(14).borderRadius(12)
            .backgroundColor(message.role === 'user' ? this.palette().activeBg : this.palette().surface)
        }
      }, (message: StudyChatMessage, index: number) => `${index}-${message.role}`)
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
    if (this.session.messages.length) {
      Row({ space: 6 }) {
        this.action('保存为笔记', () => { this.save(); }, !this.sending && !this.saving)
        this.action(this.clearArmed ? '确认新建对话' : '新建对话', () => {
          if (this.clearArmed) {
            this.session.messages = [];
            this.clearArmed = false;
            this.status = '';
          } else { this.clearArmed = true; this.status = '确认后清空当前对话。可先保存为笔记。'; }
        }, !this.sending && !this.saving)
        if (this.clearArmed) { this.action('取消', () => { this.clearArmed = false; this.status = ''; }) }
      }.width('100%')
    }
    if (this.session.model) {
      Row({ space: 8 }) {
        TextArea({ text: this.session.draft, placeholder: '输入你的问题' }).height(56).maxLength(1200).layoutWeight(1)
          .fontSize(15).fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle).borderRadius(10)
          .enabled(!this.sending).onChange((value: string) => { this.session.draft = value; })
        if (this.sending) { this.action('停止等待', () => this.stop()) }
        else { this.action('发送', () => { this.send(); }, this.session.draft.trim().length > 0 && !this.saving, true) }
      }.width('100%')
    }
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('助手').fontSize(this.phone ? 27 : 32).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
        if (this.available) { this.action('学习工具', this.onOpenLearning, !this.sending && !this.saving) }
      }.width('100%')
      if (this.available && (this.session.model || this.session.messages.length > 0)) { this.conversation() }
      else {
        Scroll() {
          Column({ space: 12 }) {
            if (this.available) { this.connection() }
            this.offline()
          }.width('100%')
        }.width('100%').layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Auto)
      }
      if (this.status) { Text(this.status).width('100%').fontSize(13).fontColor(this.palette().inkSecondary) }
    }.width('100%').height('100%').constraintSize({ maxWidth: 760 }).padding(this.phone ? 14 : 24)
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_SMOOTH }))
  }
}
