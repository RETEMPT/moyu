import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { SheetOverlay, SheetCancelButton } from '../layout/sheets/SheetScaffold';
import { REMOTE_AI_ENABLED } from '../../common/constants/RuntimeCapabilities';

export interface GuideStep { title: string; text: string; }
export const GUIDE_STEPS: GuideStep[] = [
  { title: '阅读与编辑', text: '首页图标下方标明文字笔记、手写笔记、导入文档、提取内容。新建时填写标题，选择所属项目，可另填主题标签；图标下有类型用途说明。文档默认只读，点击编辑或笔图标开始修改；手写区可用手指拖动、双指缩放。未修改或已保存时直接返回，有未保存内容时选择继续阅读或保存并退出。' },
  { title: '手写与笔控', text: '先在系统中配对手写笔。PDF 默认笔写、手指浏览，手机和白板默认支持手指书写，双指缩放。手掌图标切换手指书写；笔设置展开颜色和大小滑杆。普通笔、荧光笔、橡皮独立记住大小，顶栏和工具盘显示当前工具。支持对应事件的笔可双击切换橡皮擦、轻捏呼出工具。分屏时先在目标画布落笔；弯箭头撤销和重做。' },
  { title: '本地助手', text: '在“墨客”引用资料后，选择“提取要点”“整理待办”或输入关键词搜索原文。无需账号、密钥或联网。摘录可回到来源核对，提取的待办不会自动创建。加号可按标题、项目、标签和正文关键词选取引用。PDF 要先提取并校对文字；伴读可选本页或已校对页范围。' },
  { title: 'AI 配置', text: '左下角“设置 → AI 配置”选择本地助手或自配 API。本地无需密钥、无需联网；自配 API 在确认发送授权、测试连接并保存后使用。团队云 AI 暂未开放。“使用指引”中有 DeepSeek / 阿里云百炼图解和官方获取入口。正在生成可点停止图标；失败可重试或切回本地。' },
  { title: '资料与换机', text: '导入 PDF 会保存本机副本，保留外部原文件，重新打开应用仍可阅读。墨客和智能提取导入的资料存放在“外部参考”。“设置 → 资料库 → 备份与附近传递”可导出资料，恢复时创建副本。卸载或清除应用数据前先备份，具体范围见备份页说明。长按项目或资料打开操作面板。' },
  { title: '日历与待办', text: '日历显示农历与节日，2026 年按国务院安排标记“休 / 班”。其他年份只显示农历节日，后续公布正式安排后再更新调休。点日期查看备忘和待办。' },
  { title: '系统操作', text: '分享图标打开系统分享；PDF 更多菜单分享原文件，原文件不含应用内笔迹。接收方由你选择。外接键盘可用 Ctrl+F 搜索；“设置 → 主题风格”可跟随系统、切换深浅色或减少动效。' }
];

@Component
export struct UsageGuideSheet {
  onClose: () => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  @StorageProp('flowmindThemeStyle') themeStyle: string = 'ink';
  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 12 }) {
        Text('使用指引').fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeHelper.paletteOfDark(this.dark, this.themeStyle).inkPrimary).width('100%')
        Scroll() {
          Column({ space: 18 }) {
            ForEach(GUIDE_STEPS.filter((step: GuideStep) => REMOTE_AI_ENABLED || step.title !== '可选模型'), (step: GuideStep) => {
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
