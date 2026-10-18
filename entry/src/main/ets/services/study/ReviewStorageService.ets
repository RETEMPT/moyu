import { Context } from '@kit.AbilityKit';
import { ReviewCard } from '../../common/types/StudyTypes';
import { ReviewPolicy } from './ReviewPolicy';
import { DomainStorage } from '../storage/DomainStorage';

export class ReviewStorageService {
  private domain: DomainStorage = new DomainStorage();
  async load(context: Context): Promise<ReviewCard[]> {
    try {
      const rows = await this.domain.load<ReviewCard[]>(context, 'cards', 'flowmind_study', 'cards',
        (value: ReviewCard[]) => Array.isArray(value) && ReviewPolicy.normalize(value).length === value.length);
      return ReviewPolicy.normalize(rows || []);
    } catch { throw new Error('复习记录损坏或无法读取，请先保留设备数据'); }
  }
  async save(context: Context, cards: ReviewCard[]): Promise<void> {
    try { await this.domain.save<ReviewCard[]>(context, 'cards', 'flowmind_study', 'cards', cards,
      (value: ReviewCard[]) => Array.isArray(value) && ReviewPolicy.normalize(value).length === value.length); }
    catch (error) { throw new Error('复习记录保存失败；' + (error as Error).message); }
  }
}
