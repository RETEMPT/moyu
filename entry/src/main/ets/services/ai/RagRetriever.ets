import { ChunkIndexService } from './ChunkIndexService';
import { EmbeddingIndexService } from './EmbeddingIndexService';
import { MarkdownDocument } from '../../common/types/MarkdownDocument';
import { ModelProfile } from '../../common/types/ModelConfig';
import { RetrievalHit, Citation, Chunk } from '../../common/types/RagTypes';

/** 余弦相似度低于该值的片段视为不相关，丢掉以免污染上下文 */
const VECTOR_MIN_SCORE: number = 0.28;

export class RagRetriever {
  private indexer: ChunkIndexService = new ChunkIndexService();
  private embedIndex: EmbeddingIndexService = EmbeddingIndexService.getInstance();

  /** 关键词检索：无网络依赖，永远可用，作为向量检索的兜底 */
  search(documents: MarkdownDocument[], query: string, limit: number = 6): RetrievalHit[] {
    const terms: string[] = query.toLocaleLowerCase().split(/\s+/).filter((item: string) => item.length > 0);
    const hits: RetrievalHit[] = [];
    for (const document of documents) {
      for (const chunk of this.indexer.build(document)) {
        const lower: string = `${chunk.noteTitle} ${chunk.headingPath} ${chunk.text}`.toLocaleLowerCase();
        let matched: number = 0;
        for (const term of terms) {
          if (lower.includes(term)) {
            matched++;
          }
        }
        if (matched > 0) {
          const hit: RetrievalHit = {
            chunk,
            score: matched / Math.max(1, terms.length),
            source: 'keyword'
          };
          hits.push(hit);
        }
      }
    }
    return hits.sort((a: RetrievalHit, b: RetrievalHit) => b.score - a.score).slice(0, limit);
  }

  /**
   * 混合检索：向量为主、关键词兜底。
   *
   * 向量命中能覆盖「换了个说法」的提问（关键词匹配不到）；关键词命中能保证
   * 专有名词、公式符号这类向量容易糊掉的查询仍然准确。两者的分数不同量纲，
   * 这里不做加权求和，而是先取向量结果，再用关键词补齐向量没覆盖到的片段。
   */
  async searchHybrid(
    documents: MarkdownDocument[],
    query: string,
    profile: ModelProfile,
    limit: number = 6
  ): Promise<RetrievalHit[]> {
    const keywordHits: RetrievalHit[] = this.search(documents, query, limit * 2);
    if (!EmbeddingIndexService.canEmbed(profile)) {
      return keywordHits.slice(0, limit);
    }

    const chunks: Chunk[] = [];
    for (const document of documents) {
      const built: Chunk[] = this.indexer.build(document);
      for (const c of built) {
        chunks.push(c);
      }
    }
    if (chunks.length === 0) {
      return keywordHits.slice(0, limit);
    }

    const indexed: boolean = await this.embedIndex.ensure(profile, chunks);
    if (!indexed) {
      return keywordHits.slice(0, limit);
    }
    const queryVec: number[] = await this.embedIndex.embedQuery(profile, query);
    if (queryVec.length === 0) {
      return keywordHits.slice(0, limit);
    }

    const vectorHits: RetrievalHit[] = [];
    for (const c of chunks) {
      const vec: number[] | null = this.embedIndex.get(c.id);
      if (vec === null || vec.length !== queryVec.length) {
        continue;
      }
      const score: number = cosine(queryVec, vec);
      if (score >= VECTOR_MIN_SCORE) {
        vectorHits.push({ chunk: c, score, source: 'vector' });
      }
    }
    vectorHits.sort((a: RetrievalHit, b: RetrievalHit) => b.score - a.score);

    // 向量优先，关键词补齐未覆盖的片段
    const merged: RetrievalHit[] = [];
    const seen: Set<string> = new Set();
    for (const h of vectorHits) {
      if (merged.length >= limit) {
        break;
      }
      merged.push(h);
      seen.add(h.chunk.id);
    }
    for (const h of keywordHits) {
      if (merged.length >= limit) {
        break;
      }
      if (!seen.has(h.chunk.id)) {
        merged.push(h);
        seen.add(h.chunk.id);
      }
    }
    return merged;
  }

  citations(hits: RetrievalHit[]): Citation[] {
    const citations: Citation[] = [];
    for (const hit of hits) {
      const citation: Citation = {
        noteId: hit.chunk.noteId,
        noteTitle: hit.chunk.noteTitle,
        headingPath: hit.chunk.headingPath,
        chunkText: hit.chunk.text,
        score: hit.score,
        startLine: hit.chunk.startLine
      };
      citations.push(citation);
    }
    return citations;
  }
}

function cosine(a: number[], b: number[]): number {
  let dot: number = 0;
  let na: number = 0;
  let nb: number = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na === 0 || nb === 0) {
    return 0;
  }
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}
