import { common } from '@kit.AbilityKit';
import { AnimationTokens, ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { ModelProfile, ModelPresetTemplate, ProviderProtocol, getPresetTemplates, createDefaultProfile } from '../../common/types/ModelConfig';
import { ModelConfigService } from '../../services/ai/ModelConfigService';
import { ModelProfilePolicy } from '../../services/ai/ModelProfilePolicy';
import { createProvider } from '../../services/ai/ModelProvider';
import { AGENT_TOOLS, toolDisplayName } from '../../services/ai/ToolRegistry';
import { AgentToolSpec } from '../../common/types/AgentTypes';

interface ProtocolOption { label: string; value: ProviderProtocol; }
const PROTOCOLS: ProtocolOption[] = [
  { label: '兼容 API', value: 'openai-compat' }, { label: 'Gemini', value: 'gemini' }, { label: 'Anthropic', value: 'anthropic' }
];
interface AccessOption { label: string; value: 'none' | 'read' | 'confirm-write'; }
const ACCESS_OPTIONS: AccessOption[] = [
  { label: '关闭工具', value: 'none' }, { label: '只读检索', value: 'read' }, { label: '写入前确认', value: 'confirm-write' }
];

@Component
export struct ModelSettingsSheet {
  onClose: () => void = () => {};
  @Prop @Watch('requestClose') closeToken: number = 0;
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @State profiles: ModelProfile[] = [];
  @State currentId: string = '';
  @State activeId: string = '';
  @State tab: number = 0;
  @State label: string = '';
  @State protocol: ProviderProtocol = 'openai-compat';
  @State baseUrl: string = '';
  @State apiKey: string = '';
  @State modelId: string = '';
  @State embeddingId: string = '';
  @State semanticSearch: boolean = false;
  @State temperature: string = '0.7';
  @State maxTokens: string = '8192';
  @State stream: boolean = true;
  @State systemPrompt: string = '';
  @State toolAccess: 'none' | 'read' | 'confirm-write' = 'confirm-write';
  @State rounds: string = '5';
  @State busy: boolean = false;
  @State showKey: boolean = false;
  @State feedback: string = '';
  @State feedbackError: boolean = false;
  @State closeWarning: boolean = false;
  @State deleteWarning: boolean = false;
  private drafts: Map<string, ModelProfile> = new Map();
  private newProfiles: Set<string> = new Set();
  private alive: boolean = true;
  private createdAt: number = 0;

  aboutToAppear(): void { this.alive = true; this.load(); }
  aboutToDisappear(): void { this.alive = false; }
  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark); }
  private report(message: string, error: boolean = false): void { this.feedback = message; this.feedbackError = error; }
  private changed(): void { this.feedback = ''; this.deleteWarning = false; this.closeWarning = false; }

  private async load(): Promise<void> {
    this.busy = true;
    try {
      const service = ModelConfigService.getInstance();
      await service.init(getContext(this) as common.UIAbilityContext);
      const profiles = await service.loadProfiles();
      const active = await service.getActiveProfile();
      if (!this.alive) { return; }
      this.profiles = profiles; this.activeId = active.id; this.fill(active);
    } catch { if (this.alive) { this.report('配置读取失败，请关闭后重试', true); } }
    finally { if (this.alive) { this.busy = false; } }
  }

  private fill(p: ModelProfile): void {
    this.currentId = p.id; this.createdAt = p.createdAt;
    this.label = p.label; this.protocol = p.protocol; this.baseUrl = p.baseUrl;
    this.apiKey = p.apiKey; this.modelId = p.modelId; this.embeddingId = p.embeddingModelId || '';
    this.semanticSearch = p.semanticSearch === true;
    this.temperature = `${p.temperature}`; this.maxTokens = `${p.maxTokens}`; this.stream = p.stream;
    this.systemPrompt = p.systemPrompt; this.toolAccess = p.toolAccess || 'confirm-write'; this.rounds = `${p.maxToolRounds || 5}`;
    this.showKey = false; this.changed();
  }

  private form(): ModelProfile {
    const previous = this.profiles.find((p: ModelProfile) => p.id === this.currentId);
    return { id: this.currentId, label: this.label.trim(), protocol: this.protocol,
      baseUrl: this.baseUrl.trim().replace(/\/+$/, ''), apiKey: this.apiKey.trim(), modelId: this.modelId.trim(),
      embeddingModelId: this.embeddingId.trim(), temperature: Number(this.temperature), maxTokens: Number(this.maxTokens),
      semanticSearch: this.semanticSearch,
      stream: this.stream, systemPrompt: this.systemPrompt, toolAccess: this.toolAccess, maxToolRounds: Number(this.rounds),
      isReasoningModel: previous?.isReasoningModel, thinkingBudget: previous?.thinkingBudget,
      createdAt: this.createdAt, updatedAt: previous?.updatedAt || this.createdAt };
  }

  private signature(p: ModelProfile): string {
    const clone = JSON.parse(JSON.stringify(p)) as ModelProfile;
    clone.updatedAt = 0;
    clone.toolAccess = p.toolAccess || 'confirm-write'; clone.maxToolRounds = p.maxToolRounds ?? 5;
    clone.embeddingModelId = p.embeddingModelId || ''; clone.semanticSearch = p.semanticSearch === true;
    clone.isReasoningModel = p.isReasoningModel === true;
    return JSON.stringify(clone);
  }

  private switchProfile(p: ModelProfile): void {
    if (this.busy || this.currentId === p.id) { return; }
    this.drafts.set(this.currentId, this.form());
    this.fill(this.drafts.get(p.id) || p);
  }

  private add(): void {
    if (this.busy) { return; }
    this.drafts.set(this.currentId, this.form());
    const p = createDefaultProfile(); p.id = `profile_${Date.now()}_${this.profiles.length}`; p.label = '新模型档案';
    this.profiles = [...this.profiles, p]; this.drafts.set(p.id, p); this.newProfiles.add(p.id); this.fill(p);
    this.report('新档案尚未保存，填写后点击“保存并启用”');
  }

  private preset(preset: ModelPresetTemplate): void {
    const key = this.baseUrl.replace(/\/+$/, '') === preset.profile.baseUrl.replace(/\/+$/, '') && this.protocol === preset.profile.protocol ? this.apiKey : '';
    const copy = ModelProfilePolicy.restore(preset.profile)!;
    copy.id = this.currentId; copy.apiKey = preset.profile.apiKey || key; copy.createdAt = this.createdAt;
    this.fill(copy);
    this.report('预设已填入，请核对模型 ID、密钥和服务地址后测试');
  }

  private requestClose(): void {
    if (this.busy) { return; }
    this.drafts.set(this.currentId, this.form());
    let dirty = this.newProfiles.size > 0;
    this.drafts.forEach((draft: ModelProfile, id: string) => {
      const original = this.profiles.find((p: ModelProfile) => p.id === id);
      if (!original || this.signature(original) !== this.signature(draft)) { dirty = true; }
    });
    if (dirty) { this.closeWarning = true; } else { this.onClose(); }
  }

  private async save(): Promise<void> {
    if (this.busy) { return; }
    const p = this.form(); const error = ModelProfilePolicy.validate(p);
    if (error.length > 0) { this.report(error, true); return; }
    this.busy = true;
    try {
      p.updatedAt = Date.now();
      const saved = await ModelConfigService.getInstance().saveAndActivate(p);
      if (!this.alive) { return; }
      const pending = this.profiles.filter((item: ModelProfile) => this.newProfiles.has(item.id) && item.id !== p.id);
      this.profiles = saved.concat(pending); this.activeId = p.id; this.drafts.delete(p.id); this.newProfiles.delete(p.id); this.fill(p);
      this.report('档案已保存并启用。连接状态请单独测试。');
    } catch { this.report('保存失败，输入已保留，请重试', true); }
    finally { this.busy = false; }
  }

  private async test(): Promise<void> {
    if (this.busy) { return; }
    const p = this.form(); const error = ModelProfilePolicy.validate(p);
    if (error) { this.report(error, true); return; }
    this.busy = true; this.report('正在测试此表单的模型连接…');
    try {
      const result = await createProvider(p.protocol).testConnection(p);
      if (this.alive) { this.report(result.ok ? `连接测试通过 · ${result.latencyMs} ms；尚未保存的输入需另行保存。` : `连接测试失败：${result.message}`, !result.ok); }
    } catch { if (this.alive) { this.report('连接测试失败，请检查地址、密钥和网络', true); } }
    finally { if (this.alive) { this.busy = false; } }
  }

  private async remove(): Promise<void> {
    if (this.busy) { return; }
    if (this.newProfiles.has(this.currentId)) {
      const id = this.currentId; this.newProfiles.delete(id); this.drafts.delete(id);
      this.profiles = this.profiles.filter((p: ModelProfile) => p.id !== id);
      this.fill(this.drafts.get(this.activeId) || this.profiles.find((p: ModelProfile) => p.id === this.activeId) || this.profiles[0]);
      return;
    }
    this.busy = true;
    try {
      const saved = await ModelConfigService.getInstance().deleteProfile(this.currentId);
      this.drafts.delete(this.currentId); this.profiles = saved;
      const active = await ModelConfigService.getInstance().getActiveProfile(); this.activeId = active.id; this.fill(active);
      this.report('档案已删除');
    } catch { this.report('删除失败，请重试', true); }
    finally { this.busy = false; this.deleteWarning = false; }
  }

  @Builder
  hint(text: string) { Text(text).fontSize(12).lineHeight(20).fontColor(this.palette().inkSecondary).width('100%') }
  @Builder
  field(label: string, value: () => string, placeholder: string, update: (value: string) => void) {
    Column({ space: 6 }) {
      Text(label).fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
      TextInput({ text: value(), placeholder }).height(48).fontSize(14).backgroundColor(this.palette().surfaceSubtle)
        .fontColor(this.palette().inkPrimary).onChange((text: string) => { update(text); this.changed(); })
    }.width('100%')
  }

  @Builder
  connection() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(getPresetTemplates(), (p: ModelPresetTemplate) => {
          Column({ space: 5 }) {
            Text(p.name).fontSize(13).fontWeight(FontWeight.Medium).maxLines(2).fontColor(this.palette().inkPrimary)
            Text(p.description).fontSize(11).maxLines(3).fontColor(this.palette().inkSecondary)
          }.width(160).height(100).padding(12).alignItems(HorizontalAlign.Start).borderRadius(10)
            .backgroundColor(this.palette().surfaceSubtle).onClick(() => this.preset(p))
        }, (p: ModelPresetTemplate) => p.name)
      }
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
    this.field('档案名称', () => this.label, '例如：学习助手', (v: string) => { this.label = v; })
    Row({ space: 6 }) {
      ForEach(PROTOCOLS, (p: ProtocolOption) => {
        Button(p.label).height(44).layoutWeight(1).fontSize(12)
          .backgroundColor(this.protocol === p.value ? this.palette().accent : this.palette().surfaceSubtle)
          .fontColor(this.protocol === p.value ? Color.White : this.palette().inkSecondary)
          .onClick(() => { this.protocol = p.value; this.changed(); })
      }, (p: ProtocolOption) => p.value)
    }.width('100%')
    this.field('服务地址', () => this.baseUrl, 'https://…', (v: string) => {
      if (v.split('/')[2] !== this.baseUrl.split('/')[2]) { this.apiKey = ''; }
      this.baseUrl = v;
    })
    this.hint(this.protocol === 'gemini' ? 'Gemini 地址应含 API 版本，例如 /v1beta。' : this.protocol === 'anthropic' ? '填写服务根地址，程序追加 /v1/messages。' : '填写兼容 API 的根地址（通常以 /v1 结尾），程序追加 /chat/completions。')
    Row({ space: 8 }) {
      TextInput({ text: this.apiKey, placeholder: 'API Key' }).type(this.showKey ? InputType.Normal : InputType.Password)
        .height(48).layoutWeight(1).fontSize(14).backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkPrimary)
        .onChange((v: string) => { this.apiKey = v; this.changed(); })
      Button(this.showKey ? '隐藏' : '显示').width(64).height(44).onClick(() => { this.showKey = !this.showKey; })
    }.width('100%')
    this.field('模型 ID', () => this.modelId, '服务商控制台中的实际 ID', (v: string) => { this.modelId = v; })
    this.hint('密钥保存在本机应用配置中。调用远程模型时，会向所填服务地址发送问题和选中的笔记内容。')
  }

  @Builder
  output() {
    this.field('温度 · 0–2', () => this.temperature, '0.7', (v: string) => { this.temperature = v; })
    this.field('输出 Token 上限 · 256–65536', () => this.maxTokens, '8192', (v: string) => { this.maxTokens = v; })
    Row() {
      Text('流式输出').fontSize(14).fontColor(this.palette().inkPrimary).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.stream }).onChange((v: boolean) => { this.stream = v; this.changed(); })
    }.height(48).width('100%')
    this.hint('关闭流式后，答案完整返回再显示；当前原生工具调用需要兼容 API 和流式输出。参数上限仍受模型服务限制。')
    Row() {
      Text('启用语义检索').fontSize(14).fontColor(this.palette().inkPrimary).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.semanticSearch }).onChange((v: boolean) => { this.semanticSearch = v; this.changed(); })
    }.height(48).width('100%')
    if (this.semanticSearch) {
      this.field('向量模型 ID', () => this.embeddingId, '服务支持的 embedding 模型', (v: string) => { this.embeddingId = v; })
    }
    this.hint('默认使用本地关键词检索。开启语义检索会把资料库笔记片段发送到所配向量服务；服务不支持或失败时回退本地检索。')
    Text('附加系统提示词').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
    TextArea({ text: this.systemPrompt, placeholder: '例如：先给结论，再列出资料依据；使用中文。' }).height(180).fontSize(14)
      .backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkPrimary)
      .onChange((v: string) => { this.systemPrompt = v; this.changed(); })
  }

  @Builder
  tools() {
    ForEach(ACCESS_OPTIONS, (option: AccessOption) => {
      Button(option.label).height(48).width('100%')
        .backgroundColor(this.toolAccess === option.value ? this.palette().accent : this.palette().surfaceSubtle)
        .fontColor(this.toolAccess === option.value ? Color.White : this.palette().inkSecondary)
        .onClick(() => { this.toolAccess = option.value; this.changed(); })
    }, (option: AccessOption) => option.value)
    this.field('工具循环上限 · 1–6 轮', () => this.rounds, '5', (v: string) => { this.rounds = v; })
    this.hint('读取资料无需确认。创建待办、修改标签、建立双链、移动分类和新建笔记，每次写入前均需确认。Gemini / Anthropic 当前仅支持文本回答与手动采纳方案。')
    ForEach(AGENT_TOOLS, (tool: AgentToolSpec) => {
      Row({ space: 10 }) {
        Text(tool.permission === 'read' ? '读取' : '写入').fontSize(11).fontColor(this.palette().inkMuted).width(32)
        Column({ space: 4 }) {
          Text(toolDisplayName(tool.name)).fontSize(14).fontColor(this.palette().inkPrimary)
          Text(tool.description).fontSize(12).fontColor(this.palette().inkSecondary)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%').padding(10).borderRadius(8).backgroundColor(this.palette().surfaceSubtle)
    }, (tool: AgentToolSpec) => tool.name)
  }

  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('模型与 AI 工具').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
          Button('✕').height(44).width(44).enabled(!this.busy).accessibilityText('关闭模型设置').onClick(() => this.requestClose())
        }.width('100%')
        Scroll() {
          Row({ space: 8 }) {
            ForEach(this.profiles, (p: ModelProfile) => {
              Button(`${p.id === this.activeId ? '● ' : ''}${p.label}`).height(44).fontSize(12)
                .backgroundColor(this.currentId === p.id ? this.palette().accent : this.palette().surfaceSubtle)
                .fontColor(this.currentId === p.id ? Color.White : this.palette().inkPrimary).onClick(() => this.switchProfile(p))
            }, (p: ModelProfile) => p.id)
            Button('+ 档案').height(44).onClick(() => this.add())
          }.enabled(!this.busy)
        }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        Row({ space: 8 }) {
          ForEach(['连接', '输出', '工具'], (name: string, index: number) => {
            Button(name).height(44).layoutWeight(1).fontSize(14)
              .backgroundColor(this.tab === index ? this.palette().surfaceSubtle : Color.Transparent)
              .fontColor(this.tab === index ? this.palette().inkPrimary : this.palette().inkMuted).onClick(() => { this.tab = index; })
          }, (name: string) => name)
        }.width('100%')
        Scroll() {
          Column({ space: 14 }) {
            if (this.tab === 0) { this.connection() } else if (this.tab === 1) { this.output() } else { this.tools() }
            if (this.profiles.length > 1) {
              Button('删除当前档案').height(44).width('100%').onClick(() => { this.deleteWarning = true; })
            }
          }.width('100%').alignItems(HorizontalAlign.Start).enabled(!this.busy)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
        if (this.feedback.length > 0) {
          Text(this.feedback).fontSize(12).lineHeight(18).width('100%').fontColor(this.feedbackError ? this.palette().danger : this.palette().inkSecondary)
        }
        if (this.deleteWarning) {
          Row({ space: 8 }) {
            Button('确认删除档案').height(44).layoutWeight(1).enabled(!this.busy).onClick(() => this.remove())
            Button('取消').height(44).layoutWeight(1).onClick(() => { this.deleteWarning = false; })
          }.width('100%')
        }
        if (this.closeWarning) {
          this.hint('还有未保存的配置。可以切回对应档案保存，或放弃本次修改后关闭。')
          Row({ space: 8 }) {
            Button('继续编辑').height(44).layoutWeight(1).onClick(() => { this.closeWarning = false; })
            Button('放弃修改并关闭').height(44).layoutWeight(1).onClick(() => this.onClose())
          }.width('100%')
        } else {
          Row({ space: 8 }) {
            Button(this.busy ? '处理中…' : '测试连接').height(48).layoutWeight(1).enabled(!this.busy).onClick(() => this.test())
              .backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkPrimary)
            Button('保存并启用').height(48).layoutWeight(1).enabled(!this.busy).onClick(() => this.save())
          }.width('100%')
        }
      }.width(this.phone ? '100%' : '92%').constraintSize({ maxWidth: 700 }).height(this.phone ? '100%' : '90%')
        .padding(this.phone ? 16 : 24).borderRadius(this.phone ? 0 : 16).backgroundColor(this.palette().surface).onClick(() => {})
    }.width('100%').height('100%').alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
      .backgroundColor('rgba(0,0,0,0.36)')
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
      .onClick(() => this.requestClose())
  }
}
