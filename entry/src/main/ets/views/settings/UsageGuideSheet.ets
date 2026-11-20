import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { SheetOverlay, SheetCancelButton } from '../layout/sheets/SheetScaffold';
import { DocumentText } from '../common/DocumentText';

export interface GuideStep { title: string; text: string; }
export const GUIDE_STEPS: GuideStep[] = [
  { title: '阅读与编辑', text: '首页图标下方标明文字笔记、手写笔记、导入文档、提取内容。新建时填写标题，选择所属项目，可另填主题标签；图标下有类型用途说明。文档默认只读，点击编辑或笔图标开始修改；手写区可用手指拖动、双指缩放。正常返回会保存正文、批注及随堂稿纸，保存失败保留当前页面并可重试。清空笔迹需从菜单主动选择并确认。' },
  { title: '多文档分屏', text: '阅读器顶栏保留已打开的文件。按住文件名拖到阅读区右半边，松开后分屏；也可点击顶栏“分屏阅读”选择资料。支持已有 PDF、图片、文字和手写资料的任意组合，包括相同格式。宽屏左右、手机上下，两份分别保存；切换、收起和关闭前会保存，失败保留内容。' },
  { title: '手写与笔控', text: '先在系统中配对手写笔，再进入手写或批注模式。手掌图标用于拖动页面；手指书写在画笔设置里开关，双指可缩放。选中橡皮后可选择“区域擦除”或“笔画擦除”，分别擦掉经过的局部或碰到的整笔。普通笔、荧光笔和橡皮各自记住粗细。支持对应笔身手势的设备上，双击切换橡皮，轻捏打开画笔工具。分屏时先在目标画布落笔；弯箭头撤销和重做。' },
  { title: '资料与换机', text: '华为笔记可先导出为 PDF 或图片，再通过墨语「导入资料」打开。导入 PDF 会保存本机副本，保留外部原文件。未分类资料显示在资料库，从项目内导入的资料会归入该项目。资料库右上的分享图标打开「备份与快传」。收到资料包后，可从系统分享面板选墨语，也可在接收页选择文件，预览后导入副本。卸载或清除应用数据前先备份。资料库每份资料的更多菜单可重命名、移动分类或移入回收站。' },
  { title: '日历与待办', text: '日历显示农历与节日，2026 年按国务院安排标记“休 / 班”。其他年份只显示农历节日，后续公布正式安排后再更新调休。点日期查看备忘和待办。' },
  { title: '系统操作', text: '分享图标打开系统分享；PDF 更多菜单分享原文件，原文件不含应用内笔迹。接收方由你选择。外接键盘可用 Ctrl+F 搜索；“设置 → 外观与动效”可跟随系统、切换深浅色或减少动效。' }
];

@Component
export struct UsageGuideSheet {
  onClose: () => void = () => {};
  onSave: (step: GuideStep) => Promise<boolean> = async () => false;
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  @State private selected: number = -1;
  @State private saving: boolean = false;
  @State private saved: string[] = [];
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; }
  aboutToDisappear(): void { this.alive = false; }

  private async saveSelected(): Promise<void> {
    const step = GUIDE_STEPS[this.selected];
    if (!step || this.saving || this.saved.includes(step.title)) { return; }
    this.saving = true;
    try {
      if (await this.onSave(step) && this.alive) { this.saved = this.saved.concat(step.title); }
    } finally { if (this.alive) { this.saving = false; } }
  }

  build() {
    SheetOverlay({ onDismiss: () => { if (!this.saving) { this.onClose(); } } }) {
      Column({ space: 12 }) {
        Text(this.selected < 0 ? '使用指引' : GUIDE_STEPS[this.selected].title).fontSize(20).fontWeight(FontWeight.Bold)
          .fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary).width('100%')
        if (this.selected < 0) {
          Scroll() {
            Column({ space: 6 }) {
              ForEach(GUIDE_STEPS, (step: GuideStep, index: number) => {
                Button({ type: ButtonType.Normal }) {
                  Text(step.title).textAlign(TextAlign.Start).width('100%').fontSize(15).fontWeight(FontWeight.Medium)
                    .fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary)
                }.width('100%').height(48).borderRadius(8).padding({ left: 12, right: 12 })
                  .backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).surfaceSubtle)
                  .onClick(() => { this.selected = index; })
              }, (step: GuideStep) => step.title)
            }.width('100%')
          }.width('100%').constraintSize({ maxHeight: 330 }).scrollBar(BarState.Auto)
          SheetCancelButton({ label: '完成', onCancel: this.onClose })
        } else {
          Scroll() {
            DocumentText({ text: GUIDE_STEPS[this.selected].text })
          }.width('100%').constraintSize({ maxHeight: 320 }).scrollBar(BarState.Auto)
          Button(this.saved.includes(GUIDE_STEPS[this.selected].title) ? '已保存到资料库' : '保存 Markdown 副本')
            .height(44).width('100%').borderRadius(8)
            .fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).onAccent)
            .backgroundColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).accent)
            .enabled(!this.saving && !this.saved.includes(GUIDE_STEPS[this.selected].title)).onClick(() => { this.saveSelected(); })
          SheetCancelButton({ label: '返回指引目录', onCancel: () => { if (!this.saving) { this.selected = -1; } } })
        }
      }.width('100%')
    }
  }
}
