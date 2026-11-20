import { AnimationTokens, ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { StudyAssistantGateway, StudyChatMessage, StudyGatewayModel, StudyGatewaySelection, studyChatContext } from '../../services/study/StudyAssistantGateway';
import { AppIcon } from '../common/AppIcon';
import { DocumentText } from '../common/DocumentText';
import { IconButton } from '../common/IconButton';

interface StudyConversation {
  id: string;
  messages: StudyChatMessage[];
  draft: string;
}

export interface StudyChatSession extends StudyGatewaySelection {
  conversation: StudyConversation;
  history: StudyConversation[];
}

export function withStudyGatewaySelection(session: StudyChatSession, selection: StudyGatewaySelection): StudyChatSession {
  return { pairingCode: selection.pairingCode, models: selection.models, model: selection.model,
    conversation: session.conversation, history: session.history };
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
  @StorageProp('flowmindStudyPreview') studyPreview: boolean = false;
  @State private available: boolean = false;
  @State private connecting: boolean = false;
  @State private sending: boolean = false;
  @State private saving: boolean = false;
  @State private code: string = '';
  @State private status: string = '';
  @State private pendingQuestion: string = '';
  @State private showConnection: boolean = false;
  @State private showHistory: boolean = false;
  private alive: boolean = false;
  private generation: number = 0;
  private gateway: StudyAssistantGateway = new StudyAssistantGateway();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.alive = true;
    if (this.studyPreview) {
      StudyAssistantGateway.enabled().then((enabled: boolean) => { if (this.alive) { this.available = enabled; } });
    }
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.generation++;
    this.gateway.cancel();
    if (this.pendingQuestion) { this.setDraft(this.pendingQuestion); }
  }

  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark, this.style); }

  private replaceConversation(conversation: StudyConversation, history: StudyConversation[] = this.session.history): void {
    const session = this.session;
    this.session = { pairingCode: session.pairingCode, models: session.models, model: session.model, conversation, history };
  }

  private setDraft(draft: string): void {
    const current = this.session.conversation;
    this.replaceConversation({ id: current.id, messages: current.messages, draft });
  }

  private title(conversation: StudyConversation): string {
    return (conversation.messages[0]?.content || conversation.draft).trim().replace(/\s+/g, ' ').slice(0, 36) || '新对话';
  }

  private moveTo(conversation: StudyConversation): void {
    if (this.sending || this.saving || this.connecting) { return; }
    let current = this.session.conversation;
    if (this.pendingQuestion) { current = { id: current.id, messages: current.messages, draft: this.pendingQuestion }; }
    const history = this.session.history.filter((item: StudyConversation) => item.id !== conversation.id);
    if (current.id !== conversation.id && (current.messages.length || current.draft.trim())) { history.unshift(current); }
    this.replaceConversation(conversation, history);
    this.pendingQuestion = '';
    this.status = '';
    this.showHistory = false;
    this.scrollBottom();
  }

  private newConversation(): void {
    this.moveTo({ id: 'chat-' + Date.now() + '-' + Math.floor(Math.random() * 1000000), messages: [], draft: '' });
  }

  private scrollBottom(): void {
    setTimeout(() => { if (this.alive) { this.scroller.scrollEdge(Edge.Bottom); } }, 50);
  }

  private async connect(): Promise<void> {
    if (!this.available || this.connecting || this.sending) { return; }
    const code = this.code.trim().toLowerCase();
    if (!/^[a-f0-9]{32}$/.test(code)) { this.status = '请输入电脑网关显示的 32 位配对码'; return; }
    this.connecting = true;
    this.status = '';
    const generation = ++this.generation;
    try {
      const models = await this.gateway.models(code);
      if (!this.alive || generation !== this.generation) { return; }
      const model = models.some((item: StudyGatewayModel) => item.id === this.session.model) ? this.session.model : models[0].id;
      this.session = withStudyGatewaySelection(this.session, { pairingCode: code, models, model });
      this.code = '';
      this.showConnection = false;
    } catch (error) {
      if (this.alive && generation === this.generation) { this.status = (error as Error).message || '连接失败，请重试'; }
    } finally {
      if (this.alive && generation === this.generation) { this.connecting = false; }
    }
  }

  private async send(): Promise<void> {
    const current = this.session.conversation;
    const question = this.pendingQuestion || current.draft.trim();
    if (this.sending || this.saving || this.connecting || !this.available || !question) { return; }
    if (!this.session.model) { this.showConnection = true; return; }
    if (question.length > 1200) { this.status = '问题较长，请缩短后再发送'; return; }
    if (current.messages.length >= 100) { this.status = '本次对话已达 50 轮，可以新建对话'; return; }
    this.sending = true;
    this.status = '';
    this.pendingQuestion = question;
    this.setDraft('');
    this.scrollBottom();
    const generation = ++this.generation;
    try {
      const answer = await this.gateway.chat(studyChatContext(current.messages, question), this.session.pairingCode, this.session.model);
      if (!this.alive || generation !== this.generation) { return; }
      const turn: StudyChatMessage[] = [{ role: 'user', content: question }, { role: 'assistant', content: answer }];
      this.replaceConversation({ id: current.id, draft: '', messages: current.messages.concat(turn) });
      this.pendingQuestion = '';
      this.scrollBottom();
    } catch (error) {
      if (this.alive && generation === this.generation) {
        this.status = (error as Error).message || '回复失败，可重试或修改问题';
        this.scrollBottom();
      }
    } finally {
      if (this.alive && generation === this.generation) { this.sending = false; }
    }
  }

  private restoreQuestion(): void {
    this.setDraft(this.pendingQuestion);
    this.pendingQuestion = '';
    this.status = '';
  }

  private stop(): void {
    this.generation++;
    this.gateway.cancel();
    this.sending = false;
    this.restoreQuestion();
    this.status = '已停止等待，问题已放回输入框';
  }

  private async save(): Promise<void> {
    const conversation = this.session.conversation;
    if (this.sending || this.saving || !conversation.messages.length) { return; }
    this.saving = true;
    const title = this.title(conversation);
    const body = '# ' + title + '\n\n' + conversation.messages.map((message: StudyChatMessage) =>
      '## ' + (message.role === 'user' ? '提问' : '墨客') + '\n\n' + message.content).join('\n\n');
    try {
      const saved = await this.onSave(title, body);
      if (this.alive) { this.status = saved ? '已保存到资料库' : '保存未完成，可以重试'; }
    } catch { if (this.alive) { this.status = '保存未完成，可以重试'; } }
    finally { if (this.alive) { this.saving = false; } }
  }

  @Builder
  action(label: string, handler: () => void, enabled: boolean = true, primary: boolean = false) {
    Button(label, { type: ButtonType.Normal }).height(44).fontSize(13).borderRadius(10)
      .padding({ left: 12, right: 12 }).fontColor(primary ? this.palette().onAccent : this.palette().inkPrimary)
      .backgroundColor(primary ? this.palette().accent : this.palette().surfaceSubtle).enabled(enabled).onClick(handler)
  }

  @Builder
  conversationHeader() {
    Row({ space: 6 }) {
      IconButton({ icon: $r('app.media.ic_menu'), label: this.showHistory ? '收起会话记录' : '会话记录',
        selected: this.showHistory, onAction: () => { this.showHistory = !this.showHistory; } })
      Text(this.title(this.session.conversation)).layoutWeight(1).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(15).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
      IconButton({ icon: $r('app.media.ic_plus'), label: '新建对话', available: !this.sending && !this.saving && !this.connecting,
        onAction: () => this.newConversation() })
      if (this.session.conversation.messages.length) {
        IconButton({ icon: $r('app.media.ic_new_note'), label: '保存对话为笔记', available: !this.sending && !this.saving,
          onAction: () => { this.save(); } })
      }
    }.width('100%').height(52).border({ width: { bottom: 1 }, color: this.palette().borderSubtle })
  }

  @Builder
  conversations() {
    Column({ space: 4 }) {
      Text('本次打开的会话').width('100%').fontSize(13).fontColor(this.palette().inkSecondary).padding({ left: 10, top: 5 })
      if (this.session.history.length === 0) {
        Text('新建对话后，可在这里切回已有会话').width('100%').fontSize(14)
          .fontColor(this.palette().inkSecondary).padding(10)
      } else {
        List({ space: 4 }) {
          ForEach(this.session.history, (conversation: StudyConversation) => {
            ListItem() {
              Button({ type: ButtonType.Normal }) {
                Text(this.title(conversation)).fontSize(14).fontColor(this.palette().inkPrimary).width('100%')
                  .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.height(44).width('100%').padding(10).borderRadius(8).backgroundColor(this.palette().surface)
                .enabled(!this.sending && !this.saving && !this.connecting).onClick(() => this.moveTo(conversation))
            }
          }, (conversation: StudyConversation) => conversation.id)
        }.width('100%').height(Math.min(4, this.session.history.length) * 48).scrollBar(BarState.Auto)
      }
    }.width('100%').padding(8).borderRadius(14).backgroundColor(this.palette().surfaceSubtle)
  }

  @Builder
  connection() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.code, placeholder: '电脑网关的 32 位配对码' }).height(44).layoutWeight(1).maxLength(32)
          .type(InputType.Password).enabled(!this.connecting).fontColor(this.palette().inkPrimary)
          .backgroundColor(this.palette().surface).onChange((value: string) => { this.code = value; })
          .onSubmit(() => { this.connect(); })
        this.action(this.connecting ? '连接中…' : '连接', () => { this.connect(); }, !this.connecting, true)
      }.width('100%')
      if (this.session.models.length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            ForEach(this.session.models, (model: StudyGatewayModel) => {
              this.action(model.label, () => {
                this.session = withStudyGatewaySelection(this.session, {
                  pairingCode: this.session.pairingCode, models: this.session.models, model: model.id
                });
                this.showConnection = false;
              }, !this.connecting, model.id === this.session.model)
            }, (model: StudyGatewayModel) => model.id)
          }
        }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto)
      }
    }.width('100%').padding(10).borderRadius(14).backgroundColor(this.palette().surfaceSubtle)
  }

  @Builder
  welcome() {
    Column({ space: 14 }) {
      Row() {
        AppIcon({ source: $r('app.media.ic_chat'), iconSize: 28, tint: this.palette().accent })
      }.width(58).height(58).borderRadius(18).justifyContent(FlexAlign.Center).backgroundColor(this.palette().accentSoft)
      Text(this.studyPreview ? 'AI 墨客' : '学习工具').fontSize(this.phone ? 28 : 36)
        .fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
      if (this.available) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
          Button('制定复习计划').height(44).margin(3).fontSize(13).fontColor(this.palette().inkPrimary)
            .backgroundColor(this.palette().surfaceSubtle)
            .onClick(() => this.setDraft('帮我制定一周的离散数学复习计划。'))
          Button('讲解一个概念').height(44).margin(3).fontSize(13).fontColor(this.palette().inkPrimary)
            .backgroundColor(this.palette().surfaceSubtle)
            .onClick(() => this.setDraft('用例子讲解等价关系和等价类。'))
        }.width('100%')
      }
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
        Button('打开资料库').height(44).margin(3).fontSize(13).fontColor(this.palette().accent)
          .backgroundColor(this.palette().accentSoft).onClick(this.onOpenLibrary)
        Button(this.studyPreview ? '学习工具' : '复习与学习结果').height(44).margin(3).fontSize(13).fontColor(this.palette().inkSecondary)
          .backgroundColor(this.palette().surfaceSubtle).onClick(this.onOpenLearning)
      }.width('100%')
    }.width('100%').padding({ top: this.phone ? 34 : 64, bottom: 24 })
  }

  @Builder
  message(role: string, content: string) {
    Row() {
      if (role === 'user') {
        Blank()
        Text(content).fontSize(15).lineHeight(23).fontColor(this.palette().inkPrimary)
          .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
          .padding({ left: 15, right: 15, top: 11, bottom: 11 }).borderRadius(16)
          .constraintSize({ maxWidth: this.phone ? '92%' : '80%' }).backgroundColor(this.palette().accentSoft)
      } else {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            AppIcon({ source: $r('app.media.ic_chat'), iconSize: 18, tint: this.palette().accent })
            Text('墨客').fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.palette().accent)
          }.width('100%')
          DocumentText({ text: content, allowLinks: false })
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 2, right: 2, top: 6, bottom: 8 })
      }
    }.width('100%')
  }

  @Builder
  transcript() {
    List({ space: 14, scroller: this.scroller }) {
      if (!this.session.conversation.messages.length && !this.pendingQuestion) {
        ListItem() { this.welcome() }
      }
      ForEach(this.session.conversation.messages, (message: StudyChatMessage) => {
        ListItem() { this.message(message.role, message.content) }
      }, (message: StudyChatMessage, index: number) => `${this.session.conversation.id}-${index}-${message.role}`)
      if (this.pendingQuestion) {
        ListItem() { this.message('user', this.pendingQuestion) }
        ListItem() {
          if (this.sending) {
            Row({ space: 8 }) {
              LoadingProgress().width(22).height(22).color(this.palette().accent)
              Text('墨客正在回复…').fontSize(14).fontColor(this.palette().inkSecondary)
            }.width('100%').height(44)
          } else {
            Column({ space: 6 }) {
              Text(this.status).fontSize(14).fontColor(this.palette().danger).width('100%')
              Row({ space: 6 }) {
                this.action('重试', () => { this.send(); }, !this.connecting)
                this.action('修改问题', () => this.restoreQuestion())
              }.width('100%')
            }.width('100%')
          }
        }
      }
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
  }

  @Builder
  composer() {
    Column({ space: 6 }) {
      if (this.available && this.showConnection) { this.connection() }
      if (this.status && (!this.pendingQuestion || this.showConnection)) {
        Text(this.status).fontSize(13).fontColor(this.palette().inkSecondary).width('100%')
      }
      TextArea({ text: this.session.conversation.draft, placeholder: '问墨客一个问题…' }).height(this.phone ? 56 : 68)
        .maxLength(1200).width('100%').fontSize(16).fontColor(this.palette().inkPrimary)
        .backgroundColor(Color.Transparent).enabled(!this.sending && !this.pendingQuestion)
        .onChange((value: string) => { this.setDraft(value); this.status = ''; })
      Row({ space: 6 }) {
        if (this.available) {
          this.action(this.session.models.find((model: StudyGatewayModel) => model.id === this.session.model)?.label ||
            '连接电脑网关', () => { this.showConnection = !this.showConnection; }, !this.sending && !this.connecting)
        } else {
          Text('联调版开启 StudyDemo 后可连接网关').layoutWeight(1).fontSize(12).fontColor(this.palette().inkSecondary)
        }
        if (this.available) { Blank() }
        if (this.sending) {
          this.action('停止', () => this.stop())
        } else {
          this.action('发送', () => { this.send(); }, this.available && !this.connecting && !this.saving &&
            !this.pendingQuestion && this.session.conversation.draft.trim().length > 0, true)
        }
      }.width('100%')
    }.width('100%').padding(10).borderRadius(18).backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().borderSubtle })
  }

  build() {
    Column({ space: 10 }) {
      if (this.studyPreview) {
        this.conversationHeader()
        if (this.showHistory) { this.conversations() }
        this.transcript()
        this.composer()
      } else {
        this.welcome()
      }
    }.width('100%').height('100%').constraintSize({ maxWidth: 820 })
      .padding({ left: this.phone ? 12 : 24, right: this.phone ? 12 : 24, bottom: this.phone ? 8 : 18 })
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_SMOOTH }))
  }
}
