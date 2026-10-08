import { common } from '@kit.AbilityKit';
import { AnimationTokens, ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { ModelProfile, ModelPresetTemplate, ProviderProtocol, getPresetTemplates, createDefaultProfile } from '../../common/types/ModelConfig';
import { ModelConfigService } from '../../services/ai/ModelConfigService';
import { ModelProfilePolicy } from '../../services/ai/ModelProfilePolicy';
import { RemoteAiPolicy } from '../../services/ai/RemoteAiPolicy';
import { createProvider } from '../../services/ai/ModelProvider';
import { AGENT_TOOLS, toolDisplayName } from '../../services/ai/ToolRegistry';
import { AgentToolSpec } from '../../common/types/AgentTypes';
import { AssistantModeService, ASSISTANT_MODE_KEY } from '../../services/ai/AssistantModeService';
import { REMOTE_AI_ENABLED } from '../../common/constants/RuntimeCapabilities';
import { IconButton } from '../common/IconButton';

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
  @Prop embedded: boolean = false;
  onClose: () => void = () => {};
  @Prop @Watch('requestClose') closeToken: number = 0;
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @StorageProp(ASSISTANT_MODE_KEY) assistantMode: string = 'local';
  @State profiles: ModelProfile[] = [];
  @State currentId: string = '';
  @State activeId: string = '';
  @State tab: number = 0;
  @State sourceTab: number = 0;
  @State advancedSection: number = -1;
  @State showConsentDetails: boolean = false;
  @State showToolList: boolean = false;
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
  @State remoteConsent: boolean = false;
  private consentEndpoint: string = '';
  private consentProtocol: ProviderProtocol = 'openai-compat';
  private credentialUnavailable: boolean = false;
  @State feedback: string = '';
  @State feedbackError: boolean = false;
  @State closeWarning: boolean = false;
  @State deleteWarning: boolean = false;
  @State resetWarning: boolean = false;
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
      await AssistantModeService.getInstance().init(getContext(this) as common.UIAbilityContext);
      this.sourceTab = this.assistantMode === 'remote' ? 1 : 0;
      if (!REMOTE_AI_ENABLED) { this.sourceTab = 0; return; }
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
    this.remoteConsent = RemoteAiPolicy.consented(p);
    this.consentEndpoint = RemoteAiPolicy.endpoint(p.baseUrl); this.consentProtocol = p.protocol;
    this.credentialUnavailable = p.credentialUnavailable === true;
    this.temperature = `${p.temperature}`; this.maxTokens = `${p.maxTokens}`; this.stream = p.stream;
    this.systemPrompt = p.systemPrompt; this.toolAccess = p.toolAccess || 'confirm-write'; this.rounds = `${p.maxToolRounds || 5}`;
    this.showKey = false; this.changed();
    if (this.credentialUnavailable) { this.report('此设备无法读取旧密钥，请重新填写。其他配置已保留。', true); }
  }

  private form(): ModelProfile {
    const previous = this.profiles.find((p: ModelProfile) => p.id === this.currentId);
    const allowed = this.remoteConsent && this.consentEndpoint === RemoteAiPolicy.endpoint(this.baseUrl) && this.consentProtocol === this.protocol;
    return { id: this.currentId, label: this.label.trim(), protocol: this.protocol,
      baseUrl: this.baseUrl.trim().replace(/\/+$/, ''), apiKey: this.apiKey.trim(), modelId: this.modelId.trim(),
      embeddingModelId: this.embeddingId.trim(), temperature: Number(this.temperature), maxTokens: Number(this.maxTokens),
      semanticSearch: this.semanticSearch,
      credentialUnavailable: this.credentialUnavailable && !this.apiKey.trim(),
      remoteConsentVersion: allowed ? RemoteAiPolicy.VERSION : undefined,
      remoteConsentEndpoint: allowed ? this.consentEndpoint : undefined,
      remoteConsentProtocol: allowed ? this.consentProtocol : undefined,
      remoteConsentedAt: allowed ? previous?.remoteConsentedAt || Date.now() : undefined,
      stream: this.stream, systemPrompt: this.systemPrompt, toolAccess: this.toolAccess, maxToolRounds: Number(this.rounds),
      isReasoningModel: previous?.isReasoningModel, thinkingBudget: previous?.thinkingBudget,
      createdAt: this.createdAt, updatedAt: previous?.updatedAt || this.createdAt };
  }

  private signature(p: ModelProfile): string {
    const clone = JSON.parse(JSON.stringify(p)) as ModelProfile;
    clone.updatedAt = 0;
    clone.credentialRef = undefined; clone.credentialUnavailable = undefined;
    clone.remoteConsentedAt = clone.remoteConsentVersion ? 1 : undefined;
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

  private profileOptions(): SelectOption[] {
    return this.profiles.map((p: ModelProfile) => {
      const option: SelectOption = { value: `${p.id === this.activeId ? '当前 · ' : ''}${p.label}` };
      return option;
    });
  }

  private async useLocal(): Promise<void> {
    this.busy = true;
    try { await AssistantModeService.getInstance().setMode('local'); this.report('已启用本地助手'); }
    catch { this.report('助手设置保存失败，请重试', true); }
    finally { this.busy = false; }
  }

  private requestClose(): void {
    if (this.busy) { return; }
    if (!this.currentId) { this.onClose(); return; }
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
      await AssistantModeService.getInstance().setMode(RemoteAiPolicy.consented(p) ? 'remote' : 'local');
      if (!this.alive) { return; }
      const pending = this.profiles.filter((item: ModelProfile) => this.newProfiles.has(item.id) && item.id !== p.id);
      this.profiles = saved.concat(pending); this.activeId = p.id; this.drafts.delete(p.id); this.newProfiles.delete(p.id); this.fill(saved.find((item: ModelProfile) => item.id === p.id) || p);
      this.report(RemoteAiPolicy.consented(p) ? '模型已保存并启用' : '配置已保存，当前使用本地助手。授权后可启用模型。');
    } catch { this.report('保存失败，输入已保留，请重试', true); }
    finally { this.busy = false; }
  }

  private async test(): Promise<void> {
    if (this.busy) { return; }
    const p = this.form(); const error = ModelProfilePolicy.validate(p);
    if (error) { this.report(error, true); return; }
    try { RemoteAiPolicy.assertAllowed(p); } catch (e) { this.report((e as Error).message, true); return; }
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
  private async clearKey(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      await ModelConfigService.getInstance().clearCredentials(this.currentId || undefined);
      this.apiKey = ''; this.remoteConsent = false; this.credentialUnavailable = false;
      const pending = this.profiles.filter((p: ModelProfile) => this.newProfiles.has(p.id));
      this.profiles = (await ModelConfigService.getInstance().loadProfiles()).concat(pending);
      this.drafts.delete(this.currentId);
      if (!this.currentId) { this.fill(this.profiles[0]); }
      this.report('已移除本机密钥并撤销此服务授权。进行中的请求请在原页面停止。');
    } catch { this.report('密钥移除未完成，请重试并在重启后核对', true); }
    finally { this.busy = false; }
  }
  private async resetModels(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    try {
      await ModelConfigService.getInstance().resetProfiles();
      await AssistantModeService.getInstance().setMode('local');
      this.drafts.clear(); this.newProfiles.clear(); this.profiles = await ModelConfigService.getInstance().loadProfiles();
      this.activeId = this.profiles[0].id; this.fill(this.profiles[0]); this.resetWarning = false;
      this.report('模型档案已重置，填写服务后可重新授权。');
    } catch { this.report('重置未完成，请重启后核对', true); }
    finally { this.busy = false; }
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
    this.hint('可选。授权后将资料发往你配置的服务。')
    this.field('档案名称', () => this.label, '例如：学习助手', (v: string) => { this.label = v; })
    this.field('服务地址', () => this.baseUrl, 'https://…', (v: string) => {
      if (v.split('/')[2] !== this.baseUrl.split('/')[2]) { this.apiKey = ''; }
      this.baseUrl = v;
      if (RemoteAiPolicy.endpoint(v) !== this.consentEndpoint) { this.remoteConsent = false; }
    })
    this.hint(this.protocol === 'gemini' ? 'Gemini 地址应含 API 版本，例如 /v1beta。' : this.protocol === 'anthropic' ? '填写服务根地址，程序追加 /v1/messages。' : '填写兼容 API 的根地址（通常以 /v1 结尾），程序追加 /chat/completions。')
    Row({ space: 8 }) {
      TextInput({ text: this.apiKey, placeholder: 'API Key' }).type(this.showKey ? InputType.Normal : InputType.Password)
        .height(48).layoutWeight(1).fontSize(14).backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkPrimary)
        .onChange((v: string) => { this.apiKey = v; this.credentialUnavailable = false; this.changed(); })
      Button(this.showKey ? '隐藏' : '显示').width(64).height(44).onClick(() => { this.showKey = !this.showKey; })
    }.width('100%')
    this.field('模型 ID', () => this.modelId, '服务商控制台中的实际 ID', (v: string) => { this.modelId = v; })
    this.hint('密钥使用系统密钥保护加密保存。远程地址需为 HTTPS，本机 HTTP 仅允许无密钥服务。')
    Column({ space: 8 }) {
      Text('可选的数据发送授权').fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
      this.hint('测试会发送测试文字；问答、智能整理和题卡会发送问题、对话与所选资料。语义检索还会发送资料库文字片段。费用及留存规则由服务商决定。')
      Row({ space: 8 }) {
        Checkbox({ name: 'remoteAiConsent' }).select(this.remoteConsent).onChange((value: boolean) => {
          this.remoteConsent = value; this.consentEndpoint = RemoteAiPolicy.endpoint(this.baseUrl); this.consentProtocol = this.protocol; this.changed();
        }).accessibilityText('同意向此模型服务发送上述数据')
        Text('同意向此服务发送上述数据').fontSize(14).fontColor(this.palette().inkPrimary).layoutWeight(1)
      }.width('100%')
      Button(this.showConsentDetails ? '收起说明' : '查看发送与撤销说明').height(44).width('100%').type(ButtonType.Normal)
        .backgroundColor(Color.Transparent).fontColor(this.palette().inkSecondary).onClick(() => { this.showConsentDetails = !this.showConsentDetails; })
      if (this.showConsentDetails) {
        Text(RemoteAiPolicy.endpoint(this.baseUrl) || '请先填写服务地址').fontSize(12).fontColor(this.palette().inkPrimary).width('100%')
        this.hint('密钥仅用于此服务鉴权，使用前请阅读其隐私规则。默认关闭，保存后生效；更改地址或协议需重新确认。拒绝仍可使用本地学习功能。撤销请取消勾选并保存，进行中的请求可在原页面停止。')
      }
    }.width('100%').padding(12).borderRadius(10).backgroundColor(this.palette().surfaceSubtle)
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
    Button(this.showToolList ? '收起工具清单' : `查看 ${AGENT_TOOLS.length} 项工具`).height(44).width('100%')
      .type(ButtonType.Normal).backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkSecondary)
      .onClick(() => { this.showToolList = !this.showToolList; })
    if (this.showToolList) {
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
  }

  @Builder
  advanced() {
    this.hint('默认参数即可开始使用。需要时再调整输出、工具权限或连接协议。')
    ForEach(['输出与检索', '工具权限', '连接与档案管理'], (name: string, index: number) => {
      Button(`${name}  ${this.advancedSection === index ? '−' : '+'}`).height(48).width('100%')
        .type(ButtonType.Normal).borderRadius(8).backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkPrimary)
        .onClick(() => { this.advancedSection = this.advancedSection === index ? -1 : index; })
      if (this.advancedSection === index) {
        if (index === 0) { this.output() }
        else if (index === 1) { this.tools() }
        else {
          Row({ space: 6 }) {
            ForEach(PROTOCOLS, (p: ProtocolOption) => {
              Button(p.label).height(44).layoutWeight(1).fontSize(12)
                .backgroundColor(this.protocol === p.value ? this.palette().accent : this.palette().surfaceSubtle)
                .fontColor(this.protocol === p.value ? Color.White : this.palette().inkSecondary)
                .onClick(() => { if (this.protocol !== p.value) { this.remoteConsent = false; } this.protocol = p.value; this.changed(); })
            }, (p: ProtocolOption) => p.value)
          }.width('100%')
          this.hint('改变协议后请在“连接”页核对地址，并重新确认发送授权。')
          ForEach(getPresetTemplates(), (p: ModelPresetTemplate) => {
            Button(`填入模版 · ${p.name}`).height(44).width('100%').fontSize(13).type(ButtonType.Normal)
              .backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkPrimary).onClick(() => { this.preset(p); this.tab = 0; })
          }, (p: ModelPresetTemplate) => p.name)
          Button(this.currentId ? '移除此档案的本机密钥' : '移除旧配置的全部本机密钥').height(44).width('100%').onClick(() => this.clearKey())
          if (this.profiles.length > 1) {
            Button('删除当前档案').height(44).width('100%').onClick(() => { this.deleteWarning = true; })
          }
          Button('重置模型配置').height(44).width('100%').onClick(() => { this.resetWarning = true; })
          if (this.resetWarning) {
            this.hint('删除全部模型档案、发送授权和本机密钥，需要重新配置。笔记、PDF、待办与复习资料保留。')
            Row({ space: 8 }) {
              Button('确认重置').height(44).layoutWeight(1).onClick(() => this.resetModels())
              Button('取消').height(44).layoutWeight(1).onClick(() => { this.resetWarning = false; })
            }.width('100%')
          }
        }
      }
    }, (name: string) => name)
  }

  build() {
    Column() {
      Column({ space: 12 }) {
        Row() {
          Text('助手设置').fontSize(20).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
          IconButton({ icon: $r('app.media.ic_back'), label: '返回设置', available: !this.busy, onAction: () => this.requestClose() })
        }.width('100%')
        Row({ space: 8 }) {
          ForEach(['本地助手', '自配 API', '云 AI'], (name: string, index: number) => {
            Button(name).height(44).layoutWeight(1).fontSize(14)
              .type(ButtonType.Normal).borderRadius(8)
              .backgroundColor(this.sourceTab === index ? this.palette().accentSoft : this.palette().surfaceSubtle)
              .fontColor(this.sourceTab === index ? this.palette().accent : this.palette().inkSecondary)
              .enabled(!this.busy).onClick(() => { this.sourceTab = index; })
          }, (name: string) => name)
        }.width('100%')
        if (this.sourceTab === 1) {
          Row({ space: 8 }) {
            Select(this.profileOptions()).selected(Math.max(0, this.profiles.findIndex((p: ModelProfile) => p.id === this.currentId)))
              .value(this.label || '模型档案').layoutWeight(1).height(48).font({ size: 14 }).fontColor(this.palette().inkPrimary)
              .backgroundColor(this.palette().surfaceSubtle).enabled(!this.busy).accessibilityText('选择模型档案')
              .onSelect((index: number) => { if (this.profiles[index]) { this.switchProfile(this.profiles[index]); } })
            Button('+ 新建').height(44).fontSize(13).enabled(!this.busy).type(ButtonType.Normal).borderRadius(8)
              .backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkPrimary).onClick(() => this.add())
          }.width('100%')
          Row({ space: 8 }) {
            ForEach(['连接', '高级'], (name: string, index: number) => {
              Button(name).height(44).layoutWeight(1).fontSize(13).type(ButtonType.Normal).borderRadius(8)
                .backgroundColor(this.tab === index ? this.palette().surfaceSubtle : Color.Transparent)
                .fontColor(this.tab === index ? this.palette().inkPrimary : this.palette().inkMuted).onClick(() => { this.tab = index; })
            }, (name: string) => name)
          }.width('100%')
        }
        Scroll() {
          Column({ space: 14 }) {
            if (this.sourceTab === 0) {
              Text('离线可用').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
              this.hint('原文检索、要点摘录、待办整理与资料概览，无需账号或密钥。')
              this.hint('按原文与规则整理，结果可回到来源核对。')
              Button('使用指引').height(44).width('100%').onClick(() => {
                this.report('先新建或导入资料，在墨客引用笔记后选择用法。PDF 需先提取并校对文字。');
              })
            } else if (this.sourceTab === 2) {
              Text('云 AI 暂未开放').fontSize(18).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
              this.hint('当前没有团队云服务。你可以离线使用本地助手，或配置自己的模型 API。')
            } else if (this.tab === 0) { this.connection() } else { this.advanced() }
          }.width('100%').alignItems(HorizontalAlign.Start).enabled(!this.busy)
        }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
        if (this.feedback.length > 0) {
          Text(this.feedback).fontSize(12).lineHeight(18).width('100%').fontColor(this.feedbackError ? this.palette().danger : this.palette().inkSecondary)
        }
        if (this.deleteWarning && this.sourceTab === 1) {
          Row({ space: 8 }) {
            Button('确认删除档案').height(44).layoutWeight(1).enabled(!this.busy).onClick(() => this.remove())
            Button('取消').height(44).layoutWeight(1).onClick(() => { this.deleteWarning = false; })
          }.width('100%')
        }
        if (this.closeWarning) {
          this.hint('还有未保存的配置。可以切回对应档案保存，或放弃本次修改后关闭。')
          Row({ space: 8 }) {
            Button('继续编辑').height(44).layoutWeight(1).onClick(() => { this.closeWarning = false; this.sourceTab = 1; })
            Button('放弃修改并关闭').height(44).layoutWeight(1).onClick(() => this.onClose())
          }.width('100%')
        } else if (this.sourceTab === 0) {
          Button(this.assistantMode === 'local' ? '本地助手已启用' : '使用本地助手').height(48).width('100%').enabled(!this.busy)
            .type(ButtonType.Normal).borderRadius(10).backgroundColor(this.palette().accent).fontColor(Color.White).onClick(() => this.useLocal())
        } else if (this.sourceTab === 2) {
          Button('暂未开放').height(48).width('100%').enabled(false).backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkMuted)
        } else {
          Row({ space: 8 }) {
            Button(this.busy ? '处理中…' : '测试连接').height(48).layoutWeight(1).enabled(!this.busy).onClick(() => this.test())
              .backgroundColor(this.palette().surfaceSubtle).fontColor(this.palette().inkPrimary)
            Button('保存并启用').height(48).layoutWeight(1).enabled(!this.busy).onClick(() => this.save())
          }.width('100%')
        }
      }.width(this.embedded ? '100%' : '92%').constraintSize({ maxWidth: 760 }).height(this.embedded ? '100%' : '90%')
        .padding(this.phone ? 16 : 24).borderRadius(20).backgroundColor(this.palette().surface).onClick(() => {})
    }.width('100%').height('100%').alignItems(HorizontalAlign.Center).justifyContent(FlexAlign.Center)
      .backgroundColor(this.embedded ? Color.Transparent : 'rgba(0,0,0,0.36)')
      .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_FAST, curve: Curve.EaseInOut }))
      .onClick(() => this.requestClose())
  }
}
