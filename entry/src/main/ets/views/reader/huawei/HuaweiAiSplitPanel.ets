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
}

interface CompanionPrompt {
  label: string;
  query: string;
}

const COMPANION_PROMPTS: CompanionPrompt[] = [
  { label: '✦ 解释本页', query: '请对当前文档内容进行通俗且深刻的总结讲解，提取核心结论与论点。' },
  { label: '✦ 提取知识卡', query: '请从当前内容中抽取核心概念、关键定理与关联知识，整理为结构化知识卡片。' },
  { label: '✦ 生成待办与行动', query: '请分析当前文档，梳理需要用户落实的复习待办、实践任务与关键时间节点。' }
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
  onClose: () => void = () => {};
  onOpenModelSettings: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
  @StorageProp(ACTIVE_STORAGE_KEY) @Watch('refreshModelLabel') activeProfileId: string = '';
  @StorageProp(ASSISTANT_MODE_KEY) @Watch('refreshModelLabel') assistantMode: string = 'local';
  @StorageProp('flowmindModelRevision') @Watch('refreshModelLabel') modelRevision: number = 0;

  @State currentModel: string = '本地助手 · 离线';
  @State inputQuestion: string = '';
  @State messages: AiMessage[] = [];
  @State streamingCard: AiMessage | null = null;
  @State isLoading: boolean = false;
  @State clearConfirmBusy: boolean = false;

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

  aboutToDisappear(): void { this.alive = false; this.cancelStream(); }

  onNoteChanged(): void {
    this.cancelStream(); this.accumulated = '';
    this.loadedNoteId = this.note.id;
    this.messages = COMPANION_CACHE.get(this.note.id) ?? [];
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
    this.ready = true;
    await this.refreshModelLabel();
  }

  private async refreshModelLabel(): Promise<void> {
    if (this.assistantMode === 'local' || !REMOTE_AI_ENABLED) { this.currentModel = '本地助手 · 离线'; return; }
    try {
      const profile: ModelProfile = await ModelConfigService.getInstance().getActiveProfile();
      this.currentModel = profile.apiKey.length === 0 ? '自配模型 · 待配置' : profile.label;
    } catch {
      this.currentModel = '未配置模型';
    }
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle);
  }

  private scrollToBottom(): void {
    setTimeout(() => {
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
    if (q.length === 0 || this.isLoading) {
      return;
    }
    if (!this.ready) {
      return;
    }

    const userMsg: AiMessage = emptyCard(`u-${Date.now()}`, 'user');
    userMsg.text = q;
    this.messages = [...this.messages, userMsg];
    this.inputQuestion = '';
    this.isLoading = true;
    this.accumulated = '';
    this.streamingCard = emptyCard(`a-${Date.now()}`, 'assistant');
    this.streamingCard.streaming = true;
    this.scrollToBottom();
    this.runL1(q);
  }

  private async runL1(query: string): Promise<void> {
    const request = ++this.requestId;
    const noteId = this.note.id;
    const current = (): boolean => this.alive && request === this.requestId && noteId === this.note.id;
    const doc: CurrentDocContext = {
      title: this.note.title,
      content: StudySourceService.context(this.note),
      outline: ''
    };
    const ctx: AgentRunContext = {
      query,
      currentDoc: doc,
      history: [],
      isCancelled: () => !current()
    };

    try {
      if (this.assistantMode === 'local' || !REMOTE_AI_ENABLED) {
        await new Promise<void>((resolve) => { setTimeout(resolve, 0); });
        if (!current()) { return; }
        const result = await new LocalAssistantService().answer(query, { notes: [this.note], pinned: [this.note] }, () => !current());
        if (!current()) { return; }
        const card = this.parseCard(result.text); card.id = `a-${Date.now()}`;
        this.messages = [...this.messages, card]; this.streamingCard = null;
        this.persist(); this.scrollToBottom(); return;
      }
      await this.orchestrator.run('L1', ctx, (text: string, done: boolean) => {
        if (!current()) { return; }
        this.accumulated = text;
        const card: AiMessage = this.parseCard(text);
        card.id = this.streamingCard !== null ? this.streamingCard.id : `a-${Date.now()}`;
        card.streaming = !done;
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
      partial.streaming = false;
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
      .padding(14)
      .borderRadius(12)
      .backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().borderSubtle })
    }
  }

  @Builder
  emptyState() {
    Column({ space: 14 }) {
      Text('伴读')
        .fontSize(TypographyTokens.TITLE_SUB)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette().inkPrimary)
      Text(`资料：《${this.note.title}》`)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().inkMuted)
        .textAlign(TextAlign.Center)

      Column({ space: 8 }) {
        ForEach(this.assistantMode === 'local' || !REMOTE_AI_ENABLED ? LOCAL_COMPANION_PROMPTS : COMPANION_PROMPTS, (p: CompanionPrompt) => {
          Text(p.label)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().accent)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .borderRadius(16)
            .backgroundColor(this.palette().accentSoft)
            .onClick(() => {
              this.inputQuestion = p.query;
              this.sendQuestion();
            })
        }, (p: CompanionPrompt) => p.label)
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(20)
  }

  build() {
    Stack() {
      Column() {
        // ---- 顶部把手与模型切换栏 ----
        Row() {
          // 居中分屏小药丸指示器
          Row() {
            Text('···')
              .fontSize(TypographyTokens.BODY_LARGE)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkMuted)
          }
          .width(36)
          .height(18)
          .justifyContent(FlexAlign.Center)

          // 模型选择器：显示当前激活档案，点按进入模型设置
          Row({ space: 4 }) {
            AppIcon({ source: $r('app.media.ic_sparkle'), iconSize: 18, tint: this.palette().accent })
            Text(this.currentModel)
              .fontSize(TypographyTokens.CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().inkPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            AppIcon({ source: $r('app.media.ic_chevron_down'), iconSize: 14, tint: this.palette().inkMuted })
          }
          .constraintSize({ maxWidth: 180 })
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(6)
          .backgroundColor(this.palette().surfaceSubtle)
          .onClick(() => {
            this.onOpenModelSettings();
          })

          Blank()

          // 右侧小工具：清空、关闭
          Row({ space: 6 }) {
            IconButton({ icon: $r('app.media.ic_trash'), label: '清空伴读对话', available: !this.isLoading && !this.clearConfirmBusy && this.messages.length > 0, onAction: () => this.requestClearThread() })
            IconButton({ icon: $r('app.media.ic_close'), label: '关闭伴读', onAction: this.onClose })
          }
        }
        .width('100%')
        .height(52)
        .padding({ left: 12, right: 12 })
        .backgroundColor(this.palette().surface)
        .border({ width: { bottom: 1 }, color: { bottom: this.palette().borderSubtle } })

        // ---- 伴读内容流 ----
        if (this.messages.length === 0 && this.streamingCard === null) {
          this.emptyState()
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
                .padding(14)
                .borderRadius(12)
                .backgroundColor(this.palette().surface)
                .border({ width: 1, color: this.palette().borderSubtle })
              }
            }
            .padding(14)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Auto)
        }

        // ---- 底部追问输入框 ----
        Row({ space: 8 }) {
          Row({ space: 6 }) {
            AppIcon({ source: $r('app.media.ic_note'), iconSize: 18, tint: this.palette().inkMuted })

            TextInput({ text: this.inputQuestion, placeholder: `问《${this.note.title}》` })
              .fontSize(TypographyTokens.BODY_REGULAR)
              .fontColor(this.palette().inkPrimary)
              .placeholderColor(this.palette().inkMuted)
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .height(36)
              .onChange((val: string) => {
                this.inputQuestion = val;
              })
              .onSubmit(() => {
                this.sendQuestion();
              })
          }
          .layoutWeight(1)
          .height(40)
          .padding({ left: 12, right: 8 })
          .borderRadius(20)
          .backgroundColor(this.palette().surfaceSubtle)
          .border({ width: 1, color: this.palette().borderSubtle })

          if (this.isLoading) {
            IconButton({ icon: $r('app.media.ic_stop'), label: '停止生成', destructive: true, onAction: () => this.cancelStream() })
          } else {
            IconButton({ icon: $r('app.media.ic_send'), label: '发送提问', selected: true, available: this.inputQuestion.trim().length > 0 && this.ready,
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
