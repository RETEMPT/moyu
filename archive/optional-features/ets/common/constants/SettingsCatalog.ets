export interface SettingsEntry { id: string; group: string; title: string; detail: string; keywords: string; }
export interface SettingsGroup { id: string; title: string; }
export const SETTINGS_GROUPS: SettingsGroup[] = [
  { id: 'workspace', title: '工作空间' }, { id: 'connection', title: '连接' }, { id: 'help', title: '安全与帮助' }
];
export const SETTINGS_ENTRIES: SettingsEntry[] = [
  { id: 'library', group: 'workspace', title: '资料库', detail: '本机资料与项目', keywords: '笔记 文件 PDF 存储' },
  { id: 'theme', group: 'workspace', title: '外观与动效', detail: '配色、明暗与减少动态', keywords: '主题 颜色 黑白 浅蓝 蓝白 深色 浅色 系统' },
  { id: 'capture', group: 'workspace', title: '文字识别与排版', detail: '图片转文字，默认本地整理', keywords: 'OCR 扫描 智能识别 学习笔记 无模型' },
  { id: 'ai', group: 'connection', title: 'AI 与模型', detail: '离线助手与可选自配 API', keywords: '大模型 密钥 Seed Qwen DeepSeek GLM 授权' },
  { id: 'backup', group: 'connection', title: '备份与传递', detail: '导出、恢复与附近设备', keywords: '数据 换机 同步 云盘 备份 恢复 云服务' },
  { id: 'ecosystem', group: 'connection', title: '鸿蒙与设备', detail: '系统分享、手写笔与多端', keywords: '华为 Pad 平板 手机 星闪 Penkit 互通 权限' },
  { id: 'guide', group: 'help', title: '使用指引', detail: '从收集到阅读与复习', keywords: '教程 图解 API 密钥 DeepSeek 阿里 百炼 帮助 示例 测试 PDF' },
  { id: 'legal', group: 'help', title: '隐私与数据', detail: '数据去向、授权与协议', keywords: '安全 隐私 网络 删除 密钥' },
  { id: 'about', group: 'help', title: '关于墨语', detail: '版本与开源项目', keywords: '版本 更新 开源 GitHub FlowMind' }
];
export class SettingsCatalog {
  static normalize(id: string): string {
    if (id === 'cloud') { return 'backup'; }
    return SETTINGS_ENTRIES.some((entry: SettingsEntry) => entry.id === id) ? id : 'overview';
  }
  static find(id: string): SettingsEntry | undefined { return SETTINGS_ENTRIES.find((entry: SettingsEntry) => entry.id === id); }
  static search(query: string, group: string = ''): SettingsEntry[] {
    const terms = query.trim().toLowerCase().split(/\s+/).filter((term: string) => term.length > 0);
    return SETTINGS_ENTRIES.filter((entry: SettingsEntry) => (group.length === 0 || entry.group === group) &&
      terms.every((term: string) => `${entry.title} ${entry.detail} ${entry.keywords}`.toLowerCase().includes(term)));
  }
}
