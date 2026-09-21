/**
 * 华为风 AI 分屏伴读面板 (HuaweiAiSplitPanel)
 *
 * 对标实拍图右半侧：
 *   1. 顶栏：分屏把手 (···)、模型切换器 (Flash 扩展 ▾)、画笔联动、清除与更多
 *   2. 结构化题解与数理推导卡片（支持公式块、分条解析、核心结论）
 *   3. 底部 Gemini 风格追问交互栏（+ 问问 Gemini、语音按键、发送）
 */
import { curves } from '@kit.ArkUI';
import { ColorPalette, TypographyTokens, LayoutTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { NoteItem } from '../../../common/types/NoteItem';

interface AiMessage {
  id: string;
  sender: 'user' | 'gemini';
  title?: string;
  text: string;
  formula?: string;
  bullets?: string[];
  time: string;
}

@Component
export struct HuaweiAiSplitPanel {
  @Require @Prop note: NoteItem;
  onClose: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  @State currentModel: string = 'Flash 扩展';
  @State inputQuestion: string = '';
  @State messages: AiMessage[] = [
    {
      id: 'msg-seed-1',
      sender: 'gemini',
      title: '1. 数学推导：反平方单调递减',
      text: '在同心球对称结构中，取半径为 r (r₁ ≤ r ≤ r₂) 的同心球面作为高斯面。根据电介质中的高斯定理：',
      formula: '∮_S D · dS = D(r) · 4πr² = q  ⟹  E(r) = q / (4πεr²)',
      bullets: [
        '在介质填充的区间 r ∈ [r₁, r₂] 内，电场强度 E(r) 与半径平方 r² 成反比。随着 r 增大，E(r) 是严格单调递减的函数。',
        '最大场强：位于半径最小的内边界，即内球表面 r = r₁ 处；',
        '最小场强：位于半径最大的外边界，即外球内壁 r = r₂ 处。'
      ],
      time: '刚刚'
    },
    {
      id: 'msg-seed-2',
      sender: 'gemini',
      title: '2. 物理图像：电力线发散与空间稀释',
      text: '电场强度的物理本质对应着电力线的空间密度（即穿过垂直单位面积的电力线根数）：',
      bullets: [
        '从内球表面发出的总电力线根数取决于内球所带自由电荷量 q。',
        '所有电力线沿径向呈三维球对称向外发散，穿过半径为 r 的球面，其球面总面积为 S(r) = 4πr²。',
        '半径越小，球面积越小，相同数量的电力线被“压缩”在极狭小的空间内，电力线密度最高；随着向外延伸，球面随 r² 剧烈扩张，电力线迅速被稀释。',
        '因为内球表面面积 4πr₁² 是整个介质空间中最小的几何界面，所以那里的电力线最为密集，场强最高。'
      ],
      time: '刚刚'
    }
  ];

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private sendQuestion(): void {
    const q = this.inputQuestion.trim();
    if (q.length === 0) {
      return;
    }
    const userMsg: AiMessage = {
      id: `user-${Date.now()}`,
      sender: 'user',
      text: q,
      time: '刚刚'
    };
    this.messages = this.messages.concat([userMsg]);
    this.inputQuestion = '';

    // 智能模拟针对试卷/文档的解析响应
    setTimeout(() => {
      const replyMsg: AiMessage = {
        id: `gemini-${Date.now()}`,
        sender: 'gemini',
        title: `针对「${q}」的解析与推导`,
        text: `根据当前文档《${this.note.title}》的上下文线索：`,
        bullets: [
          '考点定位：对应试卷第四题介质球层电容与击穿临界场强计算。',
          '推导要点：利用积分 V = ∫[r₁→r₂] E(r) dr 计算极板电势差，并代入临界击穿条件 E₁ ≤ E_b。',
          '易错提醒：注意介质球壳厚度内外半径比值 r₂/r₁ 的极值求导条件。'
        ],
        time: '刚刚'
      };
      this.messages = this.messages.concat([replyMsg]);
    }, 400);
  }

  build() {
    Column() {
      // ---- 顶部把手与模型切换栏 (对标截图) ----
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

        // 模型选择器：Flash 扩展 ∨
        Row({ space: 4 }) {
          Text('＝')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().accent)
          Text(this.currentModel)
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary)
          Text('▾')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
        }
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(6)
        .backgroundColor(this.palette().surfaceSubtle)
        .onClick(() => {
          this.currentModel = this.currentModel === 'Flash 扩展' ? 'Pro 深度推导' : 'Flash 扩展';
        })

        Blank()

        // 右侧小工具：画笔、清空、关闭
        Row({ space: 6 }) {
          Text('✎')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .width(26)
            .height(26)
            .textAlign(TextAlign.Center)
            .borderRadius(4)
            .hoverEffect(HoverEffect.Highlight)

          Text('···')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .width(26)
            .height(26)
            .textAlign(TextAlign.Center)
            .borderRadius(4)
            .hoverEffect(HoverEffect.Highlight)

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

      // ---- 伴读内容流 (对标实拍图排版) ----
      Scroll() {
        Column({ space: 14 }) {
          ForEach(this.messages, (msg: AiMessage) => {
            if (msg.sender === 'user') {
              // 用户提问泡
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
              // Gemini 结构化卡片
              Column({ space: 8 }) {
                if (msg.title && msg.title.length > 0) {
                  Text(msg.title)
                    .fontSize(TypographyTokens.BODY_LARGE)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette().inkPrimary)
                }

                Text(msg.text)
                  .fontSize(TypographyTokens.BODY_REGULAR)
                  .fontColor(this.palette().inkPrimary)
                  .lineHeight(22)

                // 独立公式块 (对标截图积分公式)
                if (msg.formula && msg.formula.length > 0) {
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
                if (msg.bullets && msg.bullets.length > 0) {
                  Column({ space: 6 }) {
                    ForEach(msg.bullets, (b: string) => {
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
                    })
                  }
                  .margin({ top: 4 })
                }
              }
              .width('100%')
              .padding(14)
              .borderRadius(12)
              .backgroundColor(this.palette().surface)
              .border({ width: 1, color: this.palette().borderSubtle })
            }
          }, (msg: AiMessage) => msg.id)
        }
        .padding(14)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)

      // ---- 底部追问输入框 (+ 问问 Gemini) ----
      Row({ space: 8 }) {
        Row({ space: 6 }) {
          Text('＋')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)

          TextInput({ text: this.inputQuestion, placeholder: '问问 Gemini' })
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

        // 语音按钮
        Text('🎙')
          .fontSize(TypographyTokens.BODY_LARGE)
          .fontColor(this.palette().inkSecondary)
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor(this.palette().surfaceSubtle)
          .hoverEffect(HoverEffect.Highlight)

        // 发送按钮
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
}
