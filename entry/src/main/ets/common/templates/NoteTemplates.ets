/** Blank note templates; inserted only after the user chooses a template. */
export function templateBody(name: string, date: Date): string {
  const y: number = date.getFullYear();
  const m: number = date.getMonth() + 1;
  const d: number = date.getDate();
  const dateText: string = `${y}-${m < 10 ? '0' + m : m}-${d < 10 ? '0' + d : d}`;
  if (name === '会议记录') {
    return `# 会议记录\n\n- 日期：${dateText}\n- 与会人：\n- 主持人：\n\n## 议题\n\n1. \n\n## 讨论要点\n\n- \n\n## 决议\n\n- \n\n## 待办\n\n- [ ] \n`;
  }
  if (name === '日记') {
    return `# ${dateText} 日记\n\n## 今日心情\n\n- \n\n## 今日记事\n\n- \n\n## 明日计划\n\n- [ ] \n`;
  }
  if (name === '读书笔记') {
    return `# 读书笔记\n\n- 书名：\n- 作者：\n- 开始日期：${dateText}\n\n## 摘录\n\n> \n\n## 我的思考\n\n- \n\n## 行动清单\n\n- [ ] \n`;
  }
  if (name === '周报') {
    return `# 周报（${dateText}）\n\n## 本周完成\n\n- \n\n## 下周计划\n\n- [ ] \n\n## 风险与阻塞\n\n- \n`;
  }
  return `# ${name}\n\n`;
}
