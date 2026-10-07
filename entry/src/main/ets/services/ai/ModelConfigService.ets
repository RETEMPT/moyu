import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ModelProfile, createDefaultProfile } from '../../common/types/ModelConfig';
import { ModelProfilePolicy } from './ModelProfilePolicy';
import { HuksCredentialStore } from './HuksCredentialStore';
import { SerialTaskQueue } from '../storage/SerialTaskQueue';

const ACTIVE_STORAGE_KEY: string = 'flowmindActiveModelProfileId';

/** Serialized metadata commits; secrets are encrypted before metadata ever references them. */
export class ModelConfigService {
  private static instance: ModelConfigService | null = null;
  private prefs: preferences.Preferences | null = null;
  private credentials: HuksCredentialStore = new HuksCredentialStore();
  private queue: SerialTaskQueue = new SerialTaskQueue();
  private unsafe: boolean = false;
  static getInstance(): ModelConfigService {
    if (!ModelConfigService.instance) { ModelConfigService.instance = new ModelConfigService(); }
    return ModelConfigService.instance;
  }
  async init(context: Context): Promise<void> {
    if (this.prefs) { return; }
    await this.credentials.init(context);
    this.prefs = await preferences.getPreferences(context, { name: 'flowmind_model' });
  }
  private ready(): preferences.Preferences {
    if (!this.prefs || this.unsafe) { throw new Error('模型配置需要重新读取，请重启后核对'); }
    return this.prefs;
  }
  private async stored(): Promise<ModelProfile[]> {
    const raw = await this.ready().get('profiles', '[]');
    try {
      const parsed = JSON.parse(raw as string) as ModelProfile[];
      if (!Array.isArray(parsed)) { throw new Error('invalid profiles'); }
      const profiles: ModelProfile[] = [];
      for (const item of parsed) {
        const restored = ModelProfilePolicy.restore(item);
        if (!restored || (item.credentialRef !== undefined && restored.credentialRef !== item.credentialRef) || profiles.some((p: ModelProfile) => p.id === restored.id)) { throw new Error('invalid profile'); }
        profiles.push(restored);
      }
      return profiles;
    } catch {
      this.unsafe = true;
      throw new Error('模型配置格式异常，原数据已保留；本地学习功能仍可使用');
    }
  }
  private async loadLocked(): Promise<ModelProfile[]> {
    const stored = await this.stored();
    if (!stored.length) { return [createDefaultProfile()]; }
    const profiles: ModelProfile[] = [];
    let legacy = false;
    for (const item of stored) {
      const profile = JSON.parse(JSON.stringify(item)) as ModelProfile;
      if (profile.apiKey) { legacy = true; }
      else if (profile.credentialRef) {
        try { profile.apiKey = await this.credentials.read(profile.id, profile.credentialRef); profile.credentialUnavailable = false; }
        catch { profile.apiKey = ''; profile.credentialUnavailable = true; }
      }
      profiles.push(profile);
    }
    // Keep old metadata intact if encryption or the metadata flush fails.
    if (legacy) { await this.commit(profiles); }
    return profiles;
  }
  loadProfiles(): Promise<ModelProfile[]> { return this.queue.run<ModelProfile[]>(() => this.loadLocked()); }
  getActiveProfileId(): Promise<string> { return this.queue.run<string>(() => this.activeLocked()); }
  private async activeLocked(): Promise<string> {
    const id = await this.ready().get('activeProfileId', '');
    return typeof id === 'string' ? id : '';
  }
  getActiveProfile(): Promise<ModelProfile> {
    return this.queue.run<ModelProfile>(async () => {
      const profiles = await this.loadLocked();
      const id = await this.activeLocked();
      return profiles.find((p: ModelProfile) => p.id === id) || profiles[0];
    });
  }
  private async commit(profiles: ModelProfile[], active?: string): Promise<void> {
    const prefs = this.ready();
    const oldRaw = await prefs.get('profiles', '[]');
    const oldActive = await prefs.get('activeProfileId', '');
    const old = await this.stored();
    const created: string[] = [];
    const metadata: ModelProfile[] = [];
    try {
      for (const runtime of profiles) {
        const clean = JSON.parse(JSON.stringify(runtime)) as ModelProfile;
        const previous = old.find((p: ModelProfile) => p.id === clean.id);
        let same = false;
        if (clean.apiKey && previous?.credentialRef) {
          try { same = await this.credentials.read(clean.id, previous.credentialRef) === clean.apiKey; } catch { same = false; }
        }
        if (clean.apiKey) {
          clean.credentialRef = same ? previous!.credentialRef : await this.credentials.write(clean.id, clean.apiKey);
          if (!same) { created.push(clean.credentialRef!); }
        } else { clean.credentialRef = clean.credentialUnavailable ? previous?.credentialRef : undefined; }
        clean.apiKey = '';
        clean.credentialUnavailable = undefined;
        metadata.push(clean);
      }
      await prefs.put('profiles', JSON.stringify(metadata));
      if (active !== undefined) { await prefs.put('activeProfileId', active); }
      await prefs.flush();
    } catch {
      try { await prefs.put('profiles', oldRaw); await prefs.put('activeProfileId', oldActive); }
      catch { this.unsafe = true; }
      for (const ref of created) { try { await this.credentials.remove(ref); } catch { /* Encrypted orphan is never used. */ } }
      throw new Error('模型配置保存未完成，旧配置已保留，请重试');
    }
    for (const previous of old) {
      if (previous.credentialRef && !metadata.some((p: ModelProfile) => p.credentialRef === previous.credentialRef)) {
        try { await this.credentials.remove(previous.credentialRef); } catch { /* Cleanup cannot invalidate a committed profile. */ }
      }
    }
  }
  saveProfiles(profiles: ModelProfile[]): Promise<void> {
    const snapshot = JSON.parse(JSON.stringify(profiles)) as ModelProfile[];
    return this.queue.run<void>(async () => {
      if (!snapshot.length || snapshot.some((p: ModelProfile, i: number) => !ModelProfilePolicy.restore(p) || snapshot.findIndex((q: ModelProfile) => p.id === q.id) !== i)) { throw new Error('模型档案列表无效'); }
      await this.commit(snapshot);
    });
  }
  setActiveProfileId(id: string): Promise<void> {
    return this.queue.run<void>(async () => {
      const profiles = await this.loadLocked();
      if (!profiles.some((p: ModelProfile) => p.id === id)) { throw new Error('模型档案不存在'); }
      await this.commit(profiles, id);
      AppStorage.setOrCreate<string>(ACTIVE_STORAGE_KEY, id);
    });
  }
  private save(profile: ModelProfile, activate: boolean): Promise<ModelProfile[]> {
    const snapshot = JSON.parse(JSON.stringify(profile)) as ModelProfile;
    return this.queue.run<ModelProfile[]>(async () => {
      const error = ModelProfilePolicy.validate(snapshot);
      if (error) { throw new Error(error); }
      const profiles = await this.loadLocked();
      const index = profiles.findIndex((p: ModelProfile) => p.id === snapshot.id);
      if (index >= 0) { profiles[index] = snapshot; } else { profiles.push(snapshot); }
      await this.commit(profiles, activate ? snapshot.id : undefined);
      if (activate) { AppStorage.setOrCreate<string>(ACTIVE_STORAGE_KEY, snapshot.id); }
      AppStorage.setOrCreate<number>('flowmindModelRevision', Date.now());
      return this.loadLocked();
    });
  }
  upsertProfile(profile: ModelProfile): Promise<ModelProfile[]> { return this.save(profile, false); }
  saveAndActivate(profile: ModelProfile): Promise<ModelProfile[]> { return this.save(profile, true); }
  deleteProfile(id: string): Promise<ModelProfile[]> {
    return this.queue.run<ModelProfile[]>(async () => {
      const profiles = await this.loadLocked();
      if (profiles.length <= 1) { return profiles; }
      const filtered = profiles.filter((p: ModelProfile) => p.id !== id);
      const active = await this.activeLocked();
      const next = active === id ? filtered[0].id : active;
      await this.commit(filtered, next);
      AppStorage.setOrCreate<string>(ACTIVE_STORAGE_KEY, next);
      AppStorage.setOrCreate<number>('flowmindModelRevision', Date.now());
      return filtered;
    });
  }
  clearCredentials(id?: string): Promise<void> {
    return this.queue.run<void>(async () => {
      // Does not decrypt or migrate legacy keys, so removal works when HUKS is unavailable.
      const profiles = await this.stored();
      for (const profile of profiles) {
        if (id !== undefined && profile.id !== id) { profile.credentialUnavailable = !!profile.credentialRef; continue; }
        profile.apiKey = ''; profile.credentialRef = undefined; profile.credentialUnavailable = false;
        profile.remoteConsentVersion = undefined; profile.remoteConsentEndpoint = undefined;
        profile.remoteConsentProtocol = undefined; profile.remoteConsentedAt = undefined;
      }
      await this.commit(profiles);
      AppStorage.setOrCreate<number>('flowmindModelRevision', Date.now());
    });
  }
  resetProfiles(): Promise<void> {
    return this.queue.run<void>(async () => {
      if (!this.prefs) { throw new Error('模型配置尚未初始化'); }
      const prefs = this.prefs;
      const oldProfiles = await prefs.get('profiles', '[]');
      const oldActive = await prefs.get('activeProfileId', '');
      const profile = createDefaultProfile();
      try {
        await prefs.put('profiles', JSON.stringify([profile]));
        await prefs.put('activeProfileId', profile.id);
        await prefs.flush();
      } catch {
        try { await prefs.put('profiles', oldProfiles); await prefs.put('activeProfileId', oldActive); } catch { this.unsafe = true; }
        throw new Error('模型配置重置未完成，请重启后核对');
      }
      this.unsafe = false;
      try { await this.credentials.clear(); } catch { /* Unreferenced ciphertext can remain until app data is cleared. */ }
      AppStorage.setOrCreate<string>(ACTIVE_STORAGE_KEY, profile.id);
      AppStorage.setOrCreate<number>('flowmindModelRevision', Date.now());
    });
  }
}
export { ACTIVE_STORAGE_KEY };
