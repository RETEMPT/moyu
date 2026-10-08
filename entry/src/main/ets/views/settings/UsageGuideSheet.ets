import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { SheetOverlay, SheetCancelButton } from '../layout/sheets/SheetScaffold';
import { REMOTE_AI_ENABLED } from '../../common/constants/RuntimeCapabilities';

export interface GuideStep { title: string; text: string; }
export const GUIDE_STEPS: GuideStep[] = [
  { title: '阅读与编辑', text: '首页四个图标下方标明文字笔记、手写笔记、导入文档、提取内容。文档默认只读，点击编辑或笔图标开始修改；手写区可用手指拖动、双指缩放。未修改或已保存时直接返回，有未保存内容时选择继续阅读或保存并退出。' },
  { title: '手写与笔控', text: '先在系统中配对手写笔。默认笔写、手指浏览，双指缩放。手掌图标可开启手指书写；滑杆图标展开颜色和笔粗。支持对应事件的笔可双击切换橡皮擦、轻捏呼出工具。分屏时先在目标画布落笔；弯箭头撤销和重做。' },
  { title: '本地助手', text: '在“墨客”引用资料后，选择“提取要点”“整理待办”或输入关键词搜索原文。无需账号、密钥或联网。摘录可回到来源核对，提取的待办不会自动创建。PDF 要先提取并校对文字。' },
  { title: 'AI 配置', text: '左下角“设置 → AI 配置”选择本地助手或自配 API。本地无需密钥、无需联网；自配 API 在确认发送授权、测试连接并保存后使用。团队云 AI 暂未开放。正在生成可点停止图标；失败可重试或切回本地。' },
  { title: '资料与换机', text: '“设置 → 资料库 → 备份与附近传递”可导出资料。恢复时导入副本，原资料保留。卸载前先备份，具体范围见备份页说明。长按项目或资料打开居中的操作面板。' },
  { title: '日历与待办', text: '日历显示农历与节日，2026 年按国务院安排标记“休 / 班”。其他年份只显示农历节日，后续公布正式安排后再更新调休。点日期查看备忘和待办。' },
  { title: '系统操作', text: '分享图标打开系统分享；PDF 更多菜单分享原文件，原文件不含应用内笔迹。接收方由你选择。外接键盘可用 Ctrl+F 搜索；“设置 → 主题风格”可跟随系统、切换深浅色或减少动效。' }
];

@Component
export struct UsageGuideSheet {
  onClose: () => void = () => {};
  @StorageProp('flowmindDarkMode') dark: boolean = false;
  build() {
    SheetOverlay({ onDismiss: this.onClose }) {
      Column({ space: 12 }) {
        Text('使用指引').fontSize(20).fontWeight(FontWeight.Bold).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary).width('100%')
        Scroll() {
          Column({ space: 18 }) {
            ForEach(GUIDE_STEPS.filter((step: GuideStep) => REMOTE_AI_ENABLED || step.title !== '可选模型'), (step: GuideStep) => {
              Column({ space: 6 }) {
                Text(step.title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(ThemeHelper.paletteOfDark(this.dark).inkPrimary).width('100%')
                Text(step.text).fontSize(14).lineHeight(22).fontColor(ThemeHelper.paletteOfDark(this.dark).inkSecondary).width('100%')
              }.width('100%')
            }, (step: GuideStep) => step.title)
          }.width('100%')
        }.width('100%').constraintSize({ maxHeight: 460 }).scrollBar(BarState.Auto)
        SheetCancelButton({ label: '完成', onCancel: this.onClose })
      }.width('100%')
    }
  }
}
