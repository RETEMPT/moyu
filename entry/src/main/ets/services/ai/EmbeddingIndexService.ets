/**
 * 片段向量索引
 *
 * 以 chunkId 为键在内存里缓存向量，避免每次提问都重新向量化整个库。
 * 档案或向量模型一旦变化（signature 不同）就整体失效重算，
 * 否则会拿 A 模型的向量去和 B 模型的向量比余弦，结果无意义。
 */
import { Chunk } from '../../common/types/RagTypes';
import { ModelProfile } from '../../common/types/ModelConfig';
import { EmbeddingProvider, createEmbeddingProvider } from './EmbeddingProvider';

/** 单次请求的向量化条数，太大的话部分网关会直接 413 */
const EMBED_BATCH: number = 32;

export class EmbeddingIndexService {
  private static instance: EmbeddingIndexService | null = null;

  private vectors: Map<string, number[]> = new Map();
  /** 当前向量所属的 (档案 id + 向量模型) 组合 */
  private signature: string = '';

  static getInstance(): EmbeddingIndexService {
    if (EmbeddingIndexService.instance === null) {
      EmbeddingIndexService.instance = new EmbeddingIndexService();
    }
    return EmbeddingIndexService.instance;
  }

  /** 该档案是否具备向量检索条件 */
  static canEmbed(profile: ModelProfile): boolean {
    const model: string = profile.embeddingModelId ?? '';
    return model.length > 0 && profile.apiKey.length > 0 && profile.protocol !== 'anthropic';
  }

  private signatureOf(profile: ModelProfile): string {
    return `${profile.id}::${profile.embeddingModelId ?? ''}::${profile.baseUrl}`;
  }

  /** 丢弃全部缓存（换档案或换模型时调用） */
  clear(): void {
    this.vectors.clear();
    this.signature = '';
  }

  /**
   * 确保这批片段都有向量。
   * @returns 是否成功（false 时调用方应退化为关键词检索）
   */
  async ensure(profile: ModelProfile, chunks: Chunk[]): Promise<boolean> {
    if (!EmbeddingIndexService.canEmbed(profile)) {
      return false;
    }
    const provider: EmbeddingProvider | null = createEmbeddingProvider(profile.protocol);
    if (provider === null) {
      return false;
    }

    const signature: string = this.signatureOf(profile);
    if (signature !== this.signature) {
      this.clear();
      this.signature = signature;
    }

    const missing: Chunk[] = [];
    for (const c of chunks) {
      const cached: number[] | undefined = this.vectors.get(c.id);
      if (cached === undefined || cached.length === 0) {
        missing.push(c);
      }
    }
    if (missing.length === 0) {
      return true;
    }

    try {
      for (let start = 0; start < missing.length; start += EMBED_BATCH) {
        const batch: Chunk[] = missing.slice(start, start + EMBED_BATCH);
        const texts: string[] = [];
        for (const c of batch) {
          // 带上标题与章节路径，让片段脱离上下文也有语义
          texts.push(`${c.noteTitle}\n${c.headingPath}\n${c.text}`);
        }
        const vecs: number[][] = await provider.embed(profile, texts);
        if (vecs.length !== batch.length) {
          return false;
        }
        for (let i = 0; i < batch.length; i++) {
          if (vecs[i].length > 0) {
            this.vectors.set(batch[i].id, vecs[i]);
          }
        }
      }
    } catch (error) {
      console.error(`片段向量化失败: ${JSON.stringify(error)}`);
      return false;
    }
    return true;
  }

  /** 向量化单条查询文本 */
  async embedQuery(profile: ModelProfile, query: string): Promise<number[]> {
    const provider: EmbeddingProvider | null = createEmbeddingProvider(profile.protocol);
    if (provider === null) {
      return [];
    }
    try {
      const vecs: number[][] = await provider.embed(profile, [query]);
      return vecs.length > 0 ? vecs[0] : [];
    } catch (error) {
      console.error(`查询向量化失败: ${JSON.stringify(error)}`);
      return [];
    }
  }

  get(chunkId: string): number[] | null {
    const v: number[] | undefined = this.vectors.get(chunkId);
    return v === undefined ? null : v;
  }

  size(): number {
    return this.vectors.size;
  }
}
