import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ReviewCard } from '../../common/types/StudyTypes';
import { ReviewPolicy } from './ReviewPolicy';

export class ReviewStorageService {
  private prefs: preferences.Preferences | null = null;
  private readBlocked: boolean = false;
  private async ensure(context: Context): Promise<preferences.Preferences> {
    if (this.prefs === null) { this.prefs = await preferences.getPreferences(context, { name: 'flowmind_study' }); }
    return this.prefs;
  }
  async load(context: Context): Promise<ReviewCard[]> {
    const raw = await (await this.ensure(context)).get('cards', '[]');
    try {
      const rows = JSON.parse(raw as string) as ReviewCard[];
      if (!Array.isArray(rows)) { throw new Error('复习记录结构无效'); }
      const cards = ReviewPolicy.normalize(rows);
      this.readBlocked = false;
      return cards;
    } catch { this.readBlocked = true; throw new Error('复习记录损坏，请先保留设备数据'); }
  }
  async save(context: Context, cards: ReviewCard[]): Promise<void> {
    if (this.readBlocked) { throw new Error('原复习记录读取失败，已阻止覆盖；请先保留设备数据'); }
    const prefs = await this.ensure(context);
    const previous = await prefs.get('cards', '[]');
    try { await prefs.put('cards', JSON.stringify(cards)); await prefs.flush(); }
    catch {
      try { await prefs.put('cards', previous); await prefs.flush(); } catch { /* Original in-memory snapshot remains visible; disk result must be checked after restart. */ }
      throw new Error('复习记录保存失败，请重试并在重启后核对');
    }
  }
}
