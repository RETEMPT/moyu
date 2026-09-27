/**
 * 模型设置面板 (ModelSettingsSheet)
 *
 * 遵循 DeepSeek-Harness 极客架构规范与 Obsidian × Notion 高端商务美学：
 * 1. 顶部一键应用官方与主流预设（DeepSeek-V3 官方、DeepSeek-R1 思考、硅基流动、本地 Ollama）
 * 2. 三分类高阶控制中枢（接入服务、推理与思考超参、智能体与提示词）
 * 3. 严格遵循 HarmonyOS GPU 光栅化渲染避坑铁律（单层居中 Column 蒙层，单调 EaseInOut 缓动）
 */
import { curves } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ColorPalette, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import {
  ModelProfile,
  ProviderProtocol,
  ModelPresetTemplate,
  getPresetTemplates,
  createDefaultProfile
} from '../../common/types/ModelConfig';
import { ModelConfigService } from '../../services/ai/ModelConfigService';
import { createProvider } from '../../services/ai/ModelProvider';
import { BrandMark } from '../brand/BrandMark';
import { AGENT_TOOLS } from '../../services/ai/ToolRegistry';
import { AgentToolSpec } from '../../common/types/AgentTypes';

interface ProtocolOption {
  label: string;
  value: ProviderProtocol;
  hint: string;
}

const PROTOCOL_OPTIONS: ProtocolOption[] = [
  { label: 'OpenAI 兼容', value: 'openai-compat', hint: 'DeepSeek / SiliconFlow / Ollama / 中转' },
  { label: 'Gemini', value: 'gemini', hint: 'Google AI Studio 原生协议' },
  { label: 'Anthropic', value: 'anthropic', hint: 'Claude API 原生协议' }
];

interface QuickParamChip {
  label: string;
  value: number;
}

const TEMP_PRESETS: QuickParamChip[] = [
  { label: '0.0 极度精确', value: 0.0 },
  { label: '0.6 R1推荐', value: 0.6 },
  { label: '0.7 伴读主力', value: 0.7 },
  { label: '1.0 创意发散', value: 1.0 }
];

const TOKEN_PRESETS: QuickParamChip[] = [
  { label: '2K', value: 2048 },
  { label: '4K', value: 4096 },
  { label: '8K', value: 8192 },
  { label: '16K', value: 16384 }
];

interface ModelIdChip {
  label: string;
  id: string;
}

const COMMON_MODEL_IDS: ModelIdChip[] = [
  { label: 'deepseek-v4-pro (旗舰版)', id: 'deepseek-v4-pro' },
  { label: 'deepseek-flash (闪速版)', id: 'deepseek-flash' },
  { label: 'deepseek-chat (官方通用)', id: 'deepseek-chat' },
  { label: 'deepseek-reasoner (深度思考)', id: 'deepseek-reasoner' }
];

@Component
export struct ModelSettingsSheet {
  onClose: () => void = () => {};

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;

  @State profiles: ModelProfile[] = [];
  @State currentId: string = '';
  @State currentTab: number = 0; // 0: 接入服务, 1: 推理超参, 2: 提示词与工具

  // 表单字段
  @State label: string = '';
  @State protocol: ProviderProtocol = 'openai-compat';
  @State baseUrl: string = '';
  @State apiKey: string = '';
  @State modelId: string = '';
  @State embeddingModelId: string = '';
  @State temperature: number = 0.7;
  @State maxTokens: number = 4096;
  @State stream: boolean = true;
  @State isReasoningModel: boolean = false;
  @State systemPrompt: string = '';

  // 状态反馈
  @State testResult: string = '';
  @State testLatency: number = -1;
  @State testing: boolean = false;
  @State showKey: boolean = false;

  aboutToAppear(): void {
    this.initAndLoad();
  }

  private async initAndLoad(): Promise<void> {
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      await ModelConfigService.getInstance().init(ctx);
    } catch (error) {
      console.error(`模型配置自初始化跳过: ${JSON.stringify(error)}`);
    }
    try {
      this.profiles = await ModelConfigService.getInstance().loadProfiles();
      const active: ModelProfile = await ModelConfigService.getInstance().getActiveProfile();
      this.fillForm(active);
    } catch (error) {
      console.error(`模型配置加载失败: ${JSON.stringify(error)}`);
      this.testResult = '✗ 配置读取失败';
    }
  }

  private fillForm(p: ModelProfile): void {
    this.currentId = p.id;
    this.label = p.label;
    this.protocol = p.protocol;
    this.baseUrl = p.baseUrl;
    this.apiKey = p.apiKey;
    this.modelId = p.modelId;
    this.embeddingModelId = p.embeddingModelId ?? '';
    this.temperature = p.temperature;
    this.maxTokens = p.maxTokens;
    this.stream = p.stream;
    this.isReasoningModel = p.isReasoningModel ?? (p.modelId.includes('reasoner') || p.modelId.includes('r1'));
    this.systemPrompt = p.systemPrompt ?? '';
    this.testResult = '';
    this.testLatency = -1;
  }

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  private applyPreset(preset: ModelPresetTemplate): void {
    this.label = preset.profile.label;
    this.protocol = preset.profile.protocol;
    this.baseUrl = preset.profile.baseUrl;
    if (preset.profile.apiKey.length > 0) {
      this.apiKey = preset.profile.apiKey;
    }
    this.modelId = preset.profile.modelId;
    this.embeddingModelId = preset.profile.embeddingModelId ?? '';
    this.temperature = preset.profile.temperature;
    this.maxTokens = preset.profile.maxTokens;
    this.stream = preset.profile.stream;
    this.isReasoningModel = preset.profile.isReasoningModel ?? false;
    this.testResult = `已载入预设「${preset.name}」配置`;
    this.testLatency = -1;
  }

  private async save(): Promise<void> {
    const svc: ModelConfigService = ModelConfigService.getInstance();
    const cleanLabel: string = this.label.trim();
    const cleanBaseUrl: string = this.baseUrl.trim();
    const cleanApiKey: string = this.apiKey.trim();
    const cleanModelId: string = this.modelId.trim();
    const cleanEmbedding: string = this.embeddingModelId.trim();

    this.label = cleanLabel;
    this.baseUrl = cleanBaseUrl;
    this.apiKey = cleanApiKey;
    this.modelId = cleanModelId;
    this.embeddingModelId = cleanEmbedding;

    let found: boolean = false;
    for (const p of this.profiles) {
      if (p.id === this.currentId) {
        p.label = cleanLabel;
        p.protocol = this.protocol;
        p.baseUrl = cleanBaseUrl;
        p.apiKey = cleanApiKey;
        p.modelId = cleanModelId;
        p.embeddingModelId = cleanEmbedding;
        p.temperature = this.temperature;
        p.maxTokens = this.maxTokens;
        p.stream = this.stream;
        p.isReasoningModel = this.isReasoningModel;
        p.systemPrompt = this.systemPrompt;
        p.updatedAt = Date.now();
        found = true;
        break;
      }
    }
    if (!found) {
      const np: ModelProfile = createDefaultProfile();
      np.label = cleanLabel;
      np.protocol = this.protocol;
      np.baseUrl = cleanBaseUrl;
      np.apiKey = cleanApiKey;
      np.modelId = cleanModelId;
      np.embeddingModelId = cleanEmbedding;
      np.temperature = this.temperature;
      np.maxTokens = this.maxTokens;
      np.stream = this.stream;
      np.isReasoningModel = this.isReasoningModel;
      np.systemPrompt = this.systemPrompt;
      this.profiles.push(np);
      this.currentId = np.id;
    }
    await svc.saveProfiles(this.profiles);
    await svc.setActiveProfileId(this.currentId);
    this.testResult = '✓ 已保存并激活当前档案配置';
  }

  private async testConnection(): Promise<void> {
    this.testing = true;
    this.testResult = '正在发起探测请求，校验端点与密钥连通性…';
    this.testLatency = -1;
    try {
      const profile: ModelProfile = this.buildProfile();
      const provider = createProvider(profile.protocol);
      const result = await provider.testConnection(profile);
      this.testLatency = result.latencyMs;
      this.testResult = result.ok
        ? `✓ 连通正常 · 延迟 ${result.latencyMs}ms (${this.latencyRating(result.latencyMs)})`
        : `✗ ${result.message}`;
    } catch (err) {
      this.testResult = `✗ ${err instanceof Error ? err.message : '未知异常'}`;
    }
    this.testing = false;
  }

  private latencyRating(ms: number): string {
    if (ms < 350) {
      return '极速';
    }
    if (ms < 800) {
      return '良好';
    }
    return '偏高';
  }

  private buildProfile(): ModelProfile {
    return {
      id: this.currentId || `profile_${Date.now()}`,
      label: this.label.trim(),
      protocol: this.protocol,
      baseUrl: this.baseUrl.trim(),
      apiKey: this.apiKey.trim(),
      modelId: this.modelId.trim(),
      embeddingModelId: this.embeddingModelId.trim(),
      temperature: this.temperature,
      maxTokens: this.maxTokens,
      stream: this.stream,
      isReasoningModel: this.isReasoningModel,
      systemPrompt: this.systemPrompt,
      createdAt: Date.now(),
      updatedAt: Date.now()
    };
  }

  private async switchProfile(id: string): Promise<void> {
    for (const p of this.profiles) {
      if (p.id === id) {
        this.fillForm(p);
        const svc: ModelConfigService = ModelConfigService.getInstance();
        await svc.setActiveProfileId(id);
        return;
      }
    }
  }

  private async addProfile(): Promise<void> {
    const np: ModelProfile = createDefaultProfile();
    np.label = '新模型档案';
    this.profiles.push(np);
    this.fillForm(np);
  }

  private async removeProfile(): Promise<void> {
    if (this.profiles.length <= 1) {
      this.testResult = '至少保留一个模型档案';
      return;
    }
    const svc: ModelConfigService = ModelConfigService.getInstance();
    this.profiles = await svc.deleteProfile(this.currentId);
    if (this.profiles.length > 0) {
      this.fillForm(this.profiles[0]);
    }
  }

  build() {
    // 遮罩蒙层：遵循 GPU 光栅化避坑铁律，单层居中 Column
    Column() {
      Column({ space: 0 }) {
        // 1. 顶栏
        Row({ space: 10 }) {
          BrandMark({ markSize: 28 })
          Column({ space: 2 }) {
            Row({ space: 6 }) {
              Text('模型接入与智能体设置')
                .fontSize(TypographyTokens.TITLE_SUB)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.palette().inkPrimary)
            }
            Text('配置模型 API 端点、密钥、超参及智能体运行规则')
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('✕')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().inkSecondary)
            .width(28).height(28)
            .textAlign(TextAlign.Center)
            .borderRadius(6)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.onClose())
        }
        .width('100%')
        .padding({ left: 16, right: 14, top: 14, bottom: 12 })

        Divider().strokeWidth(1).color(this.palette().borderSubtle)

        // 2. 档案切换行
        Row({ space: 6 }) {
          Text('档案')
            .fontSize(TypographyTokens.TINY)
            .fontColor(this.palette().inkMuted)
            .margin({ right: 2 })

          ForEach(this.profiles, (p: ModelProfile) => {
            Text(p.label)
              .fontSize(TypographyTokens.TINY)
              .fontColor(p.id === this.currentId ? Color.White : this.palette().inkSecondary)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .borderRadius(12)
              .backgroundColor(p.id === this.currentId ? this.palette().accent : this.palette().surfaceSubtle)
              .animation({ duration: 180, curve: Curve.EaseInOut })
              .onClick(() => this.switchProfile(p.id))
          }, (p: ModelProfile) => p.id)

          Text('+')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontColor(this.palette().accent)
            .width(26).height(26)
            .textAlign(TextAlign.Center)
            .borderRadius(13)
            .backgroundColor(this.palette().accentSoft)
            .onClick(() => this.addProfile())
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 8 })

        // 3. 选项卡切换（Tab 0: 接入, Tab 1: 推理超参, Tab 2: 智能体与提示词）
        Row({ space: 8 }) {
          Text('⚡ 接入与预设')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(this.currentTab === 0 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTab === 0 ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.currentTab === 0 ? this.palette().accentSoft : Color.Transparent)
            .animation({ duration: 180, curve: Curve.EaseInOut })
            .onClick(() => { this.currentTab = 0; })

          Text('⚙ 推理与思考超参')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(this.currentTab === 1 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTab === 1 ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.currentTab === 1 ? this.palette().accentSoft : Color.Transparent)
            .animation({ duration: 180, curve: Curve.EaseInOut })
            .onClick(() => { this.currentTab = 1; })

          Text('✦ 智能体与工具')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(this.currentTab === 2 ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.currentTab === 2 ? this.palette().accent : this.palette().inkSecondary)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(6)
            .backgroundColor(this.currentTab === 2 ? this.palette().accentSoft : Color.Transparent)
            .animation({ duration: 180, curve: Curve.EaseInOut })
            .onClick(() => { this.currentTab = 2; })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 4, bottom: 10 })

        Divider().strokeWidth(1).color(this.palette().borderSubtle)

        // 4. 表单内容区
        Scroll() {
          Column({ space: 10 }) {
            // TAB 0: 接入服务与一键预设
            if (this.currentTab === 0) {
              // 预设模版快速卡片网格
              Column({ space: 6 }) {
                Text('一键应用主流预设')
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkMuted)
                  .width('100%')

                Row({ space: 8 }) {
                  ForEach(getPresetTemplates(), (preset: ModelPresetTemplate) => {
                    Column({ space: 2 }) {
                      Text(preset.name)
                        .fontSize(TypographyTokens.TINY)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.palette().inkPrimary)
                        .maxLines(1)
                      Text(preset.description)
                        .fontSize(TypographyTokens.TINY)
                        .fontColor(this.palette().inkMuted)
                        .maxLines(1)
                    }
                    .layoutWeight(1)
                    .padding(8)
                    .borderRadius(8)
                    .backgroundColor(this.palette().surfaceSubtle)
                    .border({ width: 1, color: this.palette().borderSubtle })
                    .onClick(() => this.applyPreset(preset))
                  }, (preset: ModelPresetTemplate) => preset.name)
                }
                .width('100%')
              }
              .width('100%')
              .padding({ top: 6, bottom: 4 })

              Divider().strokeWidth(1).color(this.palette().borderSubtle)

              // 基础表单输入
              Row({ space: 8 }) {
                Text('档案名称').fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkSecondary).width(80)
                TextInput({ text: this.label })
                  .fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkPrimary)
                  .backgroundColor(this.palette().surfaceSubtle)
                  .borderRadius(6)
                  .height(34)
                  .layoutWeight(1)
                  .onChange((v: string) => { this.label = v; })
              }
              .width('100%')

              Row({ space: 8 }) {
                Text('协议类型').fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkSecondary).width(80)
                Row({ space: 6 }) {
                  ForEach(PROTOCOL_OPTIONS, (opt: ProtocolOption) => {
                    Row({ space: 4 }) {
                      Circle({ width: 12, height: 12 })
                        .fill(this.protocol === opt.value ? this.palette().accent : Color.Transparent)
                        .stroke(this.protocol === opt.value ? this.palette().accent : this.palette().border)
                        .strokeWidth(1.5)
                      Text(opt.label)
                        .fontSize(TypographyTokens.TINY)
                        .fontColor(this.protocol === opt.value ? this.palette().inkPrimary : this.palette().inkMuted)
                    }
                    .padding({ left: 8, right: 8, top: 6, bottom: 6 })
                    .borderRadius(6)
                    .backgroundColor(this.protocol === opt.value ? this.palette().accentSoft : this.palette().surfaceSubtle)
                    .onClick(() => { this.protocol = opt.value; })
                  }, (opt: ProtocolOption) => opt.value)
                }
                .layoutWeight(1)
              }
              .width('100%')

              Row({ space: 8 }) {
                Text('Base URL').fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkSecondary).width(80)
                TextInput({ text: this.baseUrl, placeholder: 'https://api.deepseek.com/v1' })
                  .fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkPrimary)
                  .placeholderColor(this.palette().inkMuted)
                  .backgroundColor(this.palette().surfaceSubtle)
                  .borderRadius(6)
                  .height(34)
                  .layoutWeight(1)
                  .onChange((v: string) => { this.baseUrl = v; })
              }
              .width('100%')

              Row({ space: 8 }) {
                Text('API Key').fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkSecondary).width(80)
                TextInput({ text: this.apiKey, placeholder: 'sk-…' })
                  .type(InputType.Password)
                  .showPassword(this.showKey)
                  .fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkPrimary)
                  .placeholderColor(this.palette().inkMuted)
                  .backgroundColor(this.palette().surfaceSubtle)
                  .borderRadius(6)
                  .height(34)
                  .layoutWeight(1)
                  .onChange((v: string) => { this.apiKey = v; })
                Text(this.showKey ? '隐藏' : '显示')
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().accent)
                  .padding({ left: 6, right: 6, top: 6, bottom: 6 })
                  .onClick(() => { this.showKey = !this.showKey; })
              }
              .width('100%')

              Row({ space: 8 }) {
                Text('模型 ID').fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkSecondary).width(80)
                TextInput({ text: this.modelId, placeholder: 'deepseek-chat' })
                  .fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkPrimary)
                  .placeholderColor(this.palette().inkMuted)
                  .backgroundColor(this.palette().surfaceSubtle)
                  .borderRadius(6)
                  .height(34)
                  .layoutWeight(1)
                  .onChange((v: string) => { this.modelId = v; })
              }
              .width('100%')

              // 常用官方与主流模型 ID 快速选择
              Row({ space: 6 }) {
                Text('快捷填入:').fontSize(TypographyTokens.TINY).fontColor(this.palette().inkMuted)
                ForEach(COMMON_MODEL_IDS, (chip: ModelIdChip) => {
                  Text(chip.label)
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.modelId === chip.id ? this.palette().accent : this.palette().inkSecondary)
                    .padding({ left: 6, right: 6, top: 3, bottom: 3 })
                    .borderRadius(4)
                    .backgroundColor(this.modelId === chip.id ? this.palette().accentSoft : this.palette().surfaceSubtle)
                    .onClick(() => {
                      this.modelId = chip.id;
                      if (chip.id.includes('reasoner') || chip.id.includes('r1')) {
                        this.isReasoningModel = true;
                      }
                    })
                }, (chip: ModelIdChip) => chip.id)
              }
              .width('100%')
              .padding({ left: 88, bottom: 4 })

              Row({ space: 8 }) {
                Text('向量模型').fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkSecondary).width(80)
                TextInput({ text: this.embeddingModelId, placeholder: '可选，如 BAAI/bge-m3' })
                  .fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkPrimary)
                  .placeholderColor(this.palette().inkMuted)
                  .backgroundColor(this.palette().surfaceSubtle)
                  .borderRadius(6)
                  .height(34)
                  .layoutWeight(1)
                  .onChange((v: string) => { this.embeddingModelId = v; })
              }
              .width('100%')
            }

            // TAB 1: 推理与思考超参
            if (this.currentTab === 1) {
              // 深度思考模型模式
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text('深度思考 / 思考流解析')
                    .fontSize(TypographyTokens.CAPTION)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.palette().inkPrimary)
                  Text('开启后自动捕获并展示链式思考过程')
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().inkMuted)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.isReasoningModel })
                  .selectedColor(this.palette().accent)
                  .onChange((isOn: boolean) => { this.isReasoningModel = isOn; })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(8)
              .backgroundColor(this.palette().surfaceSubtle)

              // 流式传输
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text('流式输出 (Stream)')
                    .fontSize(TypographyTokens.CAPTION)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.palette().inkPrimary)
                  Text('逐字/逐片段下发文本与思考流，提供极致打字机反馈')
                    .fontSize(TypographyTokens.TINY)
                    .fontColor(this.palette().inkMuted)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.stream })
                  .selectedColor(this.palette().accent)
                  .onChange((isOn: boolean) => { this.stream = isOn; })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(8)
              .backgroundColor(this.palette().surfaceSubtle)

              // 温度
              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Text('采样温度 (Temperature)').fontSize(TypographyTokens.CAPTION)
                    .fontColor(this.palette().inkSecondary).layoutWeight(1)
                  Text(this.temperature.toFixed(2))
                    .fontSize(TypographyTokens.CAPTION)
                    .fontWeight(FontWeight.Bold)
                    .fontColor(this.palette().accent)
                }
                .width('100%')

                Slider({ value: this.temperature * 50, min: 0, max: 100, step: 2 })
                  .width('100%')
                  .selectedColor(this.palette().accent)
                  .onChange((v: number) => {
                    this.temperature = Math.round(v / 50 * 100) / 100;
                  })

                Row({ space: 6 }) {
                  ForEach(TEMP_PRESETS, (preset: QuickParamChip) => {
                    Text(preset.label)
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.temperature === preset.value ? this.palette().accent : this.palette().inkMuted)
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .borderRadius(4)
                      .backgroundColor(this.temperature === preset.value ? this.palette().accentSoft : this.palette().surfaceSubtle)
                      .onClick(() => { this.temperature = preset.value; })
                  }, (preset: QuickParamChip) => preset.label)
                }
                .width('100%')
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(8)
              .backgroundColor(this.palette().surfaceSubtle)

              // 最大 Token
              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Text('最大输出 Token (Max Tokens)').fontSize(TypographyTokens.CAPTION)
                    .fontColor(this.palette().inkSecondary).layoutWeight(1)
                  TextInput({ text: `${this.maxTokens}` })
                    .fontSize(TypographyTokens.CAPTION)
                    .fontColor(this.palette().inkPrimary)
                    .backgroundColor(this.palette().surface)
                    .width(90).height(30)
                    .borderRadius(4)
                    .onChange((v: string) => {
                      const n = parseInt(v);
                      if (!isNaN(n) && n > 0) {
                        this.maxTokens = n;
                      }
                    })
                }
                .width('100%')

                Row({ space: 6 }) {
                  ForEach(TOKEN_PRESETS, (preset: QuickParamChip) => {
                    Text(preset.label)
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(this.maxTokens === preset.value ? this.palette().accent : this.palette().inkMuted)
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                      .borderRadius(4)
                      .backgroundColor(this.maxTokens === preset.value ? this.palette().accentSoft : this.palette().surfaceSubtle)
                      .onClick(() => { this.maxTokens = preset.value; })
                  }, (preset: QuickParamChip) => preset.label)
                }
                .width('100%')
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(8)
              .backgroundColor(this.palette().surfaceSubtle)
            }

            // TAB 2: 智能体与提示词
            if (this.currentTab === 2) {
              Column({ space: 6 }) {
                Text('自定义系统附加指令')
                  .fontSize(TypographyTokens.CAPTION)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().inkPrimary)
                  .width('100%')
                Text('追加在核心角色提示词之后，可用于定制回答语气或特定领域的排版偏好。')
                  .fontSize(TypographyTokens.TINY)
                  .fontColor(this.palette().inkMuted)
                  .width('100%')

                TextArea({ text: this.systemPrompt, placeholder: '例如：回答请优先使用中文，数理定理务必标明适用边界…' })
                  .fontSize(TypographyTokens.CAPTION)
                  .fontColor(this.palette().inkPrimary)
                  .placeholderColor(this.palette().inkMuted)
                  .backgroundColor(this.palette().surfaceSubtle)
                  .borderRadius(8)
                  .height(100)
                  .width('100%')
                  .onChange((v: string) => { this.systemPrompt = v; })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(8)
              .backgroundColor(this.palette().surfaceSubtle)

              // 内置工具清单
              Column({ space: 6 }) {
                Text('智能体工具链')
                  .fontSize(TypographyTokens.CAPTION)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.palette().inkPrimary)
                  .width('100%')

                ForEach(AGENT_TOOLS, (tool: AgentToolSpec) => {
                  Row({ space: 8 }) {
                    Text(tool.permission === 'read' ? '只读' : '写权限')
                      .fontSize(TypographyTokens.TINY)
                      .fontColor(tool.permission === 'read' ? '#3B82F6' : '#F59E0B')
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(4)
                      .backgroundColor(this.palette().surface)

                    Column({ space: 1 }) {
                      Text(tool.name)
                        .fontSize(TypographyTokens.CAPTION)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(this.palette().inkPrimary)
                      Text(tool.description)
                        .fontSize(TypographyTokens.TINY)
                        .fontColor(this.palette().inkMuted)
                        .maxLines(1)
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .borderRadius(6)
                  .backgroundColor(this.palette().surface)
                }, (tool: AgentToolSpec) => tool.name)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(8)
              .backgroundColor(this.palette().surfaceSubtle)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)

        Divider().strokeWidth(1).color(this.palette().borderSubtle)

        // 5. 诊断与反馈面板
        if (this.testResult.length > 0) {
          Column({ space: 4 }) {
            Row({ space: 6 }) {
              Circle({ width: 6, height: 6 })
                .fill(this.testResult.startsWith('✓') ? '#22C55E' : (this.testResult.startsWith('✗') ? '#EF4444' : this.palette().accent))
              Text(this.testResult.startsWith('✓') ? '连通性测试通过' : (this.testResult.startsWith('✗') ? '连通异常诊断与排查' : '状态反馈'))
                .fontSize(TypographyTokens.TINY)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.testResult.startsWith('✓') ? '#22C55E' : (this.testResult.startsWith('✗') ? '#EF4444' : this.palette().accent))
            }
            Text(this.testResult)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkPrimary)
              .lineHeight(18)
              .width('100%')
          }
          .width('100%')
          .padding(10)
          .margin({ left: 16, right: 16, top: 8, bottom: 4 })
          .borderRadius(8)
          .backgroundColor(this.palette().surfaceSubtle)
          .border({ width: 1, color: this.testResult.startsWith('✓') ? 'rgba(34, 197, 94, 0.25)' : (this.testResult.startsWith('✗') ? 'rgba(239, 68, 68, 0.25)' : this.palette().borderSubtle) })
        }

        // 6. 底部动作栏
        Row({ space: 10 }) {
          Button(this.testing ? '探测中…' : '测试连接')
            .type(ButtonType.Normal)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().accent)
            .backgroundColor(this.palette().accentSoft)
            .borderRadius(8)
            .height(36)
            .enabled(!this.testing)
            .onClick(() => this.testConnection())

          Button('删除档案')
            .type(ButtonType.Normal)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
            .backgroundColor(this.palette().surfaceSubtle)
            .borderRadius(8)
            .height(36)
            .onClick(() => this.removeProfile())

          Blank()

          Button('保存并应用')
            .type(ButtonType.Normal)
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(this.palette().accent)
            .borderRadius(8)
            .height(36)
            .padding({ left: 16, right: 16 })
            .onClick(() => {
              this.save();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 14 })

        // 安全提示
        Text('密钥与配置均落盘于端侧 Preferences，零云端上传，导出时自动脱敏。')
          .fontSize(TypographyTokens.TINY)
          .fontColor(this.palette().inkMuted)
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 10 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 640 })
      .borderRadius(16)
      .backgroundColor(this.palette().surface)
      .shadow({ radius: 36, color: 'rgba(0,0,0,0.28)' })
      .border({ width: 1, color: this.palette().border })
      .onClick(() => {
        // 阻止冒泡
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 30, bottom: 30 })
    .backgroundColor('rgba(0,0,0,0.35)')
    .transition(TransitionEffect.OPACITY.animation({ duration: 180, curve: Curve.EaseInOut }))
    .onClick(() => this.onClose())
  }
}
