import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ReviewCard } from '../../common/types/StudyTypes';
import { ReviewPolicy } from './ReviewPolicy';
import { SnapshotStore } from '../storage/SnapshotStore';

export class ReviewStorageService {
  private prefs: preferences.Preferences | null = null;
  private snapshots: SnapshotStore = new SnapshotStore();
  private async ensure(context: Context): Promise<preferences.Preferences> {
    if (this.prefs === null) { this.prefs = await preferences.getPreferences(context, { name: 'flowmind_study' }); }
    return this.prefs;
  }
  async load(context: Context): Promise<ReviewCard[]> {
    try {
      const rows = await this.snapshots.read<ReviewCard[]>(await this.ensure(context), 'cards',
        (value: ReviewCard[]) => Array.isArray(value));
      return ReviewPolicy.normalize(rows || []);
    } catch { this.snapshots.block('cards'); throw new Error('复习记录损坏或无法读取，请先保留设备数据'); }
  }
  async save(context: Context, cards: ReviewCard[]): Promise<void> {
    const prefs = await this.ensure(context);
    try { await this.snapshots.write(prefs, 'cards', JSON.stringify(cards)); }
    catch (error) { throw new Error('复习记录保存失败；' + (error as Error).message); }
  }
}
