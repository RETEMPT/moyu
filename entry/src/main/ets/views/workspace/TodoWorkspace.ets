/**
 * 待办日历工作台 (TodoWorkspace - UI/UX Pro Max 升级版)
 *
 * 核心升级：
 *   1. 人体工学 44x44vp 触控复选框与平滑微动效，防止移动端错触
 *   2. 色彩语义重构：正常待办采用高对比度正文色 (WCAG AA 4.5:1+)，告别刺眼报错红
 *   3. 状态徽章微排版：[ 待办 ] / [ ✓ 已完成 ] / [ 关联笔记 ]
 *   4. Bento Card 双容器美学：月历视窗与日程待办均采用卡片层级与柔和微阴影
 *   5. 优雅空白态 (Empty State) 与快捷「规划今日任务」操作引导
 */
import { curves } from '@kit.ArkUI';
import { ColorPalette, LayoutTokens, TypographyTokens, AnimationTokens } from '../../common/constants/DesignTokens';
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
    return result;
  }

  private noteTitle(noteId: string): string {
    for (let i = 0; i < this.notes.length; i++) {
      if (this.notes[i].id === noteId) {
        return this.notes[i].title;
      }
    }
    return noteId;
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
  // 交互事件
  // ------------------------------------------------------------------

  private changeMonth(delta: number): void {
    let newMonth: number = this.month + delta;
    let newYear: number = this.year;
    if (newMonth < 0) {
      newMonth = 11;
      newYear--;
    } else if (newMonth > 11) {
      newMonth = 0;
      newYear++;
    }
    this.year = newYear;
    this.month = newMonth;
  }

  private goToday(): void {
    const now: Date = new Date();
    this.year = now.getFullYear();
    this.month = now.getMonth();
    this.selectDate(CalendarUtil.todayKey());
  }

  private selectDate(dateKey: string): void {
    this.flushMemo();
    this.selectedDate = dateKey;
    this.memoTouched = false;
    this.memoText = this.memoFor(dateKey);
  }

  private onMemoChange(value: string): void {
    this.memoTouched = true;
    this.memoText = value;
    if (this.memoTimer !== -1) {
      clearTimeout(this.memoTimer);
    }
    this.memoTimer = setTimeout(() => {
      this.memoTimer = -1;
      this.onUpdateDayNote(this.selectedDate, this.memoText);
    }, MEMO_DEBOUNCE_MS);
  }

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
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkMuted)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
      }, (label: string) => label)
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  dayCell(cell: CalendarCell) {
    if (cell.inMonth) {
      Column({ space: 4 }) {
        Text(`${cell.day}`)
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontWeight(cell.isToday ? FontWeight.Bold : (cell.dateKey === this.selectedDate ? FontWeight.Medium : FontWeight.Normal))
          .fontColor(cell.isToday ? this.palette().accent : (cell.dateKey === this.selectedDate ? this.palette().accent : this.palette().inkPrimary))

        // 状态指示原点
        Row({ space: 3 }) {
          if (this.pendingCount(cell.dateKey) > 0) {
            Circle({ width: 5, height: 5 })
              .fill(this.palette().accent)
          }
          if (this.doneCount(cell.dateKey) > 0) {
            Circle({ width: 5, height: 5 })
              .fill(this.palette().success)
          }
        }
        .height(6)
      }
      .width('100%')
      .height(52)
      .justifyContent(FlexAlign.Center)
      .borderRadius(10)
      .backgroundColor(cell.dateKey === this.selectedDate ? this.palette().accentSoft : (cell.isToday ? this.palette().surfaceSubtle : Color.Transparent))
      .border({
        width: cell.dateKey === this.selectedDate ? 1.5 : (cell.isToday ? 1 : 0),
        color: cell.dateKey === this.selectedDate ? this.palette().accent : this.palette().borderSubtle
      })
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => this.selectDate(cell.dateKey))
    } else {
      Column().width('100%').height(52)
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
    .rowsGap(6)
    .columnsGap(6)
    .width('100%')
    .height(this.gridRows() * 58)
  }

  @Builder
  refChip(noteId: string) {
    Row({ space: 4 }) {
      Text('▤')
        .fontSize(11)
        .fontColor(this.palette().accent)
      Text(this.noteTitle(noteId))
        .fontSize(TypographyTokens.TINY)
        .fontColor(this.palette().accent)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .borderRadius(6)
    .backgroundColor(this.palette().accentSoft)
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => this.onOpenNote(noteId))
  }

  @Builder
  todoRow(todo: TodoItem) {
    Row({ space: 8 }) {
      // 1. 人体工学 44x44vp 触控复选框
      Row() {
        Row() {
          if (todo.done) {
            Text('✓')
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
        }
        .width(22)
        .height(22)
        .borderRadius(6)
        .backgroundColor(todo.done ? this.palette().success : Color.Transparent)
        .border({
          width: 1.5,
          color: todo.done ? this.palette().success : this.palette().inkMuted
        })
        .justifyContent(FlexAlign.Center)
      }
      .width(44)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .onClick(() => this.onToggleTodo(todo))

      // 2. 待办文本与关联资料
      Column({ space: 4 }) {
        Row({ space: 6 }) {
          // 状态徽标
          Text(todo.done ? '已完成' : '待办')
            .fontSize(TypographyTokens.TINY)
            .fontWeight(FontWeight.Medium)
            .fontColor(todo.done ? this.palette().success : this.palette().accent)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor(todo.done ? 'rgba(5,150,105,0.12)' : this.palette().accentSoft)

          Text(todo.title)
            .fontSize(TypographyTokens.BODY_LARGE)
            .fontWeight(todo.done ? FontWeight.Normal : FontWeight.Medium)
            .fontColor(todo.done ? this.palette().inkMuted : this.palette().inkPrimary)
            .decoration({
              type: todo.done ? TextDecorationType.LineThrough : TextDecorationType.None,
              color: this.palette().inkMuted
            })
            .layoutWeight(1)
        }
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

      // 3. 删除操作按钮 (40x40vp 触控区)
      Row() {
        Text('✕')
          .fontSize(12)
          .fontColor(this.palette().inkMuted)
          .width(28)
          .height(28)
          .textAlign(TextAlign.Center)
          .borderRadius(14)
          .backgroundColor(this.palette().surface)
          .hoverEffect(HoverEffect.Highlight)
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .onClick(() => this.onDeleteTodo(todo))
    }
    .width('100%')
    .padding({ left: 6, right: 12, top: 4, bottom: 4 })
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.palette().surface)
    .border({ width: 1, color: this.palette().borderSubtle })
    .shadow({ radius: 8, color: this.isDarkMode ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.03)', offsetY: 2 })
  }

  @Builder
  dayPanel() {
    Column({ space: 14 }) {
      // 头部：日期与总项数
      Row({ space: 8 }) {
        Text(CalendarUtil.formatKeyCn(this.selectedDate))
          .fontSize(TypographyTokens.TITLE_SUB)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().inkPrimary)
        Blank()
        Text(`${this.todosFor(this.selectedDate).length} 项日程`)
          .fontSize(TypographyTokens.CAPTION)
          .fontColor(this.palette().inkMuted)
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(6)
          .backgroundColor(this.palette().surfaceSubtle)
      }
      .width('100%')

      // ---- 本日备忘 ----
      Column({ space: 6 }) {
        Row() {
          Text('📝 本日随记与备忘')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkSecondary)
          Blank()
          if (this.memoUpdatedText(this.selectedDate).length > 0) {
            Text(`更新于 ${this.memoUpdatedText(this.selectedDate)}`)
              .fontSize(TypographyTokens.TINY)
              .fontColor(this.palette().inkMuted)
          }
        }
        .width('100%')

        TextArea({ text: this.memoText, placeholder: '记录今日学习心得、重点反思或随堂待办…' })
          .fontSize(TypographyTokens.BODY_REGULAR)
          .fontColor(this.palette().inkPrimary)
          .placeholderColor(this.palette().inkMuted)
          .backgroundColor(this.palette().surface)
          .border({ width: 1, color: this.palette().borderSubtle })
          .borderRadius(10)
          .height(88)
          .width('100%')
          .onChange((value: string) => this.onMemoChange(value))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      // ---- 当日待办标题与添加按钮 ----
      Row() {
        Text('☑ 当日待办清单')
          .fontSize(TypographyTokens.CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().inkSecondary)
        Blank()
        Row({ space: 4 }) {
          Text('＋')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Text('添加待办')
            .fontSize(TypographyTokens.CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
        }
        .padding({ left: 14, right: 14, top: 7, bottom: 7 })
        .borderRadius(16)
        .backgroundColor(this.palette().accent)
        .hoverEffect(HoverEffect.Highlight)
        .onClick(() => {
          this.flushMemo();
          this.dialogVisible = true;
        })
      }
      .width('100%')

      // ---- 待办列表或友好空白态 ----
      if (this.todosFor(this.selectedDate).length === 0) {
        Column({ space: 10 }) {
          Text('📋')
            .fontSize(32)
          Text('今日暂无待办事项')
            .fontSize(TypographyTokens.BODY_REGULAR)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().inkPrimary)
          Text('劳逸结合享受专注时光，或点击上方按钮规划新任务。')
            .fontSize(TypographyTokens.CAPTION)
            .fontColor(this.palette().inkMuted)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 24, bottom: 24 })
        .borderRadius(12)
        .backgroundColor(this.palette().surfaceSubtle)
        .justifyContent(FlexAlign.Center)
      } else {
        Column({ space: 8 }) {
          ForEach(this.todosFor(this.selectedDate), (todo: TodoItem) => {
            this.todoRow(todo)
          }, (todo: TodoItem) => `${todo.id}-${todo.done ? 1 : 0}`)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .borderRadius(16)
    .backgroundColor(this.palette().surfaceSubtle)
    .border({ width: 1, color: this.palette().borderSubtle })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Stack() {
      Column() {
        // ---- 标题与统计 ----
        Row({ space: 10 }) {
          Text('待办任务')
            .fontSize(TypographyTokens.TITLE_HERO)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().inkPrimary)

          Row({ space: 4 }) {
            Text('●')
              .fontSize(8)
              .fontColor(this.palette().accent)
            Text(`${this.selectedPendingTotal()} 项待完成`)
              .fontSize(TypographyTokens.CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().accent)
          }
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(12)
          .backgroundColor(this.palette().accentSoft)
        }
        .width('100%')
        .margin({ bottom: 14 })

        // ---- 月份切换 Bento 卡片 ----
        Column() {
          Row({ space: 10 }) {
            // 上一月
            Text('‹')
              .fontSize(TypographyTokens.TITLE_SUB)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkSecondary)
              .width(36)
              .height(36)
              .textAlign(TextAlign.Center)
              .borderRadius(10)
              .backgroundColor(this.palette().surfaceSubtle)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.changeMonth(-1))

            Text(CalendarUtil.monthTitle(this.year, this.month))
              .fontSize(TypographyTokens.TITLE_SUB)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkPrimary)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)

            // 今天
            Text('回到今天')
              .fontSize(TypographyTokens.CAPTION)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().accent)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(14)
              .backgroundColor(this.palette().accentSoft)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.goToday())

            // 下一月
            Text('›')
              .fontSize(TypographyTokens.TITLE_SUB)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.palette().inkSecondary)
              .width(36)
              .height(36)
              .textAlign(TextAlign.Center)
              .borderRadius(10)
              .backgroundColor(this.palette().surfaceSubtle)
              .hoverEffect(HoverEffect.Highlight)
              .onClick(() => this.changeMonth(1))
          }
          .width('100%')
          .margin({ bottom: 12 })

          this.weekdayHeader()
          this.calendarGrid()
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor(this.palette().surface)
        .border({ width: 1, color: this.palette().borderSubtle })
        .shadow({ radius: 12, color: this.isDarkMode ? 'rgba(0,0,0,0.3)' : 'rgba(0,0,0,0.03)', offsetY: 2 })
        .margin({ bottom: 16 })

        // ---- 选中日期的日程面板 ----
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
      .padding({ left: 32, right: 32, top: 24, bottom: 20 })
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
