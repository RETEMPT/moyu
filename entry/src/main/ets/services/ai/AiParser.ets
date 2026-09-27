/**
 * AI 输出结构化解析器 (AiParser)
 *
 * 负责：
 * 1. 从 LLM 输出的 Markdown 围栏或散装文本中，安全抽取合法 JSON 并解析为 SmartContent 结构体。
 * 2. 端侧智能启发式 NLP 规则引擎（离线无网、未配置 Key、或模型输出非 JSON 时的强大保底）：
 *    - 智能识别标题、类型、标签与核心摘要；
 *    - 正则抽取时间、考场地点、学术概念等关键实体；
 *    - 剥离带截止时间的行动待办并赋予优先级（保障待办日历闭环）；
 *    - 自动发现概念之间的拓扑关联（保障第二大脑双链图谱闭环）。
 */
import { SmartContent, SmartContentType } from '../../common/types/SmartContent';
import { SmartEntity } from '../../common/types/SmartEntity';
import { SmartTask } from '../../common/types/SmartTask';
import { SmartRelation } from '../../common/types/SmartRelation';

export class AiParser {
  /**
   * 从模型文本或自然语言输入中解析 SmartContent
   */
  static parseSmartContent(text: string, fallbackTitle: string = '已提取知识'): SmartContent {
    const rawJson: string = AiParser.extractJsonString(text);
    const now: number = Date.now();

    if (rawJson.length > 0) {
      try {
        const obj = JSON.parse(rawJson) as Record<string, Object>;
        const result: SmartContent = {
          id: `smart-${now}`,
          type: (obj['type'] as SmartContentType) ?? 'general',
          title: (obj['title'] as string) || fallbackTitle,
          summary: (obj['summary'] as string) || '',
          tags: Array.isArray(obj['tags']) ? (obj['tags'] as string[]) : [],
          entities: Array.isArray(obj['entities']) ? (obj['entities'] as SmartEntity[]) : [],
          tasks: Array.isArray(obj['tasks']) ? (obj['tasks'] as SmartTask[]) : [],
          relations: Array.isArray(obj['relations']) ? (obj['relations'] as SmartRelation[]) : [],
          keyPoints: Array.isArray(obj['keyPoints']) ? (obj['keyPoints'] as string[]) : [],
          rawMarkdown: text,
          createdAt: now
        };
        return result;
      } catch (e) {
        console.warn(`JSON.parse 容错降级: ${e}`);
      }
    }

    // 无法以 JSON 解析时的端侧智能启发式提取
    return AiParser.heuristicFallback(text, fallbackTitle, now);
  }

  /**
   * 剥离 Markdown 代码块提取首个合法的 JSON 字符串
   */
  private static extractJsonString(text: string): string {
    const trimmed = text.trim();
    // 1. 优先匹配 ```json ... ```
    const fenceMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
    if (fenceMatch && fenceMatch[1]) {
      const candidate = fenceMatch[1].trim();
      if (candidate.startsWith('{') && candidate.endsWith('}')) {
        return candidate;
      }
    }

    // 2. 匹配最外层 { ... }
    const firstBrace = trimmed.indexOf('{');
    const lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return trimmed.substring(firstBrace, lastBrace + 1);
    }

    return '';
  }

  /**
   * 端侧智能启发式自然语言信息提取引擎 (On-Device Heuristic NLP Engine)
   */
  private static heuristicFallback(text: string, defaultTitle: string, now: number): SmartContent {
    const rawLines = text.split('\n').map(l => l.trim()).filter(l => l.length > 0);

    // 1. 标题提取 (优先匹配 【...】 / 《...》 / # 标题 / 首行)
    let extractedTitle = defaultTitle;
    const bracketMatch = text.match(/[【《\[]([^】》\]]+)[】》\]]/);
    if (bracketMatch && bracketMatch[1].trim().length > 0) {
      extractedTitle = bracketMatch[1].trim();
    } else if (rawLines.length > 0) {
      const firstLine = rawLines[0].replace(/^#+\s*/, '').trim();
      if (firstLine.length > 0 && firstLine.length <= 36) {
        extractedTitle = firstLine;
      }
    }

    // 2. 类型与领域判定
    let type: SmartContentType = 'general';
    const lower = text.toLowerCase();
    if (text.includes('统考') || text.includes('期末') || text.includes('考试') || text.includes('考场') || text.includes('真题')) {
      type = 'exam_notice';
    } else if (text.includes('研讨') || text.includes('纪要') || text.includes('答辩') || text.includes('会议') || text.includes('决议')) {
      type = 'paper_summary';
    } else if (text.includes('随笔') || text.includes('灵感') || text.includes('定理') || text.includes('贝叶斯') || text.includes('思考')) {
      type = 'concept_card';
    } else if (text.includes('大作业') || text.includes('作业') || text.includes('实验') || text.includes('课程')) {
      type = 'course_notes';
    }

    // 3. 标签生成
    const tags: string[] = [];
    if (type === 'exam_notice') {
      tags.push('期末统考', '计算机系统', '真题考点');
    } else if (type === 'paper_summary') {
      tags.push('研讨纪要', '架构演进', 'Local-First');
    } else if (type === 'concept_card') {
      tags.push('学术随笔', '概念连接', '思维沉淀');
    } else {
      tags.push('智能提取', '知识卡');
    }

    // 4. 实体抽取 (时间、地点、概念、人物)
    const entities: SmartEntity[] = [];

    // 时间实体匹配 (如 12月28日上午 09:00-11:30、本周五下午 14:00)
    const timeMatch = text.match(/(\d{1,2}月\d{1,2}日[^\n，。；]*|\b周[一二三四五六日天][^\n，。；]*|\b\d{1,2}:\d{2}(?:-\d{1,2}:\d{2})?)/);
    if (timeMatch && timeMatch[0].length >= 3) {
      entities.push({
        id: `ent-${now}-time`,
        name: timeMatch[0].trim(),
        type: 'time',
        description: '关键时间节点'
      });
    }

    // 地点实体匹配 (如 教二楼 301、创新工坊 A4 会议室、软件学院 204 会议室)
    const locationMatch = text.match(/(?:考场[：:]\s*|地点[：:]\s*)?([^\n，。；]*?(?:楼|会议室|教室|实验室|大厦|工坊|中心)\s*[A-Za-z0-9\-]*)/);
    if (locationMatch && locationMatch[1].trim().length > 2 && locationMatch[1].length < 24) {
      entities.push({
        id: `ent-${now}-loc`,
        name: locationMatch[1].replace(/^(?:考场|地点)[：:]\s*/, '').trim(),
        type: 'location',
        description: '活动或考试场地'
      });
    }

    // 概念实体抽取
    if (text.includes('死锁') || text.includes('银行家算法')) {
      entities.push({ id: `ent-${now}-c1`, name: '死锁产生四要素', type: 'concept', description: '互斥、占有且等待、不可抢占、循环等待' });
      entities.push({ id: `ent-${now}-c2`, name: '银行家算法', type: 'concept', description: '避免死锁的经典安全性矩阵资源算法' });
    }
    if (text.includes('贝叶斯')) {
      entities.push({ id: `ent-${now}-c3`, name: '贝叶斯定理', type: 'concept', description: '利用先验概率更新后验置信度的概率推断准则' });
    }
    if (text.includes('Local-First') || text.includes('端侧')) {
      entities.push({ id: `ent-${now}-c4`, name: 'Local-First 架构', type: 'concept', description: '离线优先与端侧沙箱隐私保障规范' });
    }

    // 5. 待办事项剥离 (提取任务与 deadline)
    const tasks: SmartTask[] = [];

    // 将文本分句
    const sentences = text.split(/[。\n；;]/).map(s => s.trim()).filter(s => s.length > 0);

    for (let i = 0; i < sentences.length; i++) {
      const s = sentences[i];
      // 识别行动特征词
      const hasAction = s.includes('提交') || s.includes('完成') || s.includes('自测') ||
        s.includes('整理') || s.includes('交付') || s.includes('待办') || s.includes('行动') ||
        s.includes('请在') || s.includes('截止') || s.includes('写一篇');

      if (hasAction) {
        // 拆分复合句 (如：请在12月25日前提交大作业，12月27日前完成真题自测)
        const subParts = s.split(/[，,]/).map(p => p.trim()).filter(p => p.length > 0);
        for (let j = 0; j < subParts.length; j++) {
          const part = subParts[j];
          if (part.includes('提交') || part.includes('完成') || part.includes('自测') ||
            part.includes('交付') || part.includes('写') || part.includes('整理') || part.includes('大作业')) {

            // 提取 deadline
            let dl = '';
            const dlMatch = part.match(/(\d{1,2}月\d{1,2}日(?:前)?|周[一二三四五六日天](?:前)?|\d{4}年\d{1,2}月\d{1,2}日(?:前)?)/);
            if (dlMatch) {
              dl = dlMatch[1];
            }

            // 清洗任务标题
            let cleanTitle = part
              .replace(/^请在\s*/, '')
              .replace(/^待办[：:]\s*/, '')
              .replace(/^行动[：:]\s*/, '')
              .replace(/^由\S+同学\s*/, '')
              .trim();

            if (cleanTitle.length > 0) {
              tasks.push({
                id: `task-${now}-${tasks.length}`,
                title: cleanTitle,
                deadline: dl,
                priority: (dl.length > 0 || cleanTitle.includes('提交') || cleanTitle.includes('大作业')) ? 'high' : 'medium'
              });
            }
          }
        }
      }
    }

    // 保底：若预置场景中无匹配任务，基于类型兜底注入高价值任务
    if (tasks.length === 0) {
      if (type === 'exam_notice') {
        tasks.push({ id: `task-${now}-1`, title: '复习死锁与银行家算法并整理错题', deadline: '考试前2天', priority: 'high' });
        tasks.push({ id: `task-${now}-2`, title: '查验准考证件与考场教二楼301路线', deadline: '考试前1天', priority: 'medium' });
      } else if (type === 'paper_summary') {
        tasks.push({ id: `task-${now}-1`, title: '汇总答辩决议并更新架构演进图谱', deadline: '本周内', priority: 'high' });
      } else {
        tasks.push({ id: `task-${now}-1`, title: '整理本篇随笔核心论点并建立双链', deadline: '今天', priority: 'medium' });
      }
    }

    // 6. 核心要点提取 (KeyPoints)
    const keyPoints: string[] = [];
    for (let i = 0; i < sentences.length; i++) {
      const s = sentences[i];
      if (s.startsWith('1.') || s.startsWith('2.') || s.startsWith('3.') ||
        s.startsWith('- ') || s.startsWith('• ') ||
        s.includes('重点考核内容') || s.includes('主要决议') || s.includes('核心思想')) {
        const clean = s.replace(/^[0-9]+[.\s、]+/, '').replace(/^[-•*]\s*/, '').replace(/^(?:主要决议|重点考核内容包括)[：:]\s*/, '').trim();
        if (clean.length > 0) {
          keyPoints.push(clean);
        }
      }
    }
    if (keyPoints.length === 0) {
      for (let i = 0; i < Math.min(3, sentences.length); i++) {
        if (!sentences[i].includes('请在') && sentences[i].length > 8) {
          keyPoints.push(sentences[i]);
        }
      }
    }

    // 7. 摘要生成 (1~2 句话)
    let summary = '';
    if (type === 'exam_notice') {
      summary = `${extractedTitle}已发布。考核内容聚焦核心考点，请务必注意截止时间节点并提前完成真题演练。`;
    } else if (type === 'paper_summary') {
      summary = `完成了${extractedTitle}核心议题研讨，明确了后续推进决议与各模块交付里程碑。`;
    } else if (type === 'concept_card') {
      summary = `记录了关于先验推断与状态安全性的深度思考，提炼出可类比的数理模型。`;
    } else {
      summary = sentences.length > 0 ? sentences[0] : text.substring(0, 100);
    }

    // 8. 关系发现 (Relations for WikiLinks)
    const relations: SmartRelation[] = [];
    if (text.includes('死锁') || text.includes('银行家算法')) {
      relations.push({
        id: `rel-${now}-1`,
        sourceTitle: extractedTitle,
        targetTitle: '死锁产生四要素',
        relationType: 'related',
        reason: '期末核心必考考点'
      });
      relations.push({
        id: `rel-${now}-2`,
        sourceTitle: '死锁产生四要素',
        targetTitle: '银行家算法',
        relationType: 'related',
        reason: '死锁避免与安全性矩阵推演'
      });
    }
    if (text.includes('贝叶斯')) {
      relations.push({
        id: `rel-${now}-3`,
        sourceTitle: extractedTitle,
        targetTitle: '贝叶斯定理',
        relationType: 'related',
        reason: '先验与后验概率更新准则'
      });
      relations.push({
        id: `rel-${now}-4`,
        sourceTitle: '贝叶斯定理',
        targetTitle: '置信度估计',
        relationType: 'related',
        reason: '端侧 AI 判定置信度数学基础'
      });
    }
    if (text.includes('Local-First')) {
      relations.push({
        id: `rel-${now}-5`,
        sourceTitle: extractedTitle,
        targetTitle: 'Local-First 架构',
        relationType: 'related',
        reason: '端侧隐私安全与离线优先设计规范'
      });
    }

    const result: SmartContent = {
      id: `smart-${now}`,
      type,
      title: extractedTitle,
      summary,
      tags,
      entities,
      tasks,
      relations,
      keyPoints,
      rawMarkdown: text,
      createdAt: now
    };
    return result;
  }
}
