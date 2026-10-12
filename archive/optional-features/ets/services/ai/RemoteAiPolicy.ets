import { ModelProfile } from '../../common/types/ModelConfig';
import { REMOTE_AI_ENABLED } from '../../common/constants/RuntimeCapabilities';

/** One mandatory policy at every HTTP entry, including connection tests and embeddings. */
export class RemoteAiPolicy {
  static readonly VERSION: number = 1;
  static endpoint(url: string): string { return url.trim().replace(/\/+$/, ''); }
  static local(url: string): boolean {
    return /^http:\/\/(localhost|127\.0\.0\.1|\[::1\])(?::\d+)?(?:\/[^\s?#]*)?$/i.test(url);
  }
  static transportError(p: ModelProfile): string {
    const endpoint = RemoteAiPolicy.endpoint(p.baseUrl);
    if (!/^https?:\/\/[^\s/?#@]+(?:\/[^\s?#]*)?$/i.test(endpoint)) { return '服务地址无效，请使用不含密钥和查询参数的完整地址'; }
    if (/[\r\n]/.test(p.apiKey)) { return '密钥不能包含换行'; }
    if (!/^https:\/\//i.test(endpoint) && (!RemoteAiPolicy.local(endpoint) || p.apiKey.trim().length > 0)) {
      return '远程 AI 必须使用 HTTPS；本机 HTTP 仅允许无密钥服务';
    }
    return '';
  }
  static consented(p: ModelProfile): boolean {
    return p.remoteConsentVersion === RemoteAiPolicy.VERSION &&
      p.remoteConsentEndpoint === RemoteAiPolicy.endpoint(p.baseUrl) &&
      p.remoteConsentProtocol === p.protocol && Number.isFinite(p.remoteConsentedAt) && p.remoteConsentedAt! > 0;
  }
  static assertAllowed(p: ModelProfile): void {
    if (!REMOTE_AI_ENABLED) { throw new Error('此版本使用本地助手，不提供远程模型接入'); }
    const error = RemoteAiPolicy.transportError(p);
    if (error) { throw new Error(error); }
    if (!RemoteAiPolicy.consented(p)) { throw new Error('请在模型设置中确认此服务的数据发送授权；离线功能仍可使用'); }
    if (p.credentialUnavailable) { throw new Error('此设备无法读取旧密钥，请在模型设置中重新填写'); }
  }
}
