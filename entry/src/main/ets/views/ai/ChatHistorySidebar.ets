import { ChatSession } from '../../common/types/ChatSession';
import { ColorPalette } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { ChatHistoryPolicy } from '../../services/ai/ChatHistoryPolicy';
import { AppIcon } from '../common/AppIcon';
import { IconButton } from '../common/IconButton';

@Component
struct HistoryRow {
  @Require @Prop session: ChatSession;
  @Prop selected: boolean = false;
  onSelect: (session: ChatSession) => void = () => {};
  onDelete: (id: string) => void = () => {};
  onPin: (session: ChatSession) => void = () => {};
  @State actionsOpen: boolean = false;
  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle); }

  @Builder
  actions() {
    Menu() {
      MenuItem({ content: this.session.pinned ? '取消置顶' : '置顶对话', startIcon: $r('app.media.ic_pin') })
        .onClick(() => { this.actionsOpen = false; this.onPin(this.session); })
      MenuItem({ content: '删除对话', startIcon: $r('app.media.ic_trash') }).contentFontColor(this.palette().danger)
        .onClick(() => { this.actionsOpen = false; this.onDelete(this.session.id); })
    }
  }

  build() {
    Row({ space: 2 }) {
      Button({ type: ButtonType.Normal }) {
        Column({ space: 6 }) {
          Text(this.session.title || '新对话').fontSize(14).fontWeight(this.selected ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(this.palette().inkPrimary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(ChatHistoryPolicy.preview(this.session)).fontSize(12).fontColor(this.palette().inkMuted)
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(`${new Date(this.session.updatedAt).getMonth() + 1}月${new Date(this.session.updatedAt).getDate()}日`)
            .fontSize(10).fontColor(this.palette().inkMuted)
        }.alignItems(HorizontalAlign.Start).width('100%')
      }.layoutWeight(1).padding(10).borderRadius(8).backgroundColor(Color.Transparent)
        .accessibilityText(`打开对话：${this.session.title || '新对话'}`).onClick(() => this.onSelect(this.session))
      Button({ type: ButtonType.Normal }) {
        AppIcon({ source: $r('app.media.ic_more'), iconSize: 18, tint: this.palette().inkSecondary })
      }.width(44).height(44).padding(0).borderRadius(8).backgroundColor(Color.Transparent)
        .accessibilityText(`对话操作：${this.session.title || '新对话'}`).onClick(() => { this.actionsOpen = !this.actionsOpen; })
        .bindMenu(this.actionsOpen, this.actions, { onDisappear: () => { this.actionsOpen = false; } })
    }.width('100%').borderRadius(10).backgroundColor(this.selected ? this.palette().activeBg : this.palette().surface)
      .border({ width: 1, color: this.selected ? this.palette().accentSoft : this.palette().borderSubtle })
  }
}

/** Replaces the whole navigation sidebar; it never squeezes history into the project header. */
@Component
export struct ChatHistorySidebar {
  @Prop sessions: ChatSession[] = [];
  @Prop activeSessionId: string = '';
  onClose: () => void = () => {};
  onNew: () => void = () => {};
  onSelect: (session: ChatSession) => void = () => {};
  onDelete: (id: string) => void = () => {};
  onPin: (session: ChatSession) => void = () => {};
  @State keyword: string = '';
  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
  private openedAt: number = Date.now();
  private palette(): ColorPalette { return ThemeHelper.paletteOfDark(this.isDarkMode, this.themeStyle); }
  private rows(group: string): ChatSession[] { return ChatHistoryPolicy.filter(this.sessions, this.keyword, group, this.openedAt); }
  private resultCount(): number { return ['置顶', '今天', '最近七天', '更早'].reduce((count: number, group: string) => count + this.rows(group).length, 0); }

  build() {
    Column({ space: 12 }) {
      Row({ space: 6 }) {
        AppIcon({ source: $r('app.media.ic_history'), tint: this.palette().accent })
        Text('对话记录').fontSize(17).fontWeight(FontWeight.Medium).fontColor(this.palette().inkPrimary).layoutWeight(1)
        IconButton({ icon: $r('app.media.ic_close'), label: '返回资料侧栏', onAction: this.onClose })
      }.width('100%').height(44)
      TextInput({ text: this.keyword, placeholder: '搜索标题或最近消息' }).height(44).fontSize(13)
        .fontColor(this.palette().inkPrimary).backgroundColor(this.palette().surfaceSubtle)
        .onChange((value: string) => { this.keyword = value; })
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          AppIcon({ source: $r('app.media.ic_plus'), iconSize: 18, tint: this.palette().accent })
          Text('新建对话').fontSize(14).fontColor(this.palette().accent)
        }
      }.width('100%').height(44).borderRadius(10).backgroundColor(this.palette().accentSoft).onClick(this.onNew)
      Scroll() {
        Column({ space: 8 }) {
          if (this.resultCount() === 0) {
            Column({ space: 10 }) {
              AppIcon({ source: $r('app.media.ic_history'), iconSize: 32, tint: this.palette().inkMuted })
              Text(this.keyword.trim() ? '没有匹配的对话' : '还没有对话记录').fontSize(14).fontColor(this.palette().inkSecondary)
              Text(this.keyword.trim() ? '试试更短的关键词' : '发送第一条提问后会自动保存').fontSize(12).fontColor(this.palette().inkMuted)
            }.width('100%').padding({ top: 36, bottom: 24 })
          }
          ForEach(['置顶', '今天', '最近七天', '更早'], (group: string) => {
            if (this.rows(group).length > 0) {
              Text(group).fontSize(11).fontColor(this.palette().inkMuted).width('100%').margin({ top: 8 })
              ForEach(this.rows(group), (session: ChatSession) => {
                HistoryRow({ session, selected: session.id === this.activeSessionId, onSelect: this.onSelect, onDelete: this.onDelete, onPin: this.onPin })
              }, (session: ChatSession) => `${session.id}:${session.updatedAt}:${session.pinned}:${session.title}`)
            }
          }, (group: string) => group)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
    }.width('100%').height('100%').padding(12).backgroundColor(this.palette().sidebar)
  }
}
