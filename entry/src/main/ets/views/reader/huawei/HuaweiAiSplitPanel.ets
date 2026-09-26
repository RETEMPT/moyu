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
import { curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ColorPalette, TypographyTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';
import { ModelProfile } from '../../../common/types/ModelConfig';
import { CurrentDocContext, AgentRunContext } from '../../../services/ai/AgentOrchestrator';
import { AgentOrchestrator } from '../../../services/ai/AgentOrchestrator';
import { ModelConfigService, ACTIVE_STORAGE_KEY } from '../../../services/ai/ModelConfigService';
import { StreamHandle } from '../../../services/ai/ModelProvider';
import { ModelSettingsSheet } from '../../settings/ModelSettingsSheet';

interface AiMessage {
  id: string;
  sender: 'user' | 'assistant';
  title: string;
  text: string;
  formula: string;
  bullets: string[];
  error: string;
  streaming: boolean;
}

interface CompanionPrompt {
  label: string;
  query: string;
}

const COMPANION_PROMPTS: CompanionPrompt[] = [
  { label: '讲解这篇文档', query: '请讲解这篇文档的核心内容。' },
  { label: '提取关键结论', query: '这篇文档的关键结论是什么？' },
  { label: '推导每一步', query: '把文档里的推导过程逐步展开。' }
];

/** 按文档 id 记忆的伴读会话（模块级，跨组件实例存活） */
const COMPANION_CACHE: Map<string, AiMessage[]> = new Map();

function emptyCard(id: string, sender: 'user' | 'assistant'): AiMessage {
  return {
    id,
    sender,
    title: '',
    text: '',
    formula: '',
    bullets: [],
    error: '',
    streaming: false
  };
}

@Component
export struct HuaweiAiSplitPanel {
  @Require @Prop note: NoteItem;
  onClose: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp(ACTIVE_STORAGE_KEY) activeProfileId: string = '';

  @State currentModel: string = '未配置模型';
  @State inputQuestion: string = '';
  @State messages: AiMessage[] = [];
  @State streamingCard: AiMessage | null = null;
  @State isLoading: boolean = false;
  @State settingsOpen: boolean = false;

  private orchestrator: AgentOrchestrator = new AgentOrchestrator();
  private streamHandle: StreamHandle | null = null;
  private accumulated: string = '';
  private scroller: Scroller = new Scroller();
  private ready: boolean = false;

  aboutToAppear(): void {
    this.messages = COMPANION_CACHE.get(this.note.id) ?? [];
    this.initModel();
  }

  /** 子组件自行取 Context；Index 已用同一单例完成初始化，取不到也不影响使用 */
  private async initModel(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await ModelConfigService.getInstance().init(ctx);
    } catch (error) {
      console.error(`伴读模型自初始化跳过: ${JSON.stringify(error)}`);
    }
    this.ready = true;
    await this.refreshModelLabel();
  }

  private async refreshModelLabel(): Promise<void> {
    try {
      const profile: ModelProfile = await ModelConfigService.getInstance().getActiveProfile();
      this.currentModel = profile.apiKey.length === 0 ? `${profile.label}（未填密钥）` : profile.label;
    } catch {
      this.currentModel = '未配置模型';
    }
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  private persist(): void {
    COMPANION_CACHE.set(this.note.id, this.messages);
  }

  private clearThread(): void {
    this.cancelStream();
    this.messages = [];
    this.streamingCard = null;
    COMPANION_CACHE.delete(this.note.id);
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
    const doc: CurrentDocContext = {
      title: this.note.title,
      content: this.note.contentDetail ?? '',
      outline: ''
    };
    const ctx: AgentRunContext = {
      query,
      currentDoc: doc,
      history: []
    };

    try {
      await this.orchestrator.run('L1', ctx, (text: string, done: boolean) => {
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
        this.streamHandle = handle;
      });
    } catch (err) {
      this.isLoading = false;
      const failed: AiMessage = emptyCard(`a-${Date.now()}`, 'assistant');
      failed.error = err instanceof Error ? err.message : '请求失败';
      this.streamingCard = null;
      this.messages = [...this.messages, failed];
      this.persist();
    }
  }

  private cancelStream(): void {
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
  }

  /**
   * 把模型返回的 Markdown 解析成卡片结构。
   * 标题取首个 H1/H2，公式取 $$ 或 ```math 围栏，分条取列表项，其余作为正文。
   */
  private parseCard(text: string): AiMessage {
    const card: AiMessage = emptyCard('', 'assistant');
    const lines: string[] = text.split('\n');
    const body: string[] = [];
    const formula: string[] = [];
    let inFence: boolean = false;
    let fenceMath: boolean = false;
    let inDollarMath: boolean = false;

    const flushBody = (): void => {
      const joined: string = body.join('\n').trim();
      if (joined.length > 0) {
        card.text = card.text.length > 0 ? `${card.text}\n\n${joined}` : joined;
      }
      body.length = 0;
    };

    for (const raw of lines) {
      const line: string = raw.trim();

      // $$ 公式块
      if (line.startsWith('$$')) {
        if (inDollarMath) {
          inDollarMath = false;
          const expr: string = formula.join(' ').trim();
          if (expr.length > 0 && card.formula.length === 0) {
            card.formula = expr;
          }
          formula.length = 0;
        } else {
          flushBody();
          inDollarMath = true;
        }
        const rest: string = line.slice(2).replace(/\$\$$/, '').trim();
        if (rest.length > 0) {
          formula.push(rest);
        }
        continue;
      }
      if (inDollarMath) {
        formula.push(line);
        continue;
      }

      // ``` 围栏
      if (line.startsWith('```')) {
        if (inFence) {
          inFence = false;
          if (fenceMath) {
            const expr: string = formula.join('\n').trim();
            if (expr.length > 0 && card.formula.length === 0) {
              card.formula = expr;
            }
            formula.length = 0;
          }
        } else {
          flushBody();
          inFence = true;
          fenceMath = line.toLowerCase().includes('math');
        }
        continue;
      }
      if (inFence) {
        if (fenceMath) {
          formula.push(line);
        } else {
          body.push(raw);
        }
        continue;
      }

      // 标题
      if (line.startsWith('# ') || line.startsWith('## ')) {
        const headingText: string = line.replace(/^#+\s*/, '').trim();
        if (card.title.length === 0) {
          card.title = headingText;
          continue;
        }
        flushBody();
        body.push(headingText);
        continue;
      }

      // 列表项
      if (line.startsWith('- ') || line.startsWith('• ') || line.startsWith('* ')) {
        flushBody();
        card.bullets = [...card.bullets, line.slice(2).trim()];
        continue;
      }
      const ordered: RegExpMatchArray | null = line.match(/^\d+\.\s+(.*)$/);
      if (ordered !== null) {
        flushBody();
        card.bullets = [...card.bullets, ordered[1]];
        continue;
      }

      body.push(raw);
    }

    // 收尾：未闭合的围栏也把内容吐出来，避免流式中途整段消失
    if (inDollarMath || (inFence && fenceMath)) {
      const expr: string = formula.join('\n').trim();
      if (expr.length > 0 && card.formula.length === 0) {
        card.formula = expr;
      }
    } else {
      flushBody();
    }
    if (inFence && !fenceMath) {
      flushBody();
    }
    return card;
  }

  // ------------------------------------------------------------------
  // 渲染
  // ------------------------------------------------------------------

  @Builder
  cardBody(msg: AiMessage) {
    Column({ space: 8 }) {
      if (msg.title.length > 0) {
        Text(msg.title)
          .fontSize(TypographyTokens.BODY_LARGE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
      }

      if (msg.error.length > 0) {
        Text(`⚠ ${msg.error}`)
          .fontSize(TypographyTokens.CAPTION)
          .fontColor('#EF4444')
          .width('100%')
      }

      if (msg.text.length > 0) {
        Text(msg.text)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkPrimary)
          .lineHeight(22)
      }

      // 独立公式块
      if (msg.formula.length > 0) {
        Column() {
          Text(msg.formula)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().accent)
            .fontFamily('monospace')
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width('100%')
        .padding({ top: 10, bottom: 10, left: 12, right: 12 })
        .borderRadius(8)
        .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)')
        .margin({ top: 4, bottom: 4 })
      }

      // 列表条目
      if (msg.bullets.length > 0) {
        Column({ space: 6 }) {
          ForEach(msg.bullets, (b: string, idx: number) => {
            Row({ space: 6 }) {
              Text('○')
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().inkMuted)
                .margin({ top: 3 })
              Text(b)
                .fontSize(TypographyTokens.BODY_REGULAR)
                .fontColor(this.palette().inkSecondary)
                .lineHeight(20)
                .layoutWeight(1)
            }
            .alignItems(VerticalAlign.Top)
            .width('100%')
          }, (b: string, idx: number) => `b-${idx}-${b.length}`)
        }
        .margin({ top: 4 })
      }

      if (msg.streaming) {
        Text('生成中…')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
      }
    }
    .width('100%')
  }

  @Builder
  messageItem(msg: AiMessage) {
    if (msg.sender === 'user') {
      Row() {
        Blank()
        Column() {
          Text(msg.text)
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(Color.White)
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
      Text(`已绑定当前文档《${this.note.title}》，只依据这篇文档作答。`)
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().inkMuted)
        .textAlign(TextAlign.Center)

      Column({ space: 8 }) {
        ForEach(COMPANION_PROMPTS, (p: CompanionPrompt) => {
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
            Text('＝')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().accent)
            Text(this.currentModel)
              .fontSize(TypographyTokens.CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().inkPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('▾')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
          .constraintSize({ maxWidth: 180 })
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(6)
          .backgroundColor(this.palette().surfaceSubtle)
          .onClick(() => {
            this.settingsOpen = true;
          })

          Blank()

          // 右侧小工具：清空、关闭
          Row({ space: 6 }) {
            Text('⌫')
              .fontSize(TypographyTokens.BODY_REGULAR)
              .fontColor(this.palette().inkSecondary)
              .width(26)
              .height(26)
              .textAlign(TextAlign.Center)
              .borderRadius(4)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.clearThread())

            Button('✕')
              .type(ButtonType.Normal)
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkMuted)
              .width(44)
              .height(44)
              .padding(0)
              .borderRadius(22)
              .backgroundColor(this.palette().surfaceSubtle)
              .onClick(() => this.onClose())
          }
        }
        .width('100%')
        .height(42)
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
            Text('＋')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkMuted)

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
            Text('停止')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(Color.White)
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(18)
              .backgroundColor('#EF4444')
              .onClick(() => this.cancelStream())
          } else {
            Text('➤')
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(Color.White)
              .width(36)
              .height(36)
              .textAlign(TextAlign.Center)
              .borderRadius(18)
              .backgroundColor(this.palette().accent)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                this.sendQuestion();
              })
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

      // 模型设置浮层（点顶栏模型名进入）
      if (this.settingsOpen) {
        ModelSettingsSheet({
          onClose: () => {
            animateTo({ curve: curves.springMotion(0.28, 0.72) }, () => {
              this.settingsOpen = false;
            });
            this.refreshModelLabel();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
