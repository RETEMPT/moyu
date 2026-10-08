/** Small, bounded Chinese keyword tokenizer; this is lexical matching, not semantic search. */
export function searchTerms(query: string): string[] {
  const cleaned = query.toLocaleLowerCase().replace(/请问|请|帮我|关于|是什么|怎么|如何|为什么|有哪些|的|了|吗|呢|一下/g, ' ');
  const words = cleaned.match(/[a-z0-9_]+|[\u4e00-\u9fff]+/g) || [];
  const terms: string[] = [];
  for (const word of words.slice(0, 24)) {
    if (!terms.includes(word)) { terms.push(word); }
    if (/^[\u4e00-\u9fff]+$/.test(word) && word.length > 2) {
      for (let i = 0; i < Math.min(word.length - 1, 24); i++) {
        const pair = word.slice(i, i + 2);
        if (!terms.includes(pair)) { terms.push(pair); }
      }
    }
  }
  return terms.slice(0, 64);
}
