import { common, abilityAccessCtrl } from '@kit.AbilityKit';
import { distributedKVStore } from '@kit.ArkData';
import { distributedDeviceManager } from '@kit.DistributedServiceKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { StudyBackup } from '../../common/types/StudyBackup';
import { NearbyTransferPolicy, TransferPart } from './NearbyTransferPolicy';

export interface NearbyDevice { id: string; name: string; }
const BUNDLE: string = 'com.retempt.flowmind';
const STORE: string = 'flowmind_nearby_v1';

/** Explicit trusted-device transfer, not an always-on cloud or a live two-way notebook. */
export class HarmonyNearbyService {
  private manager: distributedKVStore.KVManager | null = null;
  private store: distributedKVStore.SingleKVStore | null = null;
  private devices: distributedDeviceManager.DeviceManager | null = null;
  private cancel: (() => void) | null = null;
  private busy: boolean = false;
  private expired: boolean = false;
  private closed: boolean = false;

  async connect(context: common.UIAbilityContext): Promise<NearbyDevice[]> {
    if (this.closed) { throw new Error('请重新打开附近传递'); }
    if (!canIUse('SystemCapability.DistributedDataManager.KVStore.Core') ||
      !canIUse('SystemCapability.DistributedHardware.DeviceManager')) { throw new Error('此设备暂不支持附近传递，请使用文件备份'); }
    const access = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, ['ohos.permission.DISTRIBUTED_DATASYNC']);
    if (access.authResults.length !== 1 || access.authResults[0] !== 0) { throw new Error('附近设备权限未授权，文件备份仍可使用'); }
    if (this.closed) { throw new Error('附近传递已关闭'); }
    try {
      if (!this.devices) { this.devices = distributedDeviceManager.createDeviceManager(BUNDLE); }
      if (!this.manager) { this.manager = distributedKVStore.createKVManager({ bundleName: BUNDLE, context }); }
      if (!this.store) {
        const manager = this.manager;
        const store = await manager.getKVStore<distributedKVStore.SingleKVStore>(STORE, {
          createIfMissing: true, encrypt: true, backup: false, autoSync: false,
          kvStoreType: distributedKVStore.KVStoreType.SINGLE_VERSION,
          securityLevel: distributedKVStore.SecurityLevel.S2
        });
        if (this.closed) { await manager.closeKVStore(BUNDLE, STORE); throw new Error('附近传递已关闭'); }
        this.store = store;
        // This store holds only temporary transfers. Remove leftovers after interrupted prior sessions.
        for (const entry of await store.getEntries('transfer_')) { await store.delete(entry.key); }
      }
      if (this.closed) { await this.close(); throw new Error('附近传递已关闭'); }
      return this.listDevices();
    } catch (error) {
      await this.close();
      throw new Error('附近传递无法初始化，请核对系统连接、两端版本与授权；可使用文件备份');
    }
  }

  listDevices(): NearbyDevice[] {
    if (!this.devices) { throw new Error('请先连接附近设备'); }
    return this.devices.getAvailableDeviceListSync().filter((device: distributedDeviceManager.DeviceBasicInfo) => !!device.networkId)
      .map((device: distributedDeviceManager.DeviceBasicInfo): NearbyDevice => ({ id: device.networkId || '', name: device.deviceName || '可信设备' }));
  }

  private ensurePeer(id: string): distributedKVStore.SingleKVStore {
    if (this.closed || this.expired || !this.store) { throw new Error('附近连接已结束，请关闭后重新连接'); }
    if (!this.listDevices().some((device: NearbyDevice) => device.id === id)) { throw new Error('目标设备已离线，请刷新列表'); }
    if (this.busy) { throw new Error('上一项传递尚未结束'); }
    return this.store;
  }

  async send(id: string, backup: StudyBackup): Promise<string> {
    const store = this.ensurePeer(id); this.busy = true;
    try {
      const packet = await NearbyTransferPolicy.pack(backup, (content: string) => this.digest(content));
      for (const part of packet.parts) { if (this.closed) { throw new Error('传递已关闭'); } await store.put(part.key, part.value); }
      const prefix = NearbyTransferPolicy.prefix(packet.manifest.id);
      await store.put(prefix + 'manifest', JSON.stringify(packet.manifest));
      await this.sync(store, id, prefix, distributedKVStore.SyncMode.PUSH_ONLY);
      return packet.manifest.id;
    } finally { this.busy = false; }
  }

  async receive(id: string, code: string): Promise<StudyBackup> {
    const prefix = NearbyTransferPolicy.prefix(code.trim());
    const store = this.ensurePeer(id); this.busy = true;
    try {
      await this.sync(store, id, prefix, distributedKVStore.SyncMode.PULL_ONLY);
      const entries = await store.getEntries(prefix);
      const manifest = entries.find((entry: distributedKVStore.Entry) => entry.key === prefix + 'manifest');
      if (!manifest || typeof manifest.value.value !== 'string') { throw new Error('未找到此传递码，请保持发送端页面打开并核对目标设备'); }
      const parts: TransferPart[] = [];
      for (const entry of entries) {
        if (entry.key === prefix + 'manifest') { continue; }
        if (typeof entry.value.value !== 'string') { throw new Error('收到不支持的传递分片'); }
        parts.push({ key: entry.key, value: entry.value.value });
      }
      return NearbyTransferPolicy.unpack(code.trim(), manifest.value.value, parts, (content: string) => this.digest(content));
    } finally { this.busy = false; }
  }

  private sync(store: distributedKVStore.SingleKVStore, id: string, prefix: string, mode: distributedKVStore.SyncMode): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      let settled = false;
      let timer: number = -1;
      const finish = (message: string): void => {
        if (settled) { return; } settled = true;
        if (timer !== -1) { clearTimeout(timer); }
        try { store.off('syncComplete', listener); } catch { /* The store may already be closing. */ }
        this.cancel = null;
        if (message) { this.expired = true; reject(new Error(message)); } else { resolve(); }
      };
      const listener = (results: [string, number][]): void => {
        const peer = results.find((result: [string, number]) => result[0] === id);
        if (peer) { finish(peer[1] === 0 ? '' : '设备同步未完成，请核对两端连接和同一来源的版本'); }
      };
      this.cancel = () => finish('附近传递已关闭');
      try {
        store.on('syncComplete', listener);
        timer = setTimeout(() => finish('设备响应超时，未确认传递完成；请关闭页面后重新连接'), 45000);
        store.sync([id], new distributedKVStore.Query().prefixKey(prefix), mode, 0);
      } catch { finish('无法发起设备同步，请核对两端权限与系统连接'); }
    });
  }

  private async digest(content: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: new util.TextEncoder().encodeInto(content) });
    const hash = await md.digest();
    let result = '';
    for (const value of hash.data) { result += value.toString(16).padStart(2, '0'); }
    return result;
  }

  async close(): Promise<void> {
    this.closed = true;
    if (this.cancel) { this.cancel(); }
    const store = this.store; this.store = null;
    if (store) {
      try { for (const entry of await store.getEntries('transfer_')) { await store.delete(entry.key); } } catch { /* Next connect removes leftovers. */ }
    }
    const manager = this.manager; this.manager = null;
    if (manager) { try { await manager.closeKVStore(BUNDLE, STORE); } catch { /* Already closed. */ } }
    const devices = this.devices; this.devices = null;
    if (devices) { try { distributedDeviceManager.releaseDeviceManager(devices); } catch { /* Already released. */ } }
  }
}
