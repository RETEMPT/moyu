/**
 * 侧边栏「项目与资料」树的派生逻辑。
 *
 * 从 Index.ets 抽出来的原因：这是一段纯函数式的数据变换 —— 输入笔记列表 +
 * 已注册项目 + 上一次的树，输出这一帧要渲染的项目树 —— 却和 Entry 组件的
 * 状态更新混写在一起，既没法单测，也让「笔记的 category 就是项目归属」这条
 * 唯一规则被埋在一堆 this.xxx 里看不清。
 *
 * 链路：NoteItem.category  ──分组──▶  notesMap
 *       customProjects     ──补齐──▶  result（保留用户自定义的顺序/图标/颜色）
 *       其余分类            ──追加──▶  result
 *
 * 注意 `previous` 的作用：折叠状态（isOpen）与未注册分类的颜色/图标只存在于
 * 上一帧的树里，每次重建时必须从旧树里捞回来，否则每次增删笔记都会把所有
 * 项目重新展开。
 */
import { NoteItem } from '../common/types/NoteItem';
import { SpaceFolder } from '../common/types/SpaceFolder';

const DEFAULT_PROJECT_COLOR: string = '#4F46E5';
const DEFAULT_IMPLICIT_COLOR: string = '#787774';
const DEFAULT_ICON: string = '📁';
const UNCATEGORIZED: string = '未分类';

/**
 * 按 category 把笔记归入项目，生成侧边栏要渲染的项目树。
 *
 * @param source 全部笔记
 * @param customProjects 用户注册过的项目（决定顺序与默认图标/主题色）
 * @param previous 上一帧的项目树，用于继承折叠状态
 * @returns 新的项目树；每次调用都返回新数组，可直接赋给 @State
 */
export function buildSpaces(
  source: NoteItem[],
  customProjects: SpaceFolder[],
  previous: SpaceFolder[]
): SpaceFolder[] {
  const notesMap: Map<string, NoteItem[]> = new Map();
  for (let i = 0; i < source.length; i++) {
    const category: string = source[i].category.length === 0 ? UNCATEGORIZED : source[i].category;
    let list: NoteItem[] | undefined = notesMap.get(category);
    if (list === undefined) {
      list = [];
      notesMap.set(category, list);
    }
    list.push(source[i]);
  }

  const result: SpaceFolder[] = [];
  const processedCategories: Set<string> = new Set();

  // 1) 已注册项目：顺序由 customProjects 决定
  for (let i = 0; i < customProjects.length; i++) {
    const proj: SpaceFolder = customProjects[i];
    const projNotes: NoteItem[] = notesMap.get(proj.name) || [];
    result.push({
      id: proj.id,
      name: proj.name,
      count: projNotes.length,
      isOpen: findPrevious(previous, proj.name)?.isOpen ?? proj.isOpen,
      children: [],
      color: proj.color || DEFAULT_PROJECT_COLOR,
      icon: proj.icon || DEFAULT_ICON,
      notes: projNotes
    });
    processedCategories.add(proj.name);
  }

  // 2) 其余分类（含从未注册过的、以及「未分类」）
  notesMap.forEach((notesList: NoteItem[], categoryName: string) => {
    if (processedCategories.has(categoryName)) {
      return;
    }
    const last: SpaceFolder | undefined = findPrevious(previous, categoryName);
    result.push({
      id: `space-${categoryName}`,
      name: categoryName,
      count: notesList.length,
      isOpen: last?.isOpen ?? true,
      children: [],
      color: pickNonEmpty(last?.color, DEFAULT_IMPLICIT_COLOR),
      icon: pickNonEmpty(last?.icon, DEFAULT_ICON),
      notes: notesList
    });
  });

  return result;
}

/**
 * 在上一帧的树里按名字找同一个项目。
 *
 * 先取到局部变量再收窄：直接写 `previous[j].color` 无法让 ArkTS 认定其非空
 * （下标访问每次都会重新求值，同一性不被保证）。
 */
function findPrevious(previous: SpaceFolder[], name: string): SpaceFolder | undefined {
  for (let i = 0; i < previous.length; i++) {
    if (previous[i].name === name) {
      return previous[i];
    }
  }
  return undefined;
}

function pickNonEmpty(value: string | undefined, fallback: string): string {
  return (value !== undefined && value.length > 0) ? value : fallback;
}
