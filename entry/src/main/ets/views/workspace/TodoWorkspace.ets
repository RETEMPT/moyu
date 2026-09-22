/**
 * 待办日历视图（参考 Feenote 的日历式待办）
 *
 * 上半部：月历网格，可翻月；有待办的日期用红点（未完成）/绿点（已完成）标记。
 * 下半部：选中日期的详情——本日备忘（可编辑文本，显示最后编辑时间）、
 *         当日待办列表（未完成红字 / 完成绿字、点勾选切换、引用笔记可跳转、删除）、添加待办。
 *
 * 数据与副作用全部由上层 Index 处理，本组件只负责呈现与回调。
 */
import { ColorPalette, LayoutTokens, TypographyTokens } from '../../common/constants/DesignTokens';
import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { NoteItem } from '../../common/types/NoteItem';
import { CalendarCell, DayNote, TodoItem } from '../../common/types/TodoItem';
import { CalendarUtil, WEEK_LABELS } from '../../common/utils/CalendarUtil';
import { TimeFormat } from '../../common/utils/TimeFormat';
import { TodoEditDialog } from './TodoEditDialog';

/** 备忘输入停止后延迟回写的毫秒数 */
const MEMO_DEBOUNCE_MS: number = 600;

@Component
export struct TodoWorkspace {
  @Prop @Watch('onDayNotesUpdated') dayNotes: DayNote[] = [];
  @Prop todos: TodoItem[] = [];
  @Prop notes: NoteItem[] = [];

  onAddTodo: (dateKey: string, title: string, noteRefs: string[]) => void = () => {};
  onToggleTodo: (todo: TodoItem) => void = () => {};
  onDeleteTodo: (todo: TodoItem) => void = () => {};
  onUpdateDayNote: (dateKey: string, text: string) => void = () => {};
  onOpenNote: (noteId: string) => void = () => {};

  @State year: number = new Date().getFullYear();
  @State month: number = new Date().getMonth();
  @State selectedDate: string = CalendarUtil.todayKey();
  @State memoText: string = '';
  @State dialogVisible: boolean = false;

  /** 用户是否正在编辑备忘；编辑期间不被回流的 dayNotes 覆盖，避免光标跳动/丢字 */
  private memoTouched: boolean = false;
  private memoTimer: number = -1;

  @StorageProp('flowmindDarkMode') isDarkMode: boolean = false;
  @StorageProp('flowmindIsPhone') isPhone: boolean = false;

  private palette(): ColorPalette {
    return ThemeHelper.paletteOfDark(this.isDarkMode);
  }

  aboutToAppear(): void {
    this.memoText = this.memoFor(this.selectedDate);
  }

  aboutToDisappear(): void {
    this.flushMemo();
  }

  /** dayNotes 回流时，仅在用户未编辑备忘的情况下同步显示，避免打断输入 */
  onDayNotesUpdated(propName: string): void {
    if (!this.memoTouched) {
      this.memoText = this.memoFor(this.selectedDate);
    }
  }

  // ------------------------------------------------------------------
  // 派生数据
  // ------------------------------------------------------------------

  private cells(): CalendarCell[] {
    return CalendarUtil.buildMonthCells(this.year, this.month);
  }

  private gridRows(): number {
    return Math.ceil(this.cells().length / 7);
  }

  private memoFor(dateKey: string): string {
    for (let i = 0; i < this.dayNotes.length; i++) {
      if (this.dayNotes[i].date === dateKey) {
        return this.dayNotes[i].text;
      }
    }
    return '';
  }

  private memoUpdatedText(dateKey: string): string {
    for (let i = 0; i < this.dayNotes.length; i++) {
      if (this.dayNotes[i].date === dateKey && this.dayNotes[i].updatedAt > 0) {
        return TimeFormat.format(new Date(this.dayNotes[i].updatedAt));
      }
    }
    return '';
  }

  private todosFor(dateKey: string): TodoItem[] {
    const result: TodoItem[] = [];
    for (let i = 0; i < this.todos.length; i++) {
      if (this.todos[i].date === dateKey) {
        result.push(this.todos[i]);
      }
    }
    // 未完成在前，其次按创建时间升序
    result.sort((a: TodoItem, b: TodoItem) => {
      if (a.done !== b.done) {
        return a.done ? 1 : -1;
      }
      return a.createdAt - b.createdAt;
    });
    return result;
  }

  private pendingCount(dateKey: string): number {
    let count: number = 0;
    for (let i = 0; i < this.todos.length; i++) {
      if (this.todos[i].date === dateKey && !this.todos[i].done) {
        count++;
      }
    }
    return count;
  }

  private doneCount(dateKey: string): number {
    let count: number = 0;
    for (let i = 0; i < this.todos.length; i++) {
      if (this.todos[i].date === dateKey && this.todos[i].done) {
        count++;
      }
    }
    return count;
  }

  private noteTitle(noteId: string): string {
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].id === noteId) {
        const title: string = this.notes[i].title;
        return title.length === 0 ? '未命名笔记' : title;
      }
    }
    return '笔记已删除';
  }

  private selectedPendingTotal(): number {
    let count: number = 0;
    for (let i = 0; i < this.todos.length; i++) {
      if (!this.todos[i].done) {
        count++;
      }
    }
    return count;
  }

  // ------------------------------------------------------------------
  // 交互
  // ------------------------------------------------------------------

  private selectDate(dateKey: string): void {
    if (dateKey.length === 0) {
      return;
    }
    this.flushMemo();
    this.selectedDate = dateKey;
    this.memoTouched = false;
    this.memoText = this.memoFor(dateKey);
  }

  private changeMonth(delta: number): void {
    this.flushMemo();
    let nextMonth: number = this.month + delta;
    let nextYear: number = this.year;
    if (nextMonth < 0) {
      nextMonth = 11;
      nextYear--;
    } else if (nextMonth > 11) {
      nextMonth = 0;
      nextYear++;
    }
    this.month = nextMonth;
    this.year = nextYear;
  }

  private goToday(): void {
    const today: Date = new Date();
    this.year = today.getFullYear();
    this.month = today.getMonth();
    this.selectDate(CalendarUtil.todayKey());
  }

  private onMemoChange(value: string): void {
    this.memoText = value;
    this.memoTouched = true;
    if (this.memoTimer !== -1) {
      clearTimeout(this.memoTimer);
    }
    this.memoTimer = setTimeout(() => {
      this.memoTimer = -1;
      this.onUpdateDayNote(this.selectedDate, value);
    }, MEMO_DEBOUNCE_MS);
  }

  /** 立即回写尚未落盘的备忘（切日期 / 离开页面时调用） */
  private flushMemo(): void {
    if (this.memoTimer !== -1) {
      clearTimeout(this.memoTimer);
      this.memoTimer = -1;
      if (this.memoTouched) {
        this.onUpdateDayNote(this.selectedDate, this.memoText);
      }
    }
  }

  // ------------------------------------------------------------------
  // 渲染
  // ------------------------------------------------------------------

  @Builder
  weekdayHeader() {
    Row() {
      ForEach(WEEK_LABELS, (label: string) => {
        Text(label)
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
      }, (label: string) => label)
    }
    .width('100%')
    .margin({ bottom: 6 })
  }

  @Builder
  dayCell(cell: CalendarCell) {
    if (cell.inMonth) {
      Column({ space: 4 }) {
        Text(`${cell.day}`)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(cell.isToday ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(cell.isToday ? this.palette().accent : this.palette().inkPrimary)
        Row({ space: 3 }) {
          if (this.pendingCount(cell.dateKey) > 0) {
            Text('●').fontSize(8).fontColor(this.palette().danger)
          }
          if (this.doneCount(cell.dateKey) > 0) {
            Text('●').fontSize(8).fontColor(this.palette().success)
          }
        }
        .height(8)
      }
      .width('100%')
      .height(50)
      .justifyContent(FlexAlign.Center)
      .borderRadius(8)
      .backgroundColor(cell.dateKey === this.selectedDate ? this.palette().activeBg : Color.Transparent)
      .border({
        width: 1,
        color: cell.dateKey === this.selectedDate ? this.palette().accent : Color.Transparent
      })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.selectDate(cell.dateKey))
    } else {
      Column().width('100%').height(50)
    }
  }

  @Builder
  calendarGrid() {
    Grid() {
      ForEach(this.cells(), (cell: CalendarCell, index: number) => {
        GridItem() {
          this.dayCell(cell)
        }
      }, (cell: CalendarCell, index: number) => `${index}-${cell.dateKey}`)
    }
    .columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr')
    .rowsGap(4)
    .columnsGap(4)
    .width('100%')
    .height(this.gridRows() * 54)
  }

  @Builder
  refChip(noteId: string) {
    Text(`▤ ${this.noteTitle(noteId)}`)
      .fontSize(TypographyTokens.TINY)
      .fontColor(this.palette().accent)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(4)
      .backgroundColor(this.palette().surfaceSubtle)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.onOpenNote(noteId))
  }

  @Builder
  todoRow(todo: TodoItem) {
    Row({ space: 10 }) {
      Text(todo.done ? '☑' : '☐')
        .fontSize(TypographyTokens.TITLE_SUB)
        .fontColor(todo.done ? this.palette().success : this.palette().danger)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.onToggleTodo(todo))

      Column({ space: 5 }) {
        Text(todo.title)
          .fontSize(TypographyTokens.BODY_LARGE)
          .fontWeight(FontWeight.Medium)
          .fontColor(todo.done ? this.palette().success : this.palette().danger)
          .decoration({
            type: todo.done ? TextDecorationType.LineThrough : TextDecorationType.None,
            color: this.palette().success
          })
          .width('100%')

        if (todo.noteRefs.length > 0) {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(todo.noteRefs, (noteId: string) => {
              Row() {
                this.refChip(noteId)
              }
              .margin({ right: 6, bottom: 4 })
            }, (noteId: string) => noteId)
          }
          .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Text('删除')
        .fontSize(TypographyTokens.CAPTION)
        .fontColor(this.palette().inkMuted)
        .padding({ left: 8, right: 8, top: 5, bottom: 5 })
        .borderRadius(6)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => this.onDeleteTodo(todo))
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .borderRadius(8)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.palette().surfaceSubtle)
  }

  @Builder
  dayPanel() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(CalendarUtil.formatKeyCn(this.selectedDate))
          .fontSize(TypographyTokens.TITLE_SUB)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
        Blank()
        Text(`${this.todosFor(this.selectedDate).length} 项`)
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
      }
      .width('100%')

      // ---- 本日备忘（可编辑文本 / 最后编辑文本）----
      Column({ space: 6 }) {
        Row() {
          Text('本日备忘')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkSecondary)
          Blank()
          if (this.memoUpdatedText(this.selectedDate).length > 0) {
            Text(`最后编辑 ${this.memoUpdatedText(this.selectedDate)}`)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
        }
        .width('100%')

        TextArea({ text: this.memoText, placeholder: '记录这一天的想法、进展或待补充内容…' })
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkPrimary)
          .placeholderColor(this.palette().inkMuted)
          .backgroundColor(this.palette().surfaceSubtle)
          .borderRadius(8)
          .height(92)
          .width('100%')
          .onChange((value: string) => this.onMemoChange(value))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // ---- 当日待办 ----
      Row() {
        Text('待办事项')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkSecondary)
        Blank()
        Text('＋ 添加待办')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(Color.White)
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(6)
          .backgroundColor(this.palette().accent)
          .hoverEffect(HoverEffect.Highlight)
          .onClick(() => {
            this.flushMemo();
            this.dialogVisible = true;
          })
      }
      .width('100%')

      if (this.todosFor(this.selectedDate).length === 0) {
        Text('这一天还没有待办，点右上角「添加待办」开始。')
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
          .width('100%')
          .padding({ top: 8, bottom: 8 })
      } else {
        Column({ space: 6 }) {
          ForEach(this.todosFor(this.selectedDate), (todo: TodoItem) => {
            this.todoRow(todo)
          }, (todo: TodoItem) => `${todo.id}-${todo.done ? 1 : 0}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack() {
      Column() {
        // ---- 标题 ----
        Row({ space: 8 }) {
          Text('待办')
            .fontSize(TypographyTokens.TITLE_HERO)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)
          Text(`${this.selectedPendingTotal()} 项未完成`)
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
        }
        .width('100%')
        .margin({ bottom: 12 })

        // ---- 月份切换 ----
        Row({ space: 10 }) {
          Text('‹')
            .fontSize(TypographyTokens.TITLE_SUB)
            .fontColor(this.palette().inkSecondary)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(6)
            .backgroundColor(this.palette().surfaceSubtle)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.changeMonth(-1))
          Text(CalendarUtil.monthTitle(this.year, this.month))
            .fontSize(TypographyTokens.TITLE_SUB)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
          Text('今天')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().accent)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .borderRadius(6)
            .backgroundColor(this.palette().surfaceSubtle)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.goToday())
          Text('›')
            .fontSize(TypographyTokens.TITLE_SUB)
            .fontColor(this.palette().inkSecondary)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(6)
            .backgroundColor(this.palette().surfaceSubtle)
            .hoverEffect(HoverEffect.Highlight)
            .onClick(() => this.changeMonth(1))
        }
        .width('100%')
        .margin({ bottom: 10 })

        this.weekdayHeader()
        this.calendarGrid()

        Divider()
          .strokeWidth(1)
          .color(this.palette().borderSubtle)
          .margin({ top: 10, bottom: 4 })

        Scroll() {
          this.dayPanel()
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: LayoutTokens.CONTENT_MAX_WIDTH + 160 })
      .padding({ left: LayoutTokens.gutter(this.isPhone), right: LayoutTokens.gutter(this.isPhone), top: 24, bottom: 20 })
      .backgroundColor(this.palette().canvas)

      if (this.dialogVisible) {
        TodoEditDialog({
          dateKey: this.selectedDate,
          notes: this.notes,
          onClose: () => {
            this.dialogVisible = false;
          },
          onSave: (title: string, noteRefs: string[]) => {
            this.dialogVisible = false;
            this.onAddTodo(this.selectedDate, title, noteRefs);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
