/**
 * 华为风 AI 分屏伴读面板 (HuaweiAiSplitPanel)
 *
 * 对标实拍图右半侧：
 *   1. 顶栏：分屏把手 (···)、模型切换器、清除与关闭
 *   2. 伴读卡片（标题 / 公式块 / 分条解析），由模型返回的 Markdown 解析而来
 *   3. 底部追问交互栏
 *
 * 数据来源：L1「伴读」Agent，硬绑定当前打开的文档作为唯一依据。
 * 会话按文档 id 记忆在模块级缓存里，切换文档再回来可续上；不写入全局会话列表，
 * 避免把「读这篇文档时的追问」混进 AI 墨客的主对话历史。
 */
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import { CompanionSourcePolicy } from '../../../services/ai/CompanionSourcePolicy';
import { ModelProfilePolicy } from '../../../services/ai/ModelProfilePolicy';
import { RemoteAiPolicy } from '../../../services/ai/RemoteAiPolicy';
import { StoredMessage } from '../../../common/types/ChatSession';
import { StudySourceService } from '../../../services/study/StudySourceService';
import { ModelProfile } from '../../../common/types/ModelConfig';
import { CurrentDocContext, AgentRunContext } from '../../../services/ai/AgentOrchestrator';
import { AgentOrchestrator } from '../../../services/ai/AgentOrchestrator';
import { ModelConfigService, ACTIVE_STORAGE_KEY } from '../../../services/ai/ModelConfigService';
import { StreamHandle } from '../../../services/ai/ModelProvider';
import { AssistantModeService, ASSISTANT_MODE_KEY } from '../../../services/ai/AssistantModeService';
import { LocalAssistantService } from '../../../services/ai/LocalAssistantService';
import { REMOTE_AI_ENABLED } from '../../../common/constants/RuntimeCapabilities';
import { AssistantText } from '../../common/AssistantText';
import { AppIcon } from '../../common/AppIcon';
import { IconButton } from '../../common/IconButton';

interface AiMessage {
  id: string;
  sender: 'user' | 'assistant';
  text: string;
  error: string;
  streaming: boolean;
  scope?: string;
}

interface CompanionPrompt {
  label: string;
  query: string;
}

const COMPANION_PROMPTS: CompanionPrompt[] = [
  { label: '讲解资料', query: '请对当前文档内容进行通俗且深刻的总结讲解，提取核心结论与论点。' },
  { label: '梳理概念', query: '请从当前内容中抽取核心概念、关键定理与关联知识，整理为结构化知识卡片。' },
  { label: '列出复习建议', query: '请分析当前文档，梳理需要用户落实的复习待办、实践任务与关键时间节点。' }
];
const LOCAL_COMPANION_PROMPTS: CompanionPrompt[] = [
  { label: '提取要点', query: '提取要点' },
  { label: '整理待办', query: '整理待办' }
];

/** 按文档 id 记忆的伴读会话（模块级，跨组件实例存活） */
const COMPANION_CACHE: Map<string, AiMessage[]> = new Map();

function emptyCard(id: string, sender: 'user' | 'assistant'): AiMessage {
  return {
    id,
    sender,
    text: '',
    error: '',
    streaming: false
  };
}

@Component
export struct HuaweiAiSplitPanel {
  @Require @Prop @Watch('onNoteChanged') note: NoteItem;
  @Prop @Watch('onPageChanged') currentPage: number = 1;
  @State pageOnly: boolean = true;
  onExtractText: () => void = () => {};
  onClose: () => void = () => {};
  onOpenModelSettings: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
  @StorageProp(ACTIVE_STORAGE_KEY) @Watch('refreshModelLabel') activeProfileId: string = '';
  @StorageProp(ASSISTANT_MODE_KEY) @Watch('refreshModelLabel') assistantMode: string = 'local';
  @StorageProp('flowmindModelRevision') @Watch('refreshModelLabel') modelRevision: number = 0;

  @State currentModel: string = '选择模型';
  @State remoteReady: boolean = false;
  private modelRefreshId: number = 0;
  @State inputQuestion: string = '';
  @State messages: AiMessage[] = [];
  @State streamingCard: AiMessage | null = null;
  @State isLoading: boolean = false;
  @State clearConfirmBusy: boolean = false;
  @State modeSwitchBusy: boolean = false;
  private localPromptId: number = 0;

  private orchestrator: AgentOrchestrator = new AgentOrchestrator();
  private streamHandle: StreamHandle | null = null;
  private accumulated: string = '';
  private scroller: Scroller = new Scroller();
  @State ready: boolean = false;
  private alive: boolean = true;
  private requestId: number = 0;
  private loadedNoteId: string = '';

  aboutToAppear(): void {
    this.alive = true;
    this.loadedNoteId = this.note.id;
    this.messages = COMPANION_CACHE.get(this.note.id) ?? [];
    this.initModel();
  }

  aboutToDisappear(): void { this.alive = false; this.modelRefreshId++; this.localPromptId++; this.cancelStream(); }

  onNoteChanged(): void {
    if (this.loadedNoteId === this.note.id) { return; }
    this.localPromptId++; this.modeSwitchBusy = false;
    this.inputQuestion = ''; this.pageOnly = true;
    this.cancelStream(); this.accumulated = '';
    this.loadedNoteId = this.note.id;
    this.messages = COMPANION_CACHE.get(this.note.id) ?? [];
  }

  onPageChanged(): void {
    this.localPromptId++; this.modeSwitchBusy = false;
    if (this.pageOnly && this.isLoading) { this.cancelStream(); }
  }

  private async prepareLocalPrompt(query: string): Promise<void> {
    if (!this.ready || !this.hasReadableSource() || this.isLoading || this.modeSwitchBusy) { return; }
    const request = ++this.localPromptId;
    const noteId = this.note.id;
    this.modeSwitchBusy = true;
    try {
      await AssistantModeService.getInstance().setMode('local');
      if (!this.alive || request !== this.localPromptId || noteId !== this.note.id || this.isLoading) { return; }
      this.modeSwitchBusy = false;
      this.inputQuestion = query; this.sendQuestion();
    } catch { if (this.alive && request === this.localPromptId) { promptAction.showToast({ message: '助手设置未能保存，请重试' }); } }
    finally { if (this.alive && request === this.localPromptId) { this.modeSwitchBusy = false; } }
  }

  /** 子组件自行取 Context；Index 已用同一单例完成初始化，取不到也不影响使用 */
  private async initModel(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await AssistantModeService.getInstance().init(ctx);
      if (REMOTE_AI_ENABLED) { await ModelConfigService.getInstance().init(ctx); }
    } catch (error) {
      console.error(`伴读模型自初始化跳过: ${JSON.stringify(error)}`);
    }
    if (!this.alive) { return; }
    this.ready = true;
    await this.refreshModelLabel();
  }

  private async refreshModelLabel(): Promise<void> {
    const refresh = ++this.modelRefreshId;
    this.cancelStream(); this.remoteReady = false;
    if (this.assistantMode === 'local' || !REMOTE_AI_ENABLED) { this.currentModel = '选择模型'; return; }
    try {
      const profile: ModelProfile = await ModelConfigService.getInstance().getActiveProfile();
      if (!this.alive || refresh !== this.modelRefreshId) { return; }
      this.remoteReady = !ModelProfilePolicy.validate(profile) && !profile.credentialUnavailable && RemoteAiPolicy.consented(profile);
      this.currentModel = this.remoteReady ? profile.label : '模型待配置 / 授权';
    } catch { if (this.alive && refresh === this.modelRefreshId) { this.currentModel = '选择模型'; } }
  }

  private sourceSnapshot(): NoteItem { return CompanionSourcePolicy.snapshot(this.note, this.currentPage, this.pageOnly); }
  private hasReadableSource(): boolean { return CompanionSourcePolicy.readable(this.sourceSnapshot()); }
  private canAsk(): boolean {
    return this.ready && this.hasReadableSource() && (this.assistantMode === 'local' || !REMOTE_AI_ENABLED || this.remoteReady);
  }
  private scopeLabel(): string {
    if (!CompanionSourcePolicy.binary(this.note)) { return '当前笔记正文'; }
    return this.pageOnly ? `第 ${this.currentPage} 页 · 校对文字` : `已校对文字 · ${StudySourceService.pages(this.note).filter((p) => p.text.trim().length > 0).length} 页`;
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      if (!this.alive) { return; }
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  private persist(): void {
    COMPANION_CACHE.set(this.loadedNoteId, this.messages);
  }

  private clearThread(): void {
    this.cancelStream();
    this.messages = [];
    this.streamingCard = null;
    COMPANION_CACHE.delete(this.note.id);
  }

  private async requestClearThread(): Promise<void> {
    if (this.isLoading || this.clearConfirmBusy || this.messages.length === 0) { return; }
    const noteId = this.loadedNoteId; this.clearConfirmBusy = true;
    try {
      const result = await promptAction.showDialog({ title: '清空伴读对话？', message: '只删除这份资料的伴读消息，删除后无法恢复。',
        buttons: [{ text: '取消', color: this.palette().inkSecondary }, { text: '清空', color: this.palette().danger }] });
      if (result.index === 1 && this.alive && this.loadedNoteId === noteId && !this.isLoading) { this.clearThread(); }
    } catch { /* Dismissal or unavailable dialog leaves messages intact. */ }
    finally { this.clearConfirmBusy = false; }
  }

  private sendQuestion(): void {
    const q: string = this.inputQuestion.trim();
    if (q.length === 0 || this.isLoading || this.modeSwitchBusy) {
      return;
    }
    if (!this.canAsk()) {
      return;
    }

    const userMsg: AiMessage = emptyCard(`u-${Date.now()}`, 'user');
    userMsg.text = q; userMsg.scope = this.scopeLabel();
    this.messages = [...this.messages, userMsg];
    this.inputQuestion = '';
    this.isLoading = true;
    this.accumulated = '';
    this.streamingCard = emptyCard(`a-${Date.now()}`, 'assistant');
    this.streamingCard.streaming = true; this.streamingCard.scope = this.scopeLabel();
    this.scrollToBottom();
    this.runL1(q);
  }

  private async runL1(query: string): Promise<void> {
    const request = ++this.requestId;
    const noteId = this.note.id;
    const current = (): boolean => this.alive && request === this.requestId && noteId === this.note.id;
    const source = this.sourceSnapshot();
    const scope = this.scopeLabel();
    const doc: CurrentDocContext = {
      title: `${source.title} · ${this.scopeLabel()}`,
      content: StudySourceService.context(source),
      outline: ''
    };
    const ctx: AgentRunContext = {
      query,
      currentDoc: doc,
      history: this.messages.slice(0, -1).filter((m: AiMessage) => !m.error && m.text.trim().length > 0).slice(-12).map((m: AiMessage) => {
        const stored: StoredMessage = { id: m.id, role: m.sender, text: m.text, createdAt: 0 }; return stored;
      }),
      isCancelled: () => !current()
    };

    try {
      if (this.assistantMode === 'local' || !REMOTE_AI_ENABLED) {
        await new Promise<void>((resolve) => { setTimeout(resolve, 0); });
        if (!current()) { return; }
        const result = await new LocalAssistantService().answer(query, { notes: [source], pinned: [source] }, () => !current());
        if (!current()) { return; }
        const card = this.parseCard(result.text); card.id = `a-${Date.now()}`; card.scope = scope;
        this.messages = [...this.messages, card]; this.streamingCard = null;
        this.persist(); this.scrollToBottom(); return;
      }
      await this.orchestrator.run('L1', ctx, (text: string, done: boolean) => {
        if (!current()) { return; }
        this.accumulated = text;
        const card: AiMessage = this.parseCard(text);
        card.id = this.streamingCard !== null ? this.streamingCard.id : `a-${Date.now()}`;
        card.streaming = !done; card.scope = scope;
        this.streamingCard = card;
        if (done) {
          this.isLoading = false;
          this.messages = [...this.messages, card];
          this.streamingCard = null;
          this.persist();
          this.scrollToBottom();
        }
      }, (handle: StreamHandle) => {
        if (current()) { this.streamHandle = handle; } else { handle.abort(); }
      });
    } catch (err) {
      if (!current()) { return; }
      this.isLoading = false;
      const failed: AiMessage = this.parseCard(this.accumulated);
      failed.id = `a-${Date.now()}`;
      failed.scope = scope;
      failed.error = err instanceof Error ? err.message : '请求失败';
      this.streamingCard = null;
      this.messages = [...this.messages, failed];
      this.persist();
    } finally { if (current()) { this.isLoading = false; this.streamHandle = null; } }
  }

  private cancelStream(): void {
    this.requestId++;
    if (this.streamHandle !== null) {
      this.streamHandle.abort();
      this.streamHandle = null;
    }
    if (this.isLoading && this.streamingCard !== null && this.accumulated.length > 0) {
      // 保留已产出的部分，避免用户手动停止时白丢一段回复
      const partial: AiMessage = this.parseCard(this.accumulated);
      partial.id = this.streamingCard.id;
      partial.streaming = false; partial.scope = this.streamingCard.scope;
      this.messages = [...this.messages, partial];
      this.persist();
    }
    this.isLoading = false;
    this.streamingCard = null;
    this.accumulated = '';
  }

  /** 保留完整源文，由共用排版器按原顺序显示。 */
  private parseCard(text: string): AiMessage {
    const card = emptyCard('', 'assistant'); card.text = text; return card;
  }

  @Builder
  cardBody(msg: AiMessage) {
    Column({ space: 8 }) {
      if (msg.scope) { Text(msg.scope).fontSize(11).fontColor(this.palette().inkMuted).width('100%') }
      if (msg.error.length > 0) { Text(msg.error).fontSize(13).lineHeight(20).fontColor(this.palette().danger).width('100%') }
      AssistantText({ text: msg.text, streaming: msg.streaming })
    }.width('100%')
  }

  @Builder
  messageItem(msg: AiMessage) {
    if (msg.sender === 'user') {
      Row() {
        Blank()
        Column() {
          Text(msg.text)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().onAccent)
        }
        .padding(10)
        .borderRadius(12)
        .backgroundColor(this.palette().accent)
        .constraintSize({ maxWidth: '85%' })
      }
      .width('100%')
    } else {
      Column({ space: 8 }) {
        this.cardBody(msg)
      }
      .width('100%')
      .padding({ top: 8, bottom: 12 })
    }
  }

  @Builder
  emptyState() {
    Column({ space: 14 }) {
      AppIcon({ source: $r('app.media.ic_sparkle'), iconSize: 30, tint: this.palette().accent })
      Text('一起研读这份资料').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
      Text(this.hasReadableSource() ? '先选任务，再追问细节；请核对原文。' : '当前范围还没有可读文字。先提取并校对，再开始伴读。')
        .fontSize(13).fontColor(this.palette().inkSecondary).lineHeight(21).textAlign(TextAlign.Center)
      if (!this.hasReadableSource() && (this.note.sourceType === 'pdf' || this.note.type.toLowerCase() === 'pdf')) {
        Button('提取本页文字').height(44).fontColor(this.palette().accent).backgroundColor(this.palette().accentSoft).onClick(this.onExtractText)
      }
      Column({ space: 8 }) {
        ForEach(LOCAL_COMPANION_PROMPTS, (p: CompanionPrompt) => {
          Button(p.label).width('100%').height(44).fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
            .enabled(this.ready && this.hasReadableSource() && !this.isLoading && !this.modeSwitchBusy)
            .onClick(() => this.prepareLocalPrompt(p.query))
        }, (p: CompanionPrompt) => p.label)
        ForEach(COMPANION_PROMPTS, (p: CompanionPrompt) => {
          Button(p.label).width('100%').height(44).fontColor(this.remoteReady ? this.palette().accent : this.palette().inkMuted)
            .backgroundColor(this.palette().surfaceSubtle).enabled(this.remoteReady && this.hasReadableSource() && !this.isLoading && !this.modeSwitchBusy)
            .onClick(() => { this.inputQuestion = p.query; this.sendQuestion(); })
        }, (p: CompanionPrompt) => p.label)
      }.width('100%')
      if (!this.remoteReady) {
        Text('讲解和生成建议需选用已配置并授权的模型。').fontSize(12).fontColor(this.palette().inkMuted).textAlign(TextAlign.Center)
      }
    }.width('100%').padding(16).alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack() {
      Column() {
        Row({ space: 4 }) {
          Column({ space: 2 }) {
            Text('伴读').fontSize(16).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
            Text(this.note.title).fontSize(11).fontColor(this.palette().inkMuted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          }.layoutWeight(1)
          IconButton({ icon: $r('app.media.ic_plus'), label: '新建伴读对话', available: !this.isLoading && !this.clearConfirmBusy && this.messages.length > 0, onAction: () => this.requestClearThread() })
          IconButton({ icon: $r('app.media.ic_close'), label: '关闭伴读', onAction: this.onClose })
        }.width('100%').height(56).padding({ left: 12, right: 8 }).backgroundColor(this.palette().surface)
        Row({ space: 6 }) {
          if (CompanionSourcePolicy.binary(this.note)) {
            Button(this.pageOnly ? '本页' : '已校对页').height(44).fontSize(12).fontColor(this.palette().accent)
              .backgroundColor(this.palette().accentSoft).enabled(!this.isLoading).onClick(() => { this.pageOnly = !this.pageOnly; })
          }
          Text(this.scopeLabel()).fontSize(11).fontColor(this.palette().inkMuted).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%').padding({ left: 12, right: 12 }).backgroundColor(this.palette().surface)

        // ---- 伴读内容流 ----
        if (this.messages.length === 0 && this.streamingCard === null) {
          Scroll() { this.emptyState() }.layoutWeight(1).width('100%').scrollBar(BarState.Auto)
        } else {
          Scroll(this.scroller) {
            Column({ space: 14 }) {
              ForEach(this.messages, (msg: AiMessage) => {
                this.messageItem(msg)
              }, (msg: AiMessage) => msg.id)

              if (this.streamingCard !== null) {
                Column({ space: 8 }) {
                  this.cardBody(this.streamingCard)
                }
                .width('100%')
                .padding({ top: 8, bottom: 12 })
              }
            }
            .padding(14)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Auto)
        }

        // ---- 底部追问输入框 ----
        Row() {
          Button(this.currentModel).height(44).fontSize(12).fontColor(this.palette().inkSecondary).backgroundColor(Color.Transparent)
            .onClick(this.onOpenModelSettings)
          Blank()
        }.width('100%').padding({ left: 8, right: 8 }).backgroundColor(this.palette().surface)
        Row({ space: 8 }) {
          Row({ space: 6 }) {
            AppIcon({ source: $r('app.media.ic_note'), iconSize: 18, tint: this.palette().inkMuted })

            TextInput({ text: this.inputQuestion, placeholder: `问《${this.note.title}》` })
              .fontSize(TypographyTokens.BODY_REGULAR)
              .fontColor(this.palette().inkPrimary)
              .placeholderColor(this.palette().inkMuted)
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .height(44)
              .onChange((val: string) => {
                this.inputQuestion = val;
              })
              .onSubmit(() => {
                this.sendQuestion();
              })
          }
          .layoutWeight(1)
          .height(44)
          .padding({ left: 12, right: 8 })
          .borderRadius(20)
          .backgroundColor(this.palette().surfaceSubtle)
          .border({ width: 1, color: this.palette().borderSubtle })

          if (this.isLoading) {
            IconButton({ icon: $r('app.media.ic_stop'), label: '停止生成', destructive: true, onAction: () => this.cancelStream() })
          } else {
            IconButton({ icon: $r('app.media.ic_send'), label: '发送提问', selected: true, available: this.inputQuestion.trim().length > 0 && this.canAsk(),
              onAction: () => this.sendQuestion() })
          }
        }
        .width('100%')
        .height(56)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.palette().surface)
        .border({ width: { top: 1 }, color: { top: this.palette().borderSubtle } })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.palette().canvas)

    }
    .width('100%')
    .height('100%')
  }
}
