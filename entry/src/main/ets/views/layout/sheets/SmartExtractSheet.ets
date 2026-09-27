/**
 * 智能信息提取与落地弹层 (SmartExtractSheet)
 *
 * FlowMind 黄金闭环核心交互：
 * 碎片信息 / 通知 / OCR 文本输入
 *   ↓
 * AI 结构化语义理解 (SmartExtractService)
 *   ↓
 * 结构化展示 (核心摘要、实体、待办事项、双链拓扑)
 *   ↓
 * 一键确认生成：
 *   1. 自动注入待办日历 (TodoStorageService)
 *   2. 自动生成双链知识卡 (NoteStorageService) 并导航打开
 */
import { curves } from '@kit.ArkUI';
import { picker } from '@kit.CoreFileKit';
import { ColorPalette, TypographyTokens, AnimationTokens } from '../../../common/constants/DesignTokens';
import { ThemeHelper } from '../../../common/theme/ThemeHelper';
import { SmartContent } from '../../../common/types/SmartContent';
import { SmartTask } from '../../../common/types/SmartTask';
import { SmartRelation } from '../../../common/types/SmartRelation';
import { SmartExtractService } from '../../../services/smart/SmartExtractService';
import { OcrService } from '../../../services/ocr/OcrService';

interface PresetSample {
  label: string;
  text: string;
}

const PRESET_SAMPLES: PresetSample[] = [
  {
    label: '考试通知与考点',
    text: '【2026年秋季计算机系统期末统考安排】\n考试时间：12月28日上午 09:00-11:30，考场：教二楼 301。\n重点考核内容包括：现代操作系统死锁产生四要素、银行家算法安全性分析及矩阵资源计算；结合线性代数特征向量进行收敛推导。\n请在12月25日前提交大作业，12月27日前完成真题自测与错题整理。'
  },
  {
    label: '论文研讨纪要',
    text: '【FlowMind 墨语项目开题答辩与架构演进研讨】\n与会人：陈导师、团队全员。时间：本周五下午 14:00，创新工坊 A4 会议室。\n主要决议：\n1. 坚持端侧 Local-First 架构，保障学生隐私绝对安全；\n2. 补齐 PDF 真题矢量批注与三层原盘结构；\n3. 优化 AI 伴读结构化提取，实现通知一键落待办与知识图谱双链连接。\n待办：由李同学在周三前完成离线评测报告；张同学周四前交付新版界面。'
  },
  {
    label: '随笔灵感草稿',
    text: '今天重读贝叶斯定理，发现其用先验更新后验的核心思想不仅适用于概率推断，更是本地端侧 AI 置信度估计的数学基础。可以和银行家算法中的安全性检查做个类比。\n行动：写一篇比较随笔，并把两者的双链建立在图谱里。'
  }
];

@Component
export struct SmartExtractSheet {
  onClose: () => void = () => {};
  onCommit: (content: SmartContent, selectedTasks: SmartTask[]) => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  // 状态机: 'input' | 'extracting' | 'result'
  @State private step: string = 'input';
  @State private inputText: string = '';
  @State private extractedData: SmartContent | null = null;
  @State private selectedTaskIds: string[] = [];
  @State private errorMsg: string = '';

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    // 默认预选第一条样例，方便评委及用户秒级体验
    this.inputText = PRESET_SAMPLES[0].text;
  }

  /** 从系统相册选择截图并通过 OCR 识别提取文字 */
  private async pickImageAndOcr(): Promise<void> {
    try {
      const photoPicker = new picker.PhotoViewPicker();
      const options = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result = await photoPicker.select(options);
      if (result.photoUris && result.photoUris.length > 0) {
        const text = await OcrService.getInstance().recognizeTextFromUri(result.photoUris[0]);
        this.inputText = text;
      }
    } catch (e) {
      console.warn(`截图选择或 OCR 异常: ${JSON.stringify(e)}`);
    }
  }

  /** 执行 AI 提取 */
  private async triggerExtraction(): Promise<void> {
    const raw = this.inputText.trim();
    if (raw.length === 0) {
      this.errorMsg = '请输入或选择需要提取的内容';
      return;
    }

    this.errorMsg = '';
    animateTo({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }, () => {
      this.step = 'extracting';
    });

    try {
      const result: SmartContent = await SmartExtractService.getInstance().extract(raw, '智能提炼知识卡');
      this.extractedData = result;

      // 默认全选待办任务
      const allTaskIds: string[] = [];
      if (result.tasks) {
        for (let i = 0; i < result.tasks.length; i++) {
          allTaskIds.push(result.tasks[i].id);
        }
      }
      this.selectedTaskIds = allTaskIds;

      animateTo({ curve: curves.springMotion(0.28, 0.72) }, () => {
        this.step = 'result';
      });
    } catch (e) {
      this.errorMsg = `提取异常: ${JSON.stringify(e)}`;
      this.step = 'input';
    }
  }

  /** 切换任务勾选 */
  private toggleTask(taskId: string): void {
    if (this.selectedTaskIds.includes(taskId)) {
      this.selectedTaskIds = this.selectedTaskIds.filter((id: string) => id !== taskId);
    } else {
      this.selectedTaskIds = [...this.selectedTaskIds, taskId];
    }
  }

  /** 提交落地为知识卡与待办 */
  private commit(): void {
    if (this.extractedData === null) {
      return;
    }
    const chosenTasks: SmartTask[] = [];
    if (this.extractedData.tasks) {
      for (let i = 0; i < this.extractedData.tasks.length; i++) {
        if (this.selectedTaskIds.includes(this.extractedData.tasks[i].id)) {
          chosenTasks.push(this.extractedData.tasks[i]);
        }
      }
    }
    this.onCommit(this.extractedData, chosenTasks);
    this.onClose();
  }

  build() {
    Column() {
      Column({ space: 14 }) {
        // ---- 弹层顶栏 ----
        Row() {
          Row({ space: 8 }) {
            Text('✦')
              .fontSize(16)
              .fontColor(this.palette().accent)
            Text('AI 智能信息工作台提取')
              .fontSize(TypographyTokens.TITLE_SUB)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)
          }

          Blank()

          Text('✕')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkMuted)
            .width(28)
            .height(28)
            .textAlign(TextAlign.Center)
            .borderRadius(6)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onClose())
        }
        .width('100%')

        // ---- 步骤一：输入碎片信息 ----
        if (this.step === 'input') {
          Column({ space: 10 }) {
            // 预设样例快捷填充芯片与截图识别
            Row({ space: 8 }) {
              ForEach(PRESET_SAMPLES, (sample: PresetSample) => {
                Text(sample.label)
                  .fontSize(TypographyTokens.TINY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().accent)
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .borderRadius(8)
                  .backgroundColor(this.palette().accentSoft)
                  .hoverEffect(HoverEffect.Highlight)
                  .onClick(() => {
                    this.inputText = sample.text;
                  })
              }, (sample: PresetSample) => sample.label)

              Blank()

              Row({ space: 4 }) {
                Text('📷')
                  .fontSize(11)
                Text('截图提取')
                  .fontSize(TypographyTokens.TINY)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().inkPrimary)
              }
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .borderRadius(8)
              .backgroundColor(this.palette().surfaceSubtle)
              .border({ width: 1, color: this.palette().borderSubtle })
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => {
                this.pickImageAndOcr();
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            // 多行输入区
            TextArea({ text: this.inputText, placeholder: '在此粘贴或输入任意文本内容...' })
              .fontSize(TypographyTokens.CAPTION)
              .fontColor(this.palette().inkPrimary)
              .placeholderColor(this.palette().inkMuted)
              .backgroundColor(this.palette().surfaceSubtle)
              .borderRadius(10)
              .height(140)
              .width('100%')
              .onChange((val: string) => {
                this.inputText = val;
              })

            if (this.errorMsg.length > 0) {
              Text(this.errorMsg)
                .fontSize(TypographyTokens.TINY)
                .fontColor(this.palette().danger)
                .width('100%')
            }

            // 底部操作按钮
            Row({ space: 10 }) {
              Button('取消')
                .layoutWeight(1)
                .height(40)
                .fontSize(TypographyTokens.BODY_REGULAR)
                .fontColor(this.palette().inkSecondary)
                .backgroundColor(this.palette().surfaceSubtle)
                .borderRadius(10)
                .onClick(() => this.onClose())

              Button('✦ 开始 AI 智能提取')
                .layoutWeight(1.4)
                .height(40)
                .fontSize(TypographyTokens.BODY_REGULAR)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .backgroundColor(this.palette().accent)
                .borderRadius(10)
                .onClick(() => this.triggerExtraction())
            }
            .width('100%')
            .margin({ top: 4 })
          }
          .width('100%')
        }

        // ---- 步骤二：提取中动画 ----
        else if (this.step === 'extracting') {
          Column({ space: 14 }) {
            LoadingProgress()
              .width(42)
              .height(42)
              .color(this.palette().accent)
            Text('正在进行语义理解与结构化提炼...')
              .fontSize(TypographyTokens.BODY_REGULAR)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().inkPrimary)
            Text('识别关键实体 · 剥离行动项 · 自动关联第二大脑双链拓扑')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
          .width('100%')
          .height(220)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }

        // ---- 步骤三：提取结果与确认落地 ----
        else if (this.step === 'result' && this.extractedData !== null) {
          Scroll() {
            Column({ space: 12 }) {
              // 1. 标题与摘要卡片
              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Text(this.extractedData.title)
                    .fontSize(TypographyTokens.BODY_REGULAR)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette().inkPrimary)
                    .layoutWeight(1)
                  Text(this.extractedData.type)
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().accent)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .borderRadius(4)
                    .backgroundColor(this.palette().accentSoft)
                }
                .width('100%')

                Text(this.extractedData.summary)
                  .fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkSecondary)
                  .lineHeight(18)
              }
              .width('100%')
              .padding(12)
              .borderRadius(10)
              .backgroundColor(this.palette().surfaceSubtle)
              .alignItems(HorizontalAlign.Start)

              // 2. 标签与实体
              if (this.extractedData.tags && this.extractedData.tags.length > 0) {
                Row({ space: 6 }) {
                  Text('智能标签:')
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().inkMuted)
                  ForEach(this.extractedData.tags, (tag: string) => {
                    Text(`#${tag}`)
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().inkPrimary)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(4)
                      .backgroundColor(this.palette().surface)
                      .border({ width: 1, color: this.palette().borderSubtle })
                  }, (tag: string) => tag)
                }
                .width('100%')
              }

              // 3. 剥离出的待办行动 (可勾选直接注入 Todo 日历)
              if (this.extractedData.tasks && this.extractedData.tasks.length > 0) {
                Column({ space: 6 }) {
                  Row() {
                    Text('✦ 识别到的行动待办（勾选直接写入待办日历）:')
                      .fontSize(TypographyTokens.TINY)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.palette().accent)
                    Blank()
                    Text(`${this.selectedTaskIds.length}/${this.extractedData.tasks.length} 已选`)
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.palette().inkMuted)
                  }
                  .width('100%')

                  ForEach(this.extractedData.tasks, (task: SmartTask) => {
                    Row({ space: 8 }) {
                      Text(this.selectedTaskIds.includes(task.id) ? '☑' : '☐')
                        .fontSize(16)
                        .fontColor(this.selectedTaskIds.includes(task.id) ? this.palette().accent : this.palette().inkMuted)
                      Column({ space: 2 }) {
                        Text(task.title)
                          .fontSize(TypographyTokens.CAPTION)
                          .fontWeight(FontWeight.Medium)
                          .fontColor(this.palette().inkPrimary)
                        if (task.deadline && task.deadline.length > 0) {
                          Text(`截止时间: ${task.deadline}`)
                            .fontSize(TypographyTokens.TINY)
                            .fontColor(this.palette().warning)
                        }
                      }
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      if (task.priority === 'high') {
                        Text('高优')
                          .fontSize(TypographyTokens.TINY)
                          .fontColor('#E11D48')
                          .padding({ left: 5, right: 5, top: 1, bottom: 1 })
                          .borderRadius(3)
                          .backgroundColor('#FFE4E6')
                      }
                    }
                    .width('100%')
                    .padding(8)
                    .borderRadius(8)
                    .backgroundColor(this.selectedTaskIds.includes(task.id) ? this.palette().accentSoft : this.palette().surfaceSubtle)
                    .onClick(() => this.toggleTask(task.id))
                  }, (task: SmartTask) => task.id)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }

              // 4. 双链关联
              if (this.extractedData.relations && this.extractedData.relations.length > 0) {
                Column({ space: 4 }) {
                  Text('✦ 自动建立的双链关联:')
                    .fontSize(TypographyTokens.TINY)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.palette().inkSecondary)
                  ForEach(this.extractedData.relations, (rel: SmartRelation) => {
                    Row({ space: 6 }) {
                      Text('🔗')
                        .fontSize(12)
                      Text(`[[${rel.sourceTitle}]] → [[${rel.targetTitle}]]`)
                        .fontSize(TypographyTokens.TINY)
                        .fontColor(this.palette().inkPrimary)
                      if (rel.reason) {
                        Text(`(${rel.reason})`)
                          .fontSize(TypographyTokens.TINY)
                          .fontColor(this.palette().inkMuted)
                      }
                    }
                    .width('100%')
                  }, (rel: SmartRelation) => rel.id)
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }

              // 底部确认与重填
              Row({ space: 10 }) {
                Button('重新输入')
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(TypographyTokens.BODY_REGULAR)
                  .fontColor(this.palette().inkSecondary)
                  .backgroundColor(this.palette().surfaceSubtle)
                  .borderRadius(10)
                  .onClick(() => {
                    this.step = 'input';
                  })

                Button(`落地为知识卡与 ${this.selectedTaskIds.length} 条待办`)
                  .layoutWeight(1.6)
                  .height(40)
                  .fontSize(TypographyTokens.BODY_REGULAR)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .backgroundColor(this.palette().accent)
                  .borderRadius(10)
                  .onClick(() => this.commit())
              }
              .width('100%')
              .margin({ top: 8, bottom: 4 })
            }
            .width('100%')
          }
          .width('100%')
          .constraintSize({ maxHeight: 420 })
        }
      }
      .width('92%')
      .constraintSize({ maxWidth: 520 })
      .padding(this.isPhone ? 16 : 22)
      .borderRadius(16)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 28, color: this.isDarkMode ? 'rgba(0,0,0,0.55)' : 'rgba(0,0,0,0.18)', offsetY: 8 })
      .border({ width: 1, color: this.palette().borderSubtle })
      .transition(
        TransitionEffect.scale({ x: AnimationTokens.SCALE_MODAL_ENTER, y: AnimationTokens.SCALE_MODAL_ENTER })
          .combine(TransitionEffect.OPACITY)
          .animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD })
      )
      .onClick(() => {
        // 阻止冒泡
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.isDarkMode ? 'rgba(0,0,0,0.55)' : 'rgba(0,0,0,0.35)')
    .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_NORMAL, curve: AnimationTokens.CURVE_STANDARD }))
    .onClick(() => this.onClose())
  }
}
