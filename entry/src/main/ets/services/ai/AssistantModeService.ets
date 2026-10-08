import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { SerialTaskQueue } from '../storage/SerialTaskQueue';
import { REMOTE_AI_ENABLED } from '../../common/constants/RuntimeCapabilities';

export type AssistantMode = 'local' | 'remote';
export const ASSISTANT_MODE_KEY: string = 'flowmindAssistantMode';

/** A separate preference keeps offline help usable even when model credentials cannot load. */
export class AssistantModeService {
  private static instance: AssistantModeService = new AssistantModeService();
  private prefs: preferences.Preferences | null = null;
  private queue: SerialTaskQueue = new SerialTaskQueue();
  static getInstance(): AssistantModeService { return AssistantModeService.instance; }

  async init(context: Context): Promise<void> {
    await this.queue.run<void>(async () => {
      if (this.prefs) { return; }
      const prefs = await preferences.getPreferences(context, { name: 'flowmind_assistant' });
      const mode = await prefs.get('mode', 'local');
      this.prefs = prefs;
      AppStorage.setOrCreate<string>(ASSISTANT_MODE_KEY, REMOTE_AI_ENABLED && mode === 'remote' ? 'remote' : 'local');
    });
  }

  setMode(mode: AssistantMode): Promise<void> {
    if (mode === 'remote' && !REMOTE_AI_ENABLED) { return Promise.reject(new Error('此版本使用本地助手')); }
    return this.queue.run<void>(async () => {
      if (!this.prefs) { throw new Error('助手设置尚未就绪，请重试'); }
      const prefs = this.prefs;
      const previous = await prefs.get('mode', 'local');
      try { await prefs.put('mode', mode); await prefs.flush(); }
      catch { await prefs.put('mode', previous); throw new Error('助手设置保存失败，请重试'); }
      AppStorage.setOrCreate<string>(ASSISTANT_MODE_KEY, mode);
    });
  }
}
