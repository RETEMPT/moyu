import { Context } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { huks } from '@kit.UniversalKeystoreKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { SnapshotStore } from '../storage/SnapshotStore';

interface EncryptedCredential { version: number; nonce: string; cipher: string; }
const ALIAS: string = 'flowmind.model.credentials.v1';

/** AES-GCM key stays in HUKS. No plaintext fallback; each write gets an immutable reference. */
export class HuksCredentialStore {
  private prefs: preferences.Preferences | null = null;
  private snapshots: SnapshotStore = new SnapshotStore();
  async init(context: Context): Promise<void> {
    this.prefs = await preferences.getPreferences(context, { name: 'flowmind_credentials' });
  }
  private props(purpose: number): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE }
    ];
  }
  private hex(data: Uint8Array): string {
    let text = '';
    for (let i = 0; i < data.length; i++) { text += data[i].toString(16).padStart(2, '0'); }
    return text;
  }
  private bytes(text: string): Uint8Array {
    if (!/^(?:[0-9a-f]{2})+$/.test(text)) { throw new Error('密钥密文格式异常'); }
    const data = new Uint8Array(text.length / 2);
    for (let i = 0; i < data.length; i++) { data[i] = parseInt(text.slice(i * 2, i * 2 + 2), 16); }
    return data;
  }
  private async crypt(profileId: string, purpose: number, nonce: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
    const properties = this.props(purpose);
    properties.push({ tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce });
    properties.push({ tag: huks.HuksTag.HUKS_TAG_ASSOCIATED_DATA, value: new util.TextEncoder().encodeInto(profileId) });
    let input = data;
    if (purpose === huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT) {
      if (data.length < 16) { throw new Error('密钥密文不完整'); }
      properties.push({ tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: data.slice(data.length - 16) });
      input = data.slice(0, data.length - 16);
    }
    const session = await huks.initSession(ALIAS, { properties });
    try {
      const result = await huks.finishSession(session.handle, { properties, inData: input });
      if (!result.outData) { throw new Error('系统密钥保护未返回结果'); }
      return result.outData;
    } catch {
      try { await huks.abortSession(session.handle, { properties }); } catch { /* Session may already be closed. */ }
      throw new Error('系统密钥保护失败，请重新填写密钥');
    }
  }
  async write(profileId: string, key: string): Promise<string> {
    if (!this.prefs || !key || key.length > 8192) { throw new Error('密钥存储尚未就绪或密钥过长'); }
    if (!await huks.isKeyItemExist(ALIAS, { properties: [] })) {
      await huks.generateKeyItem(ALIAS, { properties: this.props(huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT) });
    }
    const nonce = (await cryptoFramework.createRandom().generateRandom(12)).data;
    const cipher = await this.crypt(profileId, huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, nonce, new util.TextEncoder().encodeInto(key));
    const ref = `key_${this.hex(nonce)}`;
    await this.snapshots.write(this.prefs, ref, JSON.stringify({ version: 1, nonce: this.hex(nonce), cipher: this.hex(cipher) } as EncryptedCredential));
    return ref;
  }
  async read(profileId: string, ref: string): Promise<string> {
    if (!this.prefs || !/^key_[0-9a-f]{24}$/.test(ref)) { throw new Error('密钥引用无效'); }
    const packet = await this.snapshots.read<EncryptedCredential>(this.prefs, ref, (p: EncryptedCredential) =>
      p !== null && p.version === 1 && typeof p.nonce === 'string' && p.nonce.length === 24 &&
      typeof p.cipher === 'string' && p.cipher.length >= 32 && p.cipher.length <= 65568);
    if (!packet) { throw new Error('密钥未在此设备保存'); }
    const data = await this.crypt(profileId, huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, this.bytes(packet.nonce), this.bytes(packet.cipher));
    return new util.TextDecoder('utf-8').decode(data);
  }
  async remove(ref: string): Promise<void> {
    if (!this.prefs || !/^key_[0-9a-f]{24}$/.test(ref)) { return; }
    // A tombstone is flushed with rollback semantics; old encrypted values are never reused.
    await this.snapshots.write(this.prefs, ref, 'null');
  }
  async clear(): Promise<void> {
    if (!this.prefs) { throw new Error('密钥存储尚未初始化'); }
    await this.prefs.clear();
    await this.prefs.flush();
  }
}
