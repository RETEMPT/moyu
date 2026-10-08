import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { ModelProfile } from '../../common/types/ModelConfig';
import { StreamHandle, StreamHandleImpl } from './ModelProvider';
import { RemoteAiPolicy } from './RemoteAiPolicy';

/** Shared streaming transport; provider parsers retain text, reasoning and tool deltas; no response body appears in errors. */
export class SseHttpClient {
  static async open(profile: ModelProfile, url: string, headers: Record<string, string>, body: string,
    payload: (json: string) => boolean, finish: (error?: string) => void): Promise<StreamHandle> {
    RemoteAiPolicy.assertAllowed(profile);
    const decoder = util.TextDecoder.create('utf-8');
    const client = http.createHttp();
    let closed = false;
    let buffer = '';
    let code = 0;
    let idleTimer: number = -1;
    let totalTimer: number = -1;
    let settle: (status: number) => void = () => {};
    const status = new Promise<number>((resolve) => { settle = resolve; });
    const close = (error?: string, notify: boolean = true): void => {
      if (closed) { return; }
      closed = true;
      if (idleTimer !== -1) { clearTimeout(idleTimer); }
      if (totalTimer !== -1) { clearTimeout(totalTimer); }
      client.destroy();
      if (notify) { finish(error); }
    };
    const consume = (): void => {
      if (closed || code !== 200) { return; }
      const lines = buffer.split('\n'); buffer = lines.pop() || '';
      for (const line of lines) {
        if (closed) { break; }
        const trimmed = line.trim();
        if (!trimmed.startsWith('data:')) { continue; }
        const json = trimmed.slice(5).trim();
        if (json === '[DONE]') { close(); break; }
        try {
          if (payload(json)) { close(); }
          else if (!closed) {
            clearTimeout(idleTimer);
            idleTimer = setTimeout(() => close('模型响应中断，请重试或切换本地助手'), 30000);
          }
        }
        catch (error) {
          // A malformed line is ignored; an explicit provider error ends the request.
          if (!(error instanceof SyntaxError)) { close('AI 服务未能完成流式回答，请重试'); }
        }
      }
    };
    client.on('dataReceive', (data: ArrayBuffer) => {
      if (closed) { return; }
      try { buffer += decoder.decodeToString(new Uint8Array(data), { stream: true }); }
      catch { close('AI 服务文字解码失败，请重试'); return; }
      if (buffer.length > 2 * 1024 * 1024) { close('AI 服务响应片段过大，请缩小资料范围'); return; }
      consume();
    });
    client.on('dataEnd', async () => {
      await status;
      if (closed) { return; }
      try { buffer += decoder.decodeToString(new Uint8Array(), { stream: false }) + '\n'; }
      catch { close('AI 服务文字解码失败，请重试'); return; }
      consume();
      close(code === 200 ? undefined : `AI 服务返回 HTTP ${code}，请核对配置和额度`);
    });
    idleTimer = setTimeout(() => close('模型暂未响应，请重试或切换本地助手'), 45000);
    totalTimer = setTimeout(() => close('本次生成已超时，请缩小资料范围后重试'), 180000);
    try { client.requestInStream(url, { method: http.RequestMethod.POST, header: headers, extraData: body,
      expectDataType: http.HttpDataType.ARRAY_BUFFER, maxRedirects: 0, connectTimeout: 15000, readTimeout: 120000
    }).then((statusCode: number) => {
      code = statusCode; settle(code);
      if (code !== 200) { close(`AI 服务返回 HTTP ${code}，请核对配置和额度`); }
      else { consume(); }
    }).catch(() => { settle(0); close('网络请求失败，请检查连接后重试'); }); }
    catch { settle(0); close('网络请求无法启动，请检查配置后重试'); }
    return new StreamHandleImpl(() => { settle(0); close(undefined, false); });
  }
}
