import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { SnapshotStore } from './storage/SnapshotStore';

interface PrivacyChoice { version: number; agree: boolean; decidedAt: number; }
/** A notice choice never substitutes for optional AI or device permission consent. */
export class PrivacyNoticeService {
  static readonly VERSION: number = 1;
  private snapshots: SnapshotStore = new SnapshotStore();
  async shown(context: Context): Promise<boolean> {
    const prefs = await preferences.getPreferences(context, { name: 'flowmind_privacy' });
    // An unreadable notice receipt must not block access to local learning data.
    try {
      const raw = await prefs.get('notice', 'null');
      const choice = JSON.parse(raw as string) as PrivacyChoice;
      return choice !== null && choice.version === PrivacyNoticeService.VERSION && typeof choice.agree === 'boolean' && Number.isFinite(choice.decidedAt);
    } catch { return false; }
  }
  async choose(context: Context, agree: boolean): Promise<void> {
    const prefs = await preferences.getPreferences(context, { name: 'flowmind_privacy' });
    await this.snapshots.write(prefs, 'notice', JSON.stringify({ version: PrivacyNoticeService.VERSION, agree, decidedAt: Date.now() } as PrivacyChoice));
  }
}
