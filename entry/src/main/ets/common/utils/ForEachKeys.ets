/**
 * ForEach 键生成器。
 *
 * 为什么值得单独抽一个文件：ArkUI 的 `ForEach` **在键不变时会直接复用上一帧的子树，
 * 连 itemGenerator 都不会重新执行**。所以只要键里漏掉任何一个「会改变这一行渲染结果」
 * 的字段，数据改了界面也不会动 —— 而且没有任何报错，看起来就像功能坏了。
 *
 * 真实踩过的坑：侧边栏项目树的键原本是 `space.id`。项目内增删资料时，
 * `space-计算机基础` 这个 id 是不变的，于是删掉一篇资料后计数徽标仍是旧值、
 * 已删除的那一行还挂在树上，而 Preferences 里其实已经删干净了。
 *
 * 规则：**键必须覆盖这一行会读到的所有可变字段。**
 * 列表项一旦会重命名 / 改标签 / 改类型，键里就必须带上这些字段，不能只用 id。
 */
import { NoteItem } from '../types/NoteItem';
import { SpaceFolder } from '../types/SpaceFolder';

/**
 * 资料行（侧边栏文件行、资料库卡片、首页书架卡）的 ForEach 键。
 *
 * 覆盖了这些视图真正读到的字段：标题、标签、类型（决定图标与配色）、id。
 * 只写 `note.id` 的话，重命名后列表会继续显示旧标题。
 *
 * @param note 待渲染的资料
 * @returns 该行在本帧的唯一键
 */
export function noteRenderKey(note: NoteItem): string {
  return `${note.id}|${note.title}|${note.type}|${note.tag}`;
}

/**
 * 侧边栏项目行的 ForEach 键。
 *
 * 必须把下辖资料清单的摘要编进去：项目行的渲染结果包含子资料列表与计数徽标，
 * 而 `space.id` 在项目内增删资料时是恒定的。摘要一变，键就变，ForEach 才会重建该行。
 *
 * 刻意不包含 `activeNoteId` —— 选中态由 Sidebar 自己的 @State 驱动，
 * 不该为了高亮一行而重建整棵子树。
 *
 * @param space 待渲染的项目
 * @returns 该项目在本帧的唯一键
 */
export function spaceRenderKey(space: SpaceFolder): string {
  const notes: NoteItem[] = space.notes || [];
  let digest: string = '';
  for (let i = 0; i < notes.length; i++) {
    digest += `${noteRenderKey(notes[i])}|`;
  }
  return `${space.id}|${space.name}|${space.icon}|${space.color}|${space.count}|${space.isOpen}|${digest}`;
}
