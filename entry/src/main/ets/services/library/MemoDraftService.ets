import { Context } from '@kit.AbilityKit';
import { DomainStorage } from '../storage/DomainStorage';
import { MemoDraft } from './QuickMemoService';

/** One independent draft; it never overwrites a note body or library snapshot. */
export class MemoDraftService {
  private domain: DomainStorage = new DomainStorage();
  async load(context: Context): Promise<MemoDraft | null> {
    return this.domain.load<MemoDraft>(context, 'draft', 'flowmind_memo_draft', 'draft', (draft: MemoDraft) => this.valid(draft));
  }
  private valid(draft: MemoDraft): boolean {
    return draft !== null &&
      typeof draft.id === 'string' && /^memo_[a-zA-Z0-9_-]{1,70}$/.test(draft.id) &&
      typeof draft.content === 'string' && draft.content.length <= 12000;
  }
  async save(context: Context, draft: MemoDraft): Promise<void> {
    await this.domain.save<MemoDraft>(context, 'draft', 'flowmind_memo_draft', 'draft', draft, (value: MemoDraft) => this.valid(value));
  }
}
