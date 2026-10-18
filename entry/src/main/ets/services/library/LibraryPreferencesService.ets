import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { SnapshotStore } from '../storage/SnapshotStore';

export interface LibraryPreferences { view: string; sort: string; ascending: boolean; }

export class LibraryPreferencesService {
  private snapshots: SnapshotStore = new SnapshotStore();

  async load(context: Context): Promise<LibraryPreferences> {
    const store = await preferences.getPreferences(context, { name: 'flowmind_library' });
    return await this.snapshots.read<LibraryPreferences>(store, 'display', (value: LibraryPreferences) =>
      value !== null && ['list', 'shelf', 'timeline'].includes(value.view) && ['update', 'create', 'title', 'read'].includes(value.sort) &&
        typeof value.ascending === 'boolean') || { view: 'shelf', sort: 'update', ascending: false };
  }

  async save(context: Context, value: LibraryPreferences): Promise<void> {
    const json = JSON.stringify(value);
    const store = await preferences.getPreferences(context, { name: 'flowmind_library' });
    await this.snapshots.write(store, 'display', json);
  }
}
