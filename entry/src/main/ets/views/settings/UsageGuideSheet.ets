import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { SheetOverlay, SheetCancelButton } from '../layout/sheets/SheetScaffold';

export interface GuideStep { title: string; text: string; }
export const GUIDE_STEPS: GuideStep[] = [
  { title: '阅读与编辑', text: '首页图标下方标明文字笔记、手写笔记、导入文档、提取内容。新建时填写标题，选择所属项目，可另填主题标签；图标下有类型用途说明。文档默认只读，点击编辑或笔图标开始修改；手写区可用手指拖动、双指缩放。正常返回会保存正文、批注及随堂稿纸，保存失败保留当前页面并可重试。清空笔迹需从菜单主动选择并确认。' },
  { title: '多文档分屏', text: '阅读器顶栏保留已打开的文件。按住文件名拖到阅读区右半边，松开后分屏；也可点击顶栏“分屏阅读”选择资料。支持已有 PDF、图片、文字和手写资料的任意组合，包括相同格式。宽屏左右、手机上下，两份分别保存；切换、收起和关闭前会保存，失败保留内容。' },
  { title: '手写与笔控', text: '先在系统中配对手写笔。PDF 默认笔写、手指浏览，手机和白板默认支持手指书写，双指缩放。手掌图标切换手指书写；笔设置展开颜色和大小滑杆。选中橡皮后可直接选择“区域擦除”或“笔画擦除”，分别擦掉经过的局部或碰到的整笔。普通笔、荧光笔、橡皮独立记住大小，顶栏和工具盘显示当前工具。支持对应事件的笔可双击切换橡皮擦、轻捏呼出工具。分屏时先在目标画布落笔；弯箭头撤销和重做。' },
  { title: '资料与换机', text: '导入 PDF 会保存本机副本，保留外部原文件，重新打开应用仍可阅读。未分类的导入资料显示在资料库，不创建侧栏文件夹；在项目内导入会归入该项目。“设置 → 备份与快传”可导出资料，恢复时创建副本。卸载或清除应用数据前先备份，具体范围见备份页说明。资料库每份资料右下角“…”可重命名、移动分类或移入回收站；删除需确认。' },
  { title: '日历与待办', text: '日历显示农历与节日，2026 年按国务院安排标记“休 / 班”。其他年份只显示农历节日，后续公布正式安排后再更新调休。点日期查看备忘和待办。' },
  { title: '系统操作', text: '分享图标打开系统分享；PDF 更多菜单分享原文件，原文件不含应用内笔迹。接收方由你选择。外接键盘可用 Ctrl+F 搜索；“设置 → 外观与动效”可跟随系统、切换深浅色或减少动效。' }
];

@Component
export struct UsageGuideSheet {
  onClose: () => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'mono';
  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 12 }) {
        Text('使用指引').fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary).width('100%')
        Scroll() {
          Column({ space: 18 }) {
            ForEach(GUIDE_STEPS, (step: GuideStep) => {
              Column({ space: 6 }) {
                Text(step.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary).width('100%')
                Text(step.text).fontSize(14).lineHeight(22).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkSecondary).width('100%')
              }.width('100%')
            }, (step: GuideStep) => step.title)
          }.width('100%')
        }.width('100%').constraintSize({ maxHeight: 460 }).scrollBar(BarState.Auto)
        SheetCancelButton({ label: '完成', onCancel: this.onClose })
      }.width('100%')
    }
  }
}
