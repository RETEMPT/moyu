import { unifiedDataChannel, uniformDataStruct, uniformTypeDescriptor } from '@kit.ArkData';
import { AnimationTokens, ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { LearningCitation } from '../../common/types/LearningResult';
import { NoteItem } from '../../common/types/NoteItem';
import { LearningResultPolicy } from '../../services/study/LearningResultPolicy';
import { StudyAssistantGateway, StudyChatMessage, StudyGatewayModel, StudyGatewaySelection, StudyRunStep, StudyWebSource, studyChatContext } from '../../services/study/StudyAssistantGateway';
import { StudyChatEvidence, StudyWorkspaceLocation, StudyWorkspaceRequest, StudyWorkspaceResult, StudyWorkspaceSources } from '../../services/study/StudyWorkspaceSources';
import { AppIcon } from '../common/AppIcon';
import { DocumentText } from '../common/DocumentText';
import { IconButton } from '../common/IconButton';
import { STUDY_ACCENT, StudyGroundedContent, StudyReference, StudyReferencePane, StudyRunTrace, StudyWebSources } from './StudyWorkspacePanels';

interface StudyConversation {
  id: string;
  messages: StudyChatMessage[];
  draft: string;
  evidence?: StudyChatEvidence[];
  attachments?: string[];
  name?: string;
  workspaceId?: string;
}

export interface StudyConversationGroup { id: string; name: string; }

export interface StudyChatHistory {
  conversation: StudyConversation;
  history: StudyConversation[];
  workspaces?: StudyConversationGroup[];
}

export interface StudyChatSession extends StudyChatHistory, StudyGatewaySelection {}

interface StudyAction {
  label: string;
  onAction: () => void;
  enabled: boolean;
  primary: boolean;
}

export function withStudyGatewaySelection(session: StudyChatSession, selection: StudyGatewaySelection): StudyChatSession {
  return { pairingCode: selection.pairingCode, models: selection.models, model: selection.model,
    conversation: session.conversation, history: session.history, workspaces: session.workspaces };
}

@Component
export struct StudyChatWorkspace {
  @Link session: StudyChatSession;
  @Prop @Watch('reconcileSources') notes: NoteItem[] = [];
  @Prop importing: boolean = false;
  @Prop canGoBack: boolean = false;
  @Prop @Watch('closeReference') referenceCloseToken: number = 0;
  onBack: () => void = () => {};
  onOpenNavigation: () => void = () => {};
  onOpenLearning: () => void = () => {};
  onOpenLibrary: () => void = () => {};
  onImport: (uris: string[], limit: number) => Promise<NoteItem[]> = async () => [];
  onExtract: (id: string, start: number, end: number, cancelled: () => boolean) => Promise<void> = async () => {};
  onReferenceChange: (open: boolean) => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') style: string = 'mono';
  @StorageProp('flowmindIsPhone') phone: boolean = false;
  @StorageProp('flowmindStudyPreview') studyPreview: boolean = false;
  @State private available: boolean = false;
  @State private connecting: boolean = false;
  @State private sending: boolean = false;
  @State private code: string = '';
  @State private status: string = '';
  @State private pendingQuestion: string = '';
  @State private showConnection: boolean = false;
  @State private historyToggle: boolean = false;
  @State private addOpen: boolean = false;
  @State private libraryOpen: boolean = false;
  @State private sourceSearch: string = '';
  @State private attaching: boolean = false;
  @State private dropping: boolean = false;
  @State private extractingId: string = '';
  @State private rangeId: string = '';
  @State private rangeStart: string = '1';
  @State private rangeEnd: string = '1';
  @State private viewport: number = 0;
  @State private staged: StudyWorkspaceRequest | null = null;
  @State private activeTrace: StudyRunStep[] = [];
  @State private effort: string = 'low';
  @State private effortMenu: boolean = false;
  @State private webEnabled: boolean = false;
  @State private stopped: boolean = false;
  @State private reference: StudyReference | null = null;
  @State private menuKey: string = '';
  @State private editorKind: string = '';
  @State private editorTarget: string = '';
  @State private editorName: string = '';
  @State private editorError: string = '';
  @State private collapsedGroups: string[] = [];
  private referenceRevision: number = 0;
  private retryRequest: StudyWorkspaceRequest | null = null;
  private retryWeb: boolean = false;
  private alive: boolean = false;
  private generation: number = 0;
  private gateway: StudyAssistantGateway = new StudyAssistantGateway();
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.alive = true;
    if (this.studyPreview) {
      this.reconcileSources();
      StudyAssistantGateway.enabled().then((enabled: boolean) => { if (this.alive) { this.available = enabled; } });
    }
  }

  aboutToDisappear(): void {
    this.alive = false;
    this.generation++;
    this.gateway.cancel();
    this.closeReference();
    if (this.pendingQuestion) { this.setDraft(this.pendingQuestion); }
  }

  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.dark, this.style); }

  private wide(): boolean { return this.viewport >= 840; }

  private modelLabel(): string {
    return this.selectedModel()?.label || '连接网关';
  }

  private selectedModel(): StudyGatewayModel | undefined {
    return this.session.models.find((item: StudyGatewayModel) => item.id === this.session.model);
  }

  private busy(): boolean {
    return this.sending || this.connecting || this.attaching || this.importing || this.extractingId.length > 0;
  }

  private attachmentIds(): string[] { return this.session.conversation.attachments || []; }

  private selectedSources(): NoteItem[] {
    return this.notes.filter((note: NoteItem) => !note.deletedAt && this.attachmentIds().includes(note.id));
  }

  private replaceAttachments(ids: string[]): void {
    const current = this.session.conversation;
    this.replaceConversation({ id: current.id, messages: current.messages, draft: current.draft,
      evidence: current.evidence, attachments: ids, name: current.name, workspaceId: current.workspaceId });
    this.staged = null;
    if (ids.length) { this.webEnabled = false; }
  }

  private reconcileSources(): void {
    if (this.reference && !this.referenceNote()) { this.closeReference(); }
    const ids = this.attachmentIds();
    const live = this.selectedSources().map((note: NoteItem) => note.id);
    if (live.length !== ids.length) { this.replaceAttachments(ids.filter((id: string) => live.includes(id))); }
  }

  private toggleAttachment(note: NoteItem): void {
    if (this.busy()) { return; }
    const ids = this.attachmentIds();
    if (ids.includes(note.id)) {
      this.replaceAttachments(ids.filter((id: string) => id !== note.id));
      if (this.rangeId === note.id) { this.rangeId = ''; }
    } else if (ids.length < StudyWorkspaceSources.MAX_NOTES) {
      this.replaceAttachments(ids.concat(note.id));
    } else { this.status = '每个对话最多添加 12 份附件'; return; }
    this.status = '';
  }

  private async attachFiles(uris: string[] = []): Promise<void> {
    if (this.busy() || this.pendingQuestion || this.staged) { return; }
    const remaining = StudyWorkspaceSources.MAX_NOTES - this.attachmentIds().length;
    if (remaining <= 0) { this.status = '每个对话最多添加 12 份附件'; return; }
    this.addOpen = false;
    this.libraryOpen = false;
    this.status = '';
    this.attaching = true;
    const conversationId = this.session.conversation.id;
    try {
      const imported = await this.onImport(uris, remaining);
      if (this.session.conversation.id === conversationId && imported.length > 0) {
        this.replaceAttachments(this.attachmentIds().concat(imported.map((note: NoteItem) => note.id)));
      }
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '无法添加附件'; } }
    finally { if (this.alive) { this.attaching = false; } }
  }

  private dropFiles(event: DragEvent): void {
    this.dropping = false;
    if (this.busy() || this.pendingQuestion || this.staged) { return; }
    try {
      const files: string[] = [];
      for (const record of event.getData().getRecords()) {
        const type = record.getType();
        let uri = '';
        if (type === uniformTypeDescriptor.UniformDataType.FILE_URI) {
          uri = (record.getValue() as uniformDataStruct.FileUri)?.oriUri || '';
        } else if (type === uniformTypeDescriptor.UniformDataType.FILE) {
          uri = (record as unifiedDataChannel.File).uri || '';
        }
        if (uri.startsWith('file://')) { files.push(uri); }
      }
      if (files.length) { this.attachFiles(files); }
      else { this.status = '请拖入文件，或点「＋」从设备添加'; }
    } catch { this.status = '无法读取拖入的文件，请点「＋」重新选择'; }
  }

  private showPdfRange(note: NoteItem): void {
    this.rangeId = this.rangeId === note.id ? '' : note.id;
    this.rangeStart = '1';
    this.rangeEnd = String(Math.min(8, note.pageCount || 1));
    this.status = '';
  }

  private async extract(note: NoteItem): Promise<void> {
    if (this.busy()) { return; }
    const start = Number(this.rangeStart);
    const end = Number(this.rangeEnd);
    if (!Number.isInteger(start) || !Number.isInteger(end) || start < 1 || end < start ||
      end > (note.pageCount || 1) || end - start >= 30) {
      this.status = '请在资料范围内选择连续的 1 至 30 页'; return;
    }
    this.extractingId = note.id;
    this.status = '';
    try {
      await this.onExtract(note.id, start, end, () => !this.alive);
      if (this.alive) { this.rangeId = ''; this.status = '已提取文字，可预览后发送'; }
    } catch (error) { if (this.alive) { this.status = (error as Error).message || '提取失败，可重试'; } }
    finally { if (this.alive) { this.extractingId = ''; } }
  }

  private toggleConnection(): void {
    if (this.sending || this.connecting) { return; }
    this.status = '';
    this.showConnection = !this.showConnection;
  }

  private replaceConversation(conversation: StudyConversation, history: StudyConversation[] = this.session.history,
    workspaces: StudyConversationGroup[] | undefined = this.session.workspaces): void {
    const session = this.session;
    this.session = { pairingCode: session.pairingCode, models: session.models, model: session.model, conversation, history, workspaces };
  }

  private setDraft(draft: string): void {
    const current = this.session.conversation;
    this.replaceConversation({ id: current.id, messages: current.messages, draft, evidence: current.evidence,
      attachments: current.attachments, name: current.name, workspaceId: current.workspaceId });
  }

  private title(conversation: StudyConversation): string {
    return conversation.name || (conversation.messages[0]?.content || conversation.draft).trim().replace(/\s+/g, ' ').slice(0, 36) || '新对话';
  }

  private moveTo(conversation: StudyConversation): void {
    if (this.sending || this.connecting || this.attaching || this.extractingId) { return; }
    let current = this.session.conversation;
    if (this.pendingQuestion) {
      current = { id: current.id, messages: current.messages, draft: this.pendingQuestion, evidence: current.evidence,
        attachments: current.attachments, name: current.name, workspaceId: current.workspaceId };
    }
    const history = this.session.history.filter((item: StudyConversation) => item.id !== conversation.id);
    if (current.id !== conversation.id && (current.messages.length || current.draft.trim() ||
      (current.attachments || []).length || current.name || current.workspaceId)) { history.unshift(current); }
    this.replaceConversation(conversation, history);
    this.pendingQuestion = '';
    this.retryRequest = null;
    this.webEnabled = false;
    this.staged = null;
    this.status = '';
    this.activeTrace = [];
    if (this.reference) { this.closeReference(); }
    if (!this.wide()) { this.historyToggle = false; }
    this.addOpen = false; this.libraryOpen = false; this.rangeId = '';
    this.reconcileSources();
    this.scrollBottom();
  }

  private emptyConversation(workspaceId: string = ''): StudyConversation {
    return { id: 'chat-' + Date.now() + '-' + Math.floor(Math.random() * 1000000), messages: [], draft: '', workspaceId };
  }

  private newConversation(workspaceId: string = ''): void {
    this.moveTo(this.emptyConversation(workspaceId));
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

  private stage(question: string): void {
    this.status = '';
    const active = this.reference;
    const attached = this.attachmentIds();
    const selected = attached.length || !active ? attached : [active.noteId];
    const sources = this.notes.filter((note: NoteItem) => !note.deletedAt && selected.includes(note.id));
    if (sources.some((note: NoteItem) => !StudyWorkspaceSources.hasText(note))) {
      this.status = '请先为附件提取文字，或移除无法使用的附件';
      return;
    }
    try {
      const plan = StudyWorkspaceSources.prepare(this.notes, selected, question, 'qa', active || undefined);
      const current = this.session.conversation;
      const history = StudyWorkspaceSources.dialogue(current.messages, current.evidence || [], plan)
        .map((message: StudyChatMessage): StudyChatMessage => ({ role: message.role, content: message.role === 'assistant' ?
        message.content.slice(0, 800).replace(/[\uD800-\uDBFF]$/, '') : message.content }));
      const context = studyChatContext(history, question, question.length + 2400, 4).slice(0, -1);
      if (context.length) { plan.request.context = context; }
      this.staged = plan;
      this.libraryOpen = false;
      this.addOpen = false;
    } catch (error) { this.status = (error as Error).message; }
  }

  private async send(confirmed: StudyWorkspaceRequest | null = null): Promise<void> {
    const current = this.session.conversation;
    const request = confirmed || this.retryRequest;
    const question = request?.request.goal || this.pendingQuestion || current.draft.trim();
    if (this.sending || this.connecting || this.attaching || this.extractingId || !question) { return; }
    if (!this.available || !this.session.model) { this.showConnection = true; return; }
    if (question.length > 1200) { this.status = '问题较长，请缩短后再发送'; return; }
    if (current.messages.length >= 100) { this.status = '本次对话已达 50 轮，可以新建对话'; return; }
    if (!request && !this.pendingQuestion && (this.attachmentIds().length || this.reference)) {
      this.stage(question);
      return;
    }
    this.staged = null;
    const model = this.session.models.find((item: StudyGatewayModel) => item.id === this.session.model);
    const effort = model?.reasoning ? this.effort : undefined;
    const web = !request && !!model?.webSearch && (this.pendingQuestion ? this.retryWeb : this.webEnabled);
    this.retryWeb = web;
    this.addOpen = false; this.libraryOpen = false; this.rangeId = '';
    this.retryRequest = request;
    this.sending = true;
    this.stopped = false;
    this.status = '';
    this.activeTrace = [];
    this.pendingQuestion = question;
    this.setDraft('');
    this.scrollBottom();
    const generation = ++this.generation;
    const onStep = (step: StudyRunStep, append?: boolean): void => {
      if (!this.alive || generation !== this.generation) { return; }
      const trace = this.activeTrace;
      const previous = trace[trace.length - 1];
      if (append && previous?.kind === 'reasoning' && previous.title === step.title) {
        this.activeTrace = trace.slice(0, -1).concat({ kind: step.kind, title: step.title,
          detail: (previous.detail + step.detail).slice(0, 9000) });
      } else if (trace.length < 24) {
        this.activeTrace = trace.concat(step);
      }
    };
    try {
      let evidence = current.evidence;
      let answer: string;
      let webSources: StudyWebSource[] | undefined = undefined;
      if (request) {
        const response = await this.gateway.generateAgent(request.request, this.session.pairingCode, this.session.model, onStep, effort);
        const entry: StudyWorkspaceResult = { result: response.result, locations: request.locations, tools: response.tools };
        answer = StudyWorkspaceSources.markdown(entry);
        evidence = (evidence || []).concat({ messageIndex: current.messages.length + 1, entry });
      } else {
        const generalHistory = evidence?.length ? StudyWorkspaceSources.dialogue(current.messages, evidence) : current.messages;
        const context = studyChatContext(generalHistory, question);
        if (web) {
          const response = await this.gateway.search(context, this.session.pairingCode, this.session.model, onStep, effort);
          answer = response.reply;
          webSources = response.sources;
        } else {
          answer = await this.gateway.chat(context, this.session.pairingCode, this.session.model, onStep, effort);
        }
      }
      if (!this.alive || generation !== this.generation) { return; }
      const turn: StudyChatMessage[] = [{ role: 'user', content: question },
        { role: 'assistant', content: answer, trace: this.activeTrace, webSources }];
      this.replaceConversation({ id: current.id, draft: '', messages: current.messages.concat(turn), evidence,
        attachments: current.attachments, name: current.name, workspaceId: current.workspaceId });
      this.pendingQuestion = '';
      this.retryRequest = null;
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
    this.retryRequest = null;
    this.status = '';
    this.activeTrace = [];
  }

  private stop(): void {
    this.generation++;
    this.gateway.cancel();
    this.stopped = true;
    this.sending = false;
  }

  private openCitation(entry: StudyWorkspaceResult, citation: LearningCitation): void {
    const linked = entry.locations.find((item: StudyWorkspaceLocation) => item.sourceId === citation.source_id);
    const note = this.notes.find((item: NoteItem) => item.id === linked?.noteId && !item.deletedAt);
    const location = note ? StudyWorkspaceSources.location(entry, citation, note) : undefined;
    if (note && location) {
      const line = location.pageNumber === undefined ? LearningResultPolicy.citationLine(entry.result, citation, location) : undefined;
      this.reference = { noteId: note.id, quote: citation.quote, revision: ++this.referenceRevision, page: location.pageNumber, line };
      this.webEnabled = false;
      this.staged = null;
      this.onReferenceChange(true);
    } else {
      this.status = '引用位置已变化';
    }
  }

  private referenceNote(): NoteItem | undefined {
    return this.notes.find((note: NoteItem) => !note.deletedAt && note.id === this.reference?.noteId);
  }

  private closeReference(): void {
    if (this.reference) { this.reference = null; this.staged = null; this.onReferenceChange(false); }
  }

  private groups(): StudyConversationGroup[] { return this.session.workspaces || []; }

  private groupChats(groupId: string): StudyConversation[] {
    const current = this.session.conversation;
    const history = current.messages.length || current.draft.trim() || this.attachmentIds().length || current.name || current.workspaceId ?
      [current].concat(this.session.history) : this.session.history;
    return history.filter((chat: StudyConversation) => {
      const id = chat.workspaceId && this.groups().some((group: StudyConversationGroup) => group.id === chat.workspaceId) ?
        chat.workspaceId : '';
      return id === groupId;
    });
  }

  private beginEditor(kind: string, id: string = '', name: string = ''): void {
    if (this.busy()) { return; }
    this.menuKey = '';
    this.editorKind = kind;
    this.editorTarget = id;
    this.editorName = name;
    this.editorError = '';
  }

  private changeChat(chat: StudyConversation, name: string | undefined, workspaceId: string | undefined): StudyConversation {
    return { id: chat.id, messages: chat.messages, draft: chat.draft, evidence: chat.evidence,
      attachments: chat.attachments, name, workspaceId };
  }

  private editChat(id: string, name?: string, groupId?: string): void {
    if (this.busy()) { return; }
    const current = this.session.conversation;
    const next = current.id === id ? this.changeChat(current, name ?? current.name, groupId ?? current.workspaceId) : current;
    const history = this.session.history.map((chat: StudyConversation) =>
      chat.id === id ? this.changeChat(chat, name ?? chat.name, groupId ?? chat.workspaceId) : chat);
    this.replaceConversation(next, history);
    this.editorKind = '';
  }

  private saveEditorName(): void {
    if (this.busy()) { return; }
    const name = this.editorName.trim().replace(/\s+/g, ' ');
    if (!name) { this.editorError = '请输入名称'; return; }
    if (this.editorKind === 'rename-chat') { this.editChat(this.editorTarget, name); return; }
    if (this.groups().some((group: StudyConversationGroup) => group.id !== this.editorTarget && group.name.toLowerCase() === name.toLowerCase())) {
      this.editorError = '已有同名工作区'; return;
    }
    const groups = this.editorKind === 'rename-group' ? this.groups().map((group: StudyConversationGroup): StudyConversationGroup =>
      group.id === this.editorTarget ? { id: group.id, name } : group) :
      this.groups().concat({ id: this.emptyConversation().id, name });
    this.replaceConversation(this.session.conversation, this.session.history, groups);
    this.editorKind = '';
  }

  private deleteEditorTarget(): void {
    if (this.busy()) { return; }
    const id = this.editorTarget;
    const current = this.session.conversation;
    if (this.editorKind === 'delete-chat') {
      const history = this.session.history.filter((chat: StudyConversation) => chat.id !== id);
      if (current.id === id) {
        this.pendingQuestion = ''; this.status = ''; this.activeTrace = [];
        this.retryRequest = null; this.staged = null; this.rangeId = '';
        this.closeReference();
      }
      this.replaceConversation(current.id === id ? this.emptyConversation() : current, history);
    } else if (this.editorKind === 'delete-group') {
      const groups = this.groups().filter((group: StudyConversationGroup) => group.id !== id);
      const next = current.workspaceId === id ? this.changeChat(current, current.name, '') : current;
      const history = this.session.history.map((chat: StudyConversation) =>
        chat.workspaceId === id ? this.changeChat(chat, chat.name, '') : chat);
      this.replaceConversation(next, history, groups);
      this.collapsedGroups = this.collapsedGroups.filter((groupId: string) => groupId !== id);
    }
    this.editorKind = '';
  }

  @Builder
  action($$: StudyAction) {
    Button($$.label, { type: ButtonType.Normal }).height(40).fontSize(13).borderRadius(20)
      .padding({ left: 12, right: 12 }).fontColor($$.primary ? Color.White : this.palette().inkPrimary)
      .backgroundColor($$.primary ? STUDY_ACCENT : this.palette().surfaceSubtle)
      .hoverEffect(HoverEffect.Highlight).enabled($$.enabled).onClick($$.onAction)
  }

  @Builder
  connection() {
    Column({ space: 8 }) {
      if (this.available) {
        Row({ space: 8 }) {
          TextInput({ text: this.code, placeholder: '输入配对码' }).height(44).layoutWeight(1).maxLength(32)
            .id('study-pairing-code')
            .type(InputType.Password).enabled(!this.connecting).fontColor(this.palette().inkPrimary)
            .backgroundColor(this.palette().surface).onChange((value: string) => { this.code = value; })
            .onSubmit(() => { this.connect(); })
          this.action({ label: this.connecting ? '连接中…' : '连接', onAction: () => { this.connect(); },
            enabled: !this.connecting, primary: true })
        }.width('100%')
        if (this.session.models.length > 0) {
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.session.models, (model: StudyGatewayModel) => {
                this.action({ label: model.label, onAction: () => {
                  this.session = withStudyGatewaySelection(this.session, {
                    pairingCode: this.session.pairingCode, models: this.session.models, model: model.id
                  });
                  this.showConnection = false;
                }, enabled: !this.connecting, primary: model.id === this.session.model })
              }, (model: StudyGatewayModel) => model.id)
            }
          }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto)
        }
      } else {
        Text('当前安装包未启用模拟器网关。请从项目目录运行 deploy_hap.bat -StudyDemo。')
          .width('100%').fontSize(14).fontColor(this.palette().inkPrimary).padding(4)
      }
    }.width('100%').padding(10).borderRadius(14).backgroundColor(this.palette().surfaceSubtle)
  }

  @Builder
  requestPreview(plan: StudyWorkspaceRequest) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('发送预览').fontSize(16).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary).layoutWeight(1)
        Text(this.modelLabel()).fontSize(12).fontColor(this.palette().inkSecondary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 150 })
      }.width('100%')
      Text(plan.request.goal).fontSize(14).fontColor(this.palette().inkPrimary).width('100%').maxLines(3)
      Scroll() {
        Column({ space: 10 }) {
          ForEach(plan.locations, (source: StudyWorkspaceLocation, index: number) => {
            Column({ space: 4 }) {
              Text((plan.request.focus?.source_id === source.sourceId ? '当前引用 · ' : '') + source.title +
                (source.pageNumber === undefined ? ' · 第 ' + source.line + ' 行' : ' · 第 ' + source.pageNumber + ' 页'))
                .fontSize(13).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).width('100%')
              Text(plan.request.sources[index].text).fontSize(13).lineHeight(20).fontColor(this.palette().inkSecondary).width('100%')
            }.width('100%').padding(8).borderRadius(10).backgroundColor(this.palette().surfaceSubtle)
          }, (source: StudyWorkspaceLocation) => source.sourceId)
          if (plan.request.context?.length) {
            Column({ space: 4 }) {
              Text('最近对话 · 用于理解追问').fontSize(13).fontWeight(FontWeight.Medium)
                .fontColor(this.palette().inkPrimary).width('100%')
              ForEach(plan.request.context, (message: StudyChatMessage) => {
                Text((message.role === 'user' ? '你 · ' : '助手 · ') + message.content)
                  .fontSize(13).lineHeight(20).fontColor(this.palette().inkSecondary).width('100%')
              }, (_message: StudyChatMessage, index: number) => String(index))
            }.width('100%').padding(8).borderRadius(10).backgroundColor(this.palette().surfaceSubtle)
          }
        }.width('100%')
      }.width('100%').constraintSize({ maxHeight: 144 }).align(Alignment.TopStart).scrollBar(BarState.Auto)
      Row({ space: 8 }) {
        Blank()
        this.action({ label: '取消', onAction: () => { this.staged = null; }, enabled: true, primary: false })
        this.action({ label: '确认发送', onAction: () => { this.send(plan); }, enabled: !this.busy(), primary: true })
      }.width('100%')
    }.width('100%').padding(12).borderRadius(16).backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().borderSubtle })
  }

  @Builder
  message(role: string, content: string, entry?: StudyWorkspaceResult, trace: StudyRunStep[] = [], webSources?: StudyWebSource[]) {
    Row() {
      if (role === 'user') {
        Blank()
        Text(content).fontSize(15).lineHeight(23).fontColor(this.palette().inkPrimary)
          .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
          .padding({ left: 15, right: 15, top: 11, bottom: 11 }).borderRadius(17)
          .constraintSize({ maxWidth: '84%' }).backgroundColor(this.dark ? '#2B4542' : '#E2F0EC')
      } else {
        Column({ space: 12 }) {
          Row({ space: 7 }) {
            Row() {
              AppIcon({ source: $r('app.media.ic_chat'), iconSize: 15, tint: Color.White })
            }.width(27).height(27).borderRadius(14).justifyContent(FlexAlign.Center).backgroundColor(STUDY_ACCENT)
            Text('墨客').fontSize(14).fontWeight(FontWeight.Bold).fontColor(this.palette().inkPrimary)
          }.width('100%')
          if (trace.length) { StudyRunTrace({ steps: trace }) }
          if (entry) {
            if (!trace.length && entry.tools?.length) {
              Text(entry.tools.map((tool: string) => tool === 'read_selected_source' ? '读取原文' : '检索附件').join(' · '))
                .fontSize(12).fontColor(this.palette().inkSecondary).width('100%')
            }
            StudyGroundedContent({ entry, onOpen: (answer: StudyWorkspaceResult, citation: LearningCitation) => this.openCitation(answer, citation) })
          } else {
            DocumentText({ text: content, allowLinks: false, chatLayout: true })
            if (webSources !== undefined) { StudyWebSources({ sources: webSources }) }
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ top: 15, bottom: 16, left: this.phone ? 14 : 18, right: this.phone ? 14 : 18 })
          .borderRadius(16).backgroundColor(this.palette().surface)
      }
    }.width('100%')
  }

  private evidenceAt(index: number): StudyWorkspaceResult | undefined {
    return this.session.conversation.evidence?.find((item: StudyChatEvidence) => item.messageIndex === index)?.entry;
  }

  @Builder
  transcript() {
    List({ space: 14, scroller: this.scroller }) {
      ForEach(this.session.conversation.messages, (message: StudyChatMessage, index: number) => {
        ListItem() { this.message(message.role, message.content, this.evidenceAt(index), message.trace || [], message.webSources) }
      }, (message: StudyChatMessage, index: number) => `${this.session.conversation.id}-${index}-${message.role}`)
      if (this.pendingQuestion) {
        ListItem() { this.message('user', this.pendingQuestion) }
        ListItem() {
          if (this.sending) {
            StudyRunTrace({ steps: this.activeTrace, active: true })
          } else {
            Column({ space: 6 }) {
              if (this.activeTrace.length) { StudyRunTrace({ steps: this.activeTrace, failed: !this.stopped, stopped: this.stopped }) }
              Text(this.stopped ? '已停止，可重新运行或修改问题' : this.status).fontSize(14)
                .fontColor(this.stopped ? this.palette().inkSecondary : this.palette().danger).width('100%')
              Row({ space: 6 }) {
                this.action({ label: '重试', onAction: () => { this.send(); }, enabled: !this.connecting, primary: false })
                this.action({ label: '修改问题', onAction: () => this.restoreQuestion(), enabled: true, primary: false })
              }.width('100%')
            }.width('100%')
          }
        }
      }
    }.width('100%').layoutWeight(1).scrollBar(BarState.Auto)
  }

  @Builder
  header() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        AppIcon({ source: $r('app.media.ic_menu'), iconSize: 20, tint: this.palette().inkPrimary })
      }.width(44).height(44).padding(0).borderRadius(8).backgroundColor(Color.Transparent)
        .id('study-session-toggle').accessibilityText('切换会话菜单')
        .onClick(() => { this.historyToggle = !this.historyToggle; })
      if (this.canGoBack) { IconButton({ icon: $r('app.media.ic_back'), label: '返回上一页', onAction: this.onBack }) }
      Text(this.session.conversation.messages.length ? this.title(this.session.conversation) : 'AI 墨客')
        .fontSize(19).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).layoutWeight(1)
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      this.action({ label: this.modelLabel(), onAction: () => this.toggleConnection(), enabled: !this.busy(), primary: false })
    }.width('100%').height(56).padding({ left: 12, right: 14 })
  }

  @Builder
  historyRow(conversation: StudyConversation, current: boolean) {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Text(this.title(current ? this.session.conversation : conversation)).fontSize(14).fontColor(this.palette().inkPrimary).width('100%')
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.layoutWeight(1).height(44).padding({ left: 12, right: 2 }).borderRadius(8).backgroundColor(Color.Transparent)
        .accessibilityDescription(current ? '当前会话' : '').enabled(!this.busy())
        .onClick(() => {
          if (!current) { this.moveTo(conversation); }
          else if (!this.wide()) { this.historyToggle = false; }
        })
      Button({ type: ButtonType.Normal }) {
        AppIcon({ source: $r('app.media.ic_more'), iconSize: 17, tint: this.palette().inkSecondary })
      }.width(44).height(44).padding(0).backgroundColor(Color.Transparent)
        .accessibilityText('会话操作 ' + this.title(current ? this.session.conversation : conversation)).enabled(!this.busy())
        .onClick(() => { this.menuKey = 'chat/' + conversation.id; })
        .bindMenu(this.menuKey === 'chat/' + conversation.id, this.chatMenu, { onDisappear: () => {
          if (this.menuKey === 'chat/' + conversation.id) { this.menuKey = ''; }
        } })
    }.width('100%').borderRadius(10).backgroundColor(current ? (this.dark ? '#2B4542' : '#E1EDE9') : Color.Transparent)
  }

  @Builder
  chatMenu() {
    Menu() {
      MenuItem({ content: '重命名会话' }).onClick(() => {
        const id = this.menuKey.substring(5);
        const chat = [this.session.conversation].concat(this.session.history).find((item: StudyConversation) => item.id === id);
        if (chat) { this.beginEditor('rename-chat', id, this.title(chat)); }
      })
      MenuItem({ content: '移动到工作区' }).onClick(() => this.beginEditor('move-chat', this.menuKey.substring(5)))
      MenuItem({ content: '删除会话' }).onClick(() => this.beginEditor('delete-chat', this.menuKey.substring(5)))
    }
  }

  @Builder
  groupMenu() {
    Menu() {
      MenuItem({ content: '在此新建对话' }).onClick(() => {
        const id = this.menuKey.substring(6);
        this.menuKey = '';
        this.collapsedGroups = this.collapsedGroups.filter((item: string) => item !== id);
        this.newConversation(id);
      })
      MenuItem({ content: '重命名工作区' }).onClick(() => {
        const id = this.menuKey.substring(6);
        const group = this.groups().find((item: StudyConversationGroup) => item.id === id);
        if (group) { this.beginEditor('rename-group', id, group.name); }
      })
      MenuItem({ content: '删除工作区' }).onClick(() => this.beginEditor('delete-group', this.menuKey.substring(6)))
    }
  }

  @Builder
  groupHeader(id: string, name: string) {
    Row() {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 7 }) {
          AppIcon({ source: $r('app.media.ic_folder'), iconSize: 17, tint: this.palette().inkSecondary })
          Text(name).fontSize(14).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary)
            .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(String(this.groupChats(id).length)).fontSize(11).fontColor(this.palette().inkSecondary)
        }.width('100%')
      }.layoutWeight(1).height(44).padding(8).backgroundColor(Color.Transparent)
        .accessibilityDescription(this.collapsedGroups.includes(id) ? '已收起' : '已展开').onClick(() => {
          this.collapsedGroups = this.collapsedGroups.includes(id) ? this.collapsedGroups.filter((item: string) => item !== id) :
            this.collapsedGroups.concat(id);
        })
      if (id) {
        Button({ type: ButtonType.Normal }) {
          AppIcon({ source: $r('app.media.ic_more'), iconSize: 17, tint: this.palette().inkSecondary })
        }.width(44).height(44).padding(0).backgroundColor(Color.Transparent).enabled(!this.busy())
          .accessibilityText('工作区操作 ' + name).onClick(() => { this.menuKey = 'group/' + id; })
          .bindMenu(this.menuKey === 'group/' + id, this.groupMenu, { onDisappear: () => {
            if (this.menuKey === 'group/' + id) { this.menuKey = ''; }
          } })
      }
    }.width('100%')
  }

  @Builder
  sessionEditor() {
    Column({ space: 6 }) {
      if (this.editorKind === 'move-chat') {
        Text('移动会话').fontSize(14).fontColor(this.palette().inkPrimary).width('100%')
        Scroll() {
          Column({ space: 2 }) {
            this.action({ label: '未分组', onAction: () => this.editChat(this.editorTarget, undefined, ''), enabled: !this.busy(), primary: false })
            ForEach(this.groups(), (group: StudyConversationGroup) => {
              this.action({ label: group.name,
                onAction: () => this.editChat(this.editorTarget, undefined, group.id), enabled: !this.busy(), primary: false })
            }, (group: StudyConversationGroup) => group.id)
          }.width('100%').alignItems(HorizontalAlign.Start)
        }.width('100%').constraintSize({ maxHeight: 155 }).scrollBar(BarState.Auto)
      } else if (this.editorKind === 'delete-chat' || this.editorKind === 'delete-group') {
        Text(this.editorKind === 'delete-chat' ? '删除这条本机会话？' : '删除工作区后，会话将移入未分组。')
          .fontSize(13).fontColor(this.palette().inkPrimary).width('100%')
      } else {
        Text(this.editorKind === 'create-group' ? '新建工作区' : this.editorKind === 'rename-group' ? '重命名工作区' : '重命名会话')
          .fontSize(14).fontColor(this.palette().inkPrimary).width('100%')
        TextInput({ text: this.editorName, placeholder: '名称' }).id('study-session-name').width('100%').height(42).maxLength(48)
          .onChange((value: string) => { this.editorName = value; this.editorError = ''; }).onSubmit(() => this.saveEditorName())
      }
      if (this.editorError) { Text(this.editorError).fontSize(12).fontColor(this.palette().danger).width('100%') }
      Row({ space: 5 }) {
        this.action({ label: '取消', onAction: () => { this.editorKind = ''; }, enabled: true, primary: false })
        if (this.editorKind === 'delete-chat' || this.editorKind === 'delete-group') {
          this.action({ label: '确认删除', onAction: () => this.deleteEditorTarget(), enabled: !this.busy(), primary: true })
        } else if (this.editorKind !== 'move-chat') {
          this.action({ label: '保存名称', onAction: () => this.saveEditorName(), enabled: !this.busy(), primary: true })
        }
      }.width('100%')
    }.width('100%').padding(8).borderRadius(10).backgroundColor(this.palette().surface)
  }

  @Builder
  historyPanel() {
    Column({ space: 14 }) {
      Row() {
        Text('会话').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).layoutWeight(1)
        IconButton({ icon: $r('app.media.ic_close'), label: '收起会话栏', onAction: () => { this.historyToggle = this.wide(); } })
      }.width('100%')
      Button('＋  新建对话', { type: ButtonType.Normal }).width('100%').height(44).borderRadius(13)
        .backgroundColor(this.dark ? '#2B4542' : '#E1EDE9').fontColor(this.palette().inkPrimary)
        .accessibilityText('新建对话').enabled(!this.busy()).onClick(() => this.newConversation())
      Row() {
        Text('工作区').fontSize(12).fontColor(this.palette().inkSecondary).layoutWeight(1)
        IconButton({ icon: $r('app.media.ic_plus'), label: '新建工作区', available: !this.busy(),
          onAction: () => this.beginEditor('create-group') })
      }.width('100%').height(44)
      if (this.editorKind) { this.sessionEditor() }
      Scroll() {
        Column({ space: 2 }) {
          ForEach(this.groups(), (group: StudyConversationGroup) => {
            this.groupHeader(group.id, group.name)
            if (!this.collapsedGroups.includes(group.id)) {
              ForEach(this.groupChats(group.id), (chat: StudyConversation) => {
                this.historyRow(chat, this.session.conversation.id === chat.id)
              }, (chat: StudyConversation) => `${chat.id}-${chat.name || ''}-${this.session.conversation.id === chat.id}`)
            }
          }, (group: StudyConversationGroup) => group.id + '-' + group.name)
          this.groupHeader('', '未分组')
          if (!this.collapsedGroups.includes('')) {
            ForEach(this.groupChats(''), (chat: StudyConversation) => {
              this.historyRow(chat, this.session.conversation.id === chat.id)
            }, (chat: StudyConversation) => `${chat.id}-${chat.name || ''}-${this.session.conversation.id === chat.id}`)
          }
        }.width('100%')
      }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).align(Alignment.TopStart)
      this.action({ label: '应用导航', onAction: () => {
        if (!this.wide()) { this.historyToggle = false; }
        this.onOpenNavigation();
      }, enabled: true, primary: false })
    }.width('100%').height('100%').padding({ left: 14, right: 14, top: 10, bottom: 10 })
      .backgroundColor(this.dark ? this.palette().surfaceSubtle : '#EDF1ED').alignItems(HorizontalAlign.Start)
  }

  @Builder
  attachmentAction(label: string, icon: Resource, onAction: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 9 }) {
        AppIcon({ source: icon, iconSize: 18, tint: this.palette().inkSecondary })
        Text(label).fontSize(14).fontColor(this.palette().inkPrimary)
      }.width('100%')
    }.width('100%').height(44).borderRadius(10).padding({ left: 9, right: 9 })
      .backgroundColor(Color.Transparent).hoverEffect(HoverEffect.Highlight)
      .accessibilityText(label).enabled(!this.busy()).onClick(onAction)
  }

  @Builder
  addOptions() {
    Column({ space: 2 }) {
      this.attachmentAction('从设备添加文件', $r('app.media.ic_new_note'), () => { this.attachFiles(); })
      this.attachmentAction('从资料库选择', $r('app.media.ic_folder'), () => {
        this.addOpen = false; this.libraryOpen = !this.libraryOpen; this.sourceSearch = '';
      })
    }.width(202).alignItems(HorizontalAlign.Start).padding(6).borderRadius(14).backgroundColor(this.palette().surface)
  }

  @Builder
  libraryPicker() {
    Column({ space: 6 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.sourceSearch, placeholder: '搜索本机资料' }).layoutWeight(1).height(44).fontSize(14)
          .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
          .onChange((term: string) => { this.sourceSearch = term; })
        this.action({ label: '完成选择', onAction: () => { this.libraryOpen = false; }, enabled: true, primary: false })
      }.width('100%')
      Scroll() {
        Column({ space: 3 }) {
          if (!StudyWorkspaceSources.searchable(this.notes, this.sourceSearch).length) {
            Text('没有匹配的文字资料').fontSize(13).fontColor(this.palette().inkSecondary).padding(9).width('100%')
          }
          ForEach(StudyWorkspaceSources.searchable(this.notes, this.sourceSearch), (note: NoteItem) => {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 8 }) {
                AppIcon({ source: this.attachmentIds().includes(note.id) ? $r('app.media.ic_check') : $r('app.media.ic_folder'),
                  iconSize: 17, tint: this.palette().inkSecondary })
                Text(note.title).fontSize(14).fontColor(this.palette().inkPrimary).maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              }.width('100%')
            }.width('100%').height(44).padding({ left: 10, right: 10 }).backgroundColor(Color.Transparent)
              .accessibilityText('选择附件 ' + note.title)
              .accessibilityDescription(this.attachmentIds().includes(note.id) ? '已添加' : '未添加')
              .onClick(() => this.toggleAttachment(note))
          }, (note: NoteItem) => note.id)
        }.width('100%')
      }.width('100%').constraintSize({ maxHeight: 176 }).align(Alignment.TopStart).scrollBar(BarState.Auto)
    }.width('100%').padding(8).borderRadius(14).backgroundColor(this.palette().surface)
      .border({ width: 1, color: this.palette().borderSubtle })
  }

  @Builder
  pdfRange(note: NoteItem) {
    Row({ space: 6 }) {
      Text('页码').fontSize(13).fontColor(this.palette().inkSecondary)
      TextInput({ text: this.rangeStart }).width(56).height(40).type(InputType.Number)
        .accessibilityText('起始页').onChange((value: string) => { this.rangeStart = value; })
      Text('至').fontSize(13).fontColor(this.palette().inkSecondary)
      TextInput({ text: this.rangeEnd }).width(56).height(40).type(InputType.Number)
        .accessibilityText('结束页').onChange((value: string) => { this.rangeEnd = value; })
      this.action({ label: this.extractingId ? '提取中…' : '提取文字', onAction: () => this.extract(note),
        enabled: !this.busy(), primary: true })
    }.width('100%')
  }

  @Builder
  attachments() {
    if (this.attachmentIds().length > 0) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.selectedSources(), (note: NoteItem) => {
            Row({ space: 2 }) {
              Text(note.title).fontSize(13).fontColor(this.palette().inkPrimary).constraintSize({ maxWidth: 148 })
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).padding({ left: 10 })
              if (note.sourceUri && (note.type.toLowerCase() === 'pdf' || note.sourceType === 'pdf')) {
                this.action({ label: StudyWorkspaceSources.hasText(note) ? '页码' : '准备文字',
                  onAction: () => this.showPdfRange(note), enabled: !this.busy(), primary: false })
              }
              IconButton({ icon: $r('app.media.ic_close'), label: '移除附件 ' + note.title,
                available: !this.busy(), onAction: () => this.toggleAttachment(note) })
            }.height(44).borderRadius(12).backgroundColor(this.palette().surfaceSubtle)
          }, (note: NoteItem) => note.id + '-' + (note.pdfTextJson || '').length)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).align(Alignment.Start)
      if (this.rangeId) {
        ForEach(this.selectedSources().filter((note: NoteItem) => note.id === this.rangeId), (note: NoteItem) => {
          this.pdfRange(note)
        }, (note: NoteItem) => note.id)
      }
    }
  }

  @Builder
  thinkingOptions() {
    Menu() {
      MenuItem({ content: '快速' }).selected(this.effort === 'none').onClick(() => { this.effort = 'none'; this.effortMenu = false; })
      MenuItem({ content: '标准' }).selected(this.effort === 'low').onClick(() => { this.effort = 'low'; this.effortMenu = false; })
      MenuItem({ content: '深入' }).selected(this.effort === 'high').onClick(() => { this.effort = 'high'; this.effortMenu = false; })
    }
  }

  @Builder
  composer() {
    Column({ space: 7 }) {
      if (this.libraryOpen) { this.libraryPicker() }
      Column({ space: 3 }) {
        this.attachments()
        TextArea({ text: this.session.conversation.draft, placeholder: this.dropping ? '松开以添加文件' : '输入问题，或拖入文件' })
          .id('study-chat-question').width('100%').height(64).maxLength(this.attachmentIds().length ? 800 : 1200).fontSize(15)
          .fontColor(this.palette().inkPrimary).padding({ left: 8, right: 8, top: 8, bottom: 4 })
          .backgroundColor(Color.Transparent).enabled(!this.sending && !this.pendingQuestion)
          .onChange((value: string) => { this.setDraft(value); this.staged = null; this.status = ''; })
        Row({ space: 5 }) {
          Button({ type: ButtonType.Normal }) {
            AppIcon({ source: this.addOpen || this.libraryOpen ? $r('app.media.ic_close') : $r('app.media.ic_plus'),
              iconSize: 20, tint: this.palette().inkPrimary })
          }.width(44).height(44).padding(0).borderRadius(22).backgroundColor(this.palette().surfaceSubtle)
            .id('study-add-content').accessibilityText('添加内容')
            .accessibilityDescription(this.addOpen || this.libraryOpen ? '已展开' : '已收起')
            .enabled(!this.busy() && !this.pendingQuestion)
            .onClick(() => { this.addOpen = !this.addOpen && !this.libraryOpen; this.libraryOpen = false; })
            .bindPopup(this.addOpen, { builder: this.addOptions, popupColor: this.palette().surface,
              placement: this.session.conversation.messages.length ? Placement.TopLeft : Placement.BottomLeft,
              radius: 14, enableArrow: false,
              onStateChange: (event) => { if (!event.isVisible) { this.addOpen = false; } } })
          if (this.attaching || this.importing) {
            Text('正在添加…').fontSize(12).fontColor(this.palette().inkSecondary)
          }
          Blank()
          if (this.selectedModel()?.webSearch && !this.reference && !this.attachmentIds().length) {
            this.action({ label: this.webEnabled ? '联网已开启' : '联网', onAction: () => { this.webEnabled = !this.webEnabled; },
              enabled: !this.busy() && !this.pendingQuestion, primary: this.webEnabled })
          }
          if (this.selectedModel()?.reasoning) {
            Button(this.effort === 'none' ? '思考 · 快速' : this.effort === 'high' ? '思考 · 深入' : '思考 · 标准',
              { type: ButtonType.Normal }).height(40).fontSize(13).borderRadius(20).padding({ left: 8, right: 8 })
              .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
              .enabled(!this.busy() && !this.pendingQuestion && !this.staged).onClick(() => { this.effortMenu = true; })
              .bindMenu(this.effortMenu, this.thinkingOptions, { onDisappear: () => { this.effortMenu = false; } })
          }
          this.action({ label: this.sending ? '停止' : '发送', onAction: () => {
            if (this.sending) { this.stop(); } else { this.send(); }
          }, enabled: this.sending || (!this.busy() && !this.pendingQuestion && this.session.conversation.draft.trim().length > 0),
            primary: true })
        }.width('100%')
      }.width('100%').padding(9).borderRadius(21).backgroundColor(this.palette().surface)
        .border({ width: 1, color: this.dropping ? STUDY_ACCENT : this.palette().border })
        .shadow({ radius: 12, color: '#13242B27', offsetY: 3 })
        .allowDrop([uniformTypeDescriptor.UniformDataType.FILE_URI, uniformTypeDescriptor.UniformDataType.FILE])
        .onDragEnter(() => { if (!this.busy()) { this.dropping = true; } })
        .onDragLeave(() => { this.dropping = false; })
        .onDrop((event: DragEvent) => this.dropFiles(event))
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  chatPane() {
    Column() {
      this.header()
      Column({ space: 10 }) {
        if (this.showConnection) { this.connection() }
        if (this.status && (!this.pendingQuestion || this.showConnection)) {
          Text(this.status).width('100%').fontSize(13).fontColor(this.palette().inkSecondary)
        }
        if (!this.session.conversation.messages.length && !this.pendingQuestion) {
          Blank().layoutWeight(1).constraintSize({ minHeight: 12 })
          if (!this.libraryOpen && !this.rangeId && !this.staged) {
            Text('今天想聊什么？').fontSize(this.phone ? 26 : 37).fontWeight(FontWeight.Medium)
              .fontColor(this.palette().inkPrimary).margin({ bottom: 15 })
          }
        } else { this.transcript() }
        if (this.staged) { this.requestPreview(this.staged) }
        else { this.composer() }
        if (!this.session.conversation.messages.length && !this.pendingQuestion) {
          Blank().layoutWeight(1).constraintSize({ minHeight: 10 })
        }
      }.width('100%').constraintSize({ maxWidth: 760 }).layoutWeight(1)
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }.width('100%').height('100%').backgroundColor(this.dark ? this.palette().canvas : '#F7F8F5')
      .radialGradient({ center: ['50%', '52%'], radius: '55%', colors: [
        [this.dark ? '#24302D' : '#E9F2ED', 0], [this.dark ? this.palette().canvas : '#F7F8F5', 1]
      ] })
  }

  @Builder
  referencePane() {
    if (this.reference && this.referenceNote()) {
      StudyReferencePane({ note: this.referenceNote()!, reference: this.reference, onClose: () => this.closeReference() })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.studyPreview) {
        Row() {
          if (this.wide() && !this.historyToggle) {
            Column() { this.historyPanel() }.width(232).height('100%')
              .border({ width: { right: 1 }, color: this.palette().borderSubtle })
          }
          Column() { this.chatPane() }.layoutWeight(1).height('100%')
          if (this.wide() && this.reference && this.referenceNote()) {
            Column() { this.referencePane() }.width(this.viewport >= 1250 ? '37%' : '41%').height('100%')
          }
        }.width('100%').height('100%')
        if (!this.wide() && this.reference && this.referenceNote()) {
          Row() {
            Column().layoutWeight(1).height('100%').backgroundColor('#55000000').onClick(() => this.closeReference())
            Column() { this.referencePane() }.width('92%').height('100%')
          }.width('100%').height('100%')
        }
        if (!this.wide() && this.historyToggle) {
          Row() {
            Column() { this.historyPanel() }.width('78%').constraintSize({ maxWidth: 280 }).height('100%')
            Column().height('100%').layoutWeight(1).backgroundColor('#55000000')
              .accessibilityText('关闭会话').onClick(() => { this.historyToggle = false; })
          }.width('100%').height('100%')
            .transition(TransitionEffect.OPACITY.animation({ duration: AnimationTokens.DURATION_NORMAL }))
        }
      } else {
        Column({ space: 12 }) {
          Text('学习工具').fontSize(25).fontColor(this.palette().inkPrimary)
          this.action({ label: '打开资料库', onAction: this.onOpenLibrary, enabled: true, primary: false })
          this.action({ label: '复习与学习结果', onAction: this.onOpenLearning, enabled: true, primary: false })
        }.width('100%').padding(24)
      }
    }.width('100%').height('100%').backgroundColor(this.palette().canvas)
      .onAreaChange((_before: Area, after: Area) => { this.viewport = Number(after.width); })
  }
}
