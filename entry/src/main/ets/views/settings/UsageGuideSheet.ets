import { ThemeHelper } from '../../common/theme/ThemeHelper';
import { SheetOverlay, SheetCancelButton } from '../layout/sheets/SheetScaffold';
import { REMOTE_AI_ENABLED } from '../../common/constants/RuntimeCapabilities';

interface GuideStep { title: string; text: string; }
const STEPS: GuideStep[] = [
  { title: '图标与记录', text: '首页四个图标依次是文字笔记、手写笔记、导入、提取。输入标题后点勾选图标创建。按钮可显示系统操作提示；文字笔记直接进入编辑，手写笔记打开稿纸。修改后查看保存状态。' },
  { title: '手写与笔控', text: '先在系统中配对手写笔。默认笔写、手指浏览，双指缩放。手掌图标可开启手指书写；滑杆图标展开颜色和笔粗。支持对应事件的笔可双击切换橡皮擦、轻捏呼出工具。分屏时先在目标画布落笔；弯箭头撤销和重做。' },
  { title: '本地助手', text: '在“墨客”引用资料后，选择“提取要点”“整理待办”或输入关键词搜索原文。无需账号、密钥或联网。摘录可回到来源核对，提取的待办不会自动创建。PDF 要先提取并校对文字。' },
  { title: '可选模型', text: '需要生成式问答时，在“助手设置 → 自配模型”填写自己的服务，确认发送授权后测试并保存。正在生成可点“停止”；失败可重试或切回本地助手。服务费用由提供方决定。' },
  { title: '保存与换机', text: '“外观与数据 → 备份与附近传递”可导出资料。恢复时导入副本，原资料保留。卸载前先备份，具体范围见备份页说明。' },
  { title: '系统操作', text: '文字阅读器的向上箭头打开系统分享；PDF 通过更多菜单分享原文件，原文件不含应用内笔迹。接收方由你选择。返回手势先关闭当前弹层，阅读器退出需确认保存。外接键盘可用 Ctrl+F 搜索；主题可跟随系统。' }
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
            ForEach(STEPS.filter((step: GuideStep) => REMOTE_AI_ENABLED || step.title !== '可选模型'), (step: GuideStep) => {
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
