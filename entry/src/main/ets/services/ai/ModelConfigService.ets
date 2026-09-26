/**
 * 模型配置持久化服务
 *
 * 读写模型档案列表和当前激活档案。采用 preferences 落盘，
 * 与 NoteStorageService 同范式：JSON 序列化，flush 即写。
 *
 * 热更新：通过 AppStorage key 广播 activeProfileId 变化，
 * 订阅方（AI工作台、设置面板）用 @StorageProp 感知。
 */
import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ModelProfile, createDefaultProfile } from '../../common/types/ModelConfig';

const PREFERENCES_NAME: string = 'flowmind_model';
const PROFILES_KEY: string = 'profiles';
const ACTIVE_KEY: string = 'activeProfileId';
const ACTIVE_STORAGE_KEY: string = 'flowmindActiveModelProfileId';

export class ModelConfigService {
  private static instance: ModelConfigService | null = null;
  private prefs: preferences.Preferences | null = null;

  static getInstance(): ModelConfigService {
    if (ModelConfigService.instance === null) {
      ModelConfigService.instance = new ModelConfigService();
    }
    return ModelConfigService.instance;
  }

  /** 初始化，惰性建 Preferences；context 传 null 时跳过（后续操作会抛错） */
  async init(context: Context): Promise<void> {
    if (this.prefs !== null) {
      return;
    }
    this.prefs = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
  }

  /** 读取全部模型档案 */
  async loadProfiles(): Promise<ModelProfile[]> {
    const prefs: preferences.Preferences = await this.ensureInit();
    const raw = await prefs.get(PROFILES_KEY, '[]');
    try {
      const parsed: ModelProfile[] = JSON.parse(raw as string) as ModelProfile[];
      if (!Array.isArray(parsed) || parsed.length === 0) {
        return [createDefaultProfile()];
      }
      let needsSave: boolean = false;
      for (const p of parsed) {
        p.apiKey = this.sanitizeKey(p.apiKey);
        if (p.modelId === 'deepseek-v4') {
          p.modelId = 'deepseek-v4-pro';
          needsSave = true;
        }
      }
      if (needsSave) {
        await prefs.put(PROFILES_KEY, JSON.stringify(parsed));
        await prefs.flush();
      }
      return parsed;
    } catch {
      return [createDefaultProfile()];
    }
  }

  /**
   * 修复早期版本损坏的密钥。
   *
   * 旧版设置面板把 TextInput 的文本绑成手写打码串 `maskKey(value)`，
   * 又把 onChange 的内容写回 apiKey，导致存进去的是形如 `****sk-xxxx` 的串。
   * 密钥里不会出现 `*`，所以含 `*` 的一律判定为损坏，清空逼用户重填，
   * 而不是拿着一个必然 401 的坏值反复重试。
   */
  private sanitizeKey(key: string | undefined): string {
    if (key === undefined) {
      return '';
    }
    return key.includes('*') ? '' : key;
  }

  /** 保存全部模型档案 */
  async saveProfiles(profiles: ModelProfile[]): Promise<void> {
    const prefs: preferences.Preferences = await this.ensureInit();
    await prefs.put(PROFILES_KEY, JSON.stringify(profiles));
    await prefs.flush();
  }

  /** 读取当前激活档案 ID */
  async getActiveProfileId(): Promise<string> {
    const prefs: preferences.Preferences = await this.ensureInit();
    const stored = await prefs.get(ACTIVE_KEY, '');
    return typeof stored === 'string' ? stored : '';
  }

  /** 设置激活档案 ID 并广播热更新 */
  async setActiveProfileId(id: string): Promise<void> {
    const prefs: preferences.Preferences = await this.ensureInit();
    await prefs.put(ACTIVE_KEY, id);
    await prefs.flush();
    AppStorage.setOrCreate<string>(ACTIVE_STORAGE_KEY, id);
  }

  /** 读取激活档案（回退为第一个） */
  async getActiveProfile(): Promise<ModelProfile> {
    const profiles: ModelProfile[] = await this.loadProfiles();
    const activeId: string = await this.getActiveProfileId();
    for (const p of profiles) {
      if (p.id === activeId) {
        return p;
      }
    }
    return profiles[0];
  }

  /** 保存单个档案（upsert）并落盘 */
  async upsertProfile(profile: ModelProfile): Promise<ModelProfile[]> {
    const profiles: ModelProfile[] = await this.loadProfiles();
    let found: boolean = false;
    for (let i = 0; i < profiles.length; i++) {
      if (profiles[i].id === profile.id) {
        profiles[i] = profile;
        found = true;
        break;
      }
    }
    if (!found) {
      profiles.push(profile);
    }
    await this.saveProfiles(profiles);
    return profiles;
  }

  /** 删除档案；不允许删除最后一个 */
  async deleteProfile(id: string): Promise<ModelProfile[]> {
    const profiles: ModelProfile[] = await this.loadProfiles();
    if (profiles.length <= 1) {
      return profiles;
    }
    const filtered: ModelProfile[] = profiles.filter((p: ModelProfile) => p.id !== id);
    await this.saveProfiles(filtered);
    return filtered;
  }

  private async ensureInit(): Promise<preferences.Preferences> {
    if (this.prefs === null) {
      throw new Error('ModelConfigService 尚未初始化，请先调用 init(context)');
    }
    return this.prefs;
  }
}

export { ACTIVE_STORAGE_KEY };
