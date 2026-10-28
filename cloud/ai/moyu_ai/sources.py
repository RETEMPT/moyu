"""Bounded text import, source coordinates and Chinese/Latin lexical retrieval."""

import hashlib
import math
from pathlib import Path
import re
import unicodedata

MAX_FILE_BYTES = 1024 * 1024
CHUNK_CHARS = 1200


def digest(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def read_source(path):
    path = Path(path)
    if path.suffix.lower() not in {".txt", ".md", ".markdown"}:
        raise ValueError("仅支持 UTF-8 TXT / Markdown；PDF、图片、Office 请先提取并校对文字。")
    with path.open("rb") as stream:
        raw = stream.read(MAX_FILE_BYTES + 1)
    if len(raw) > MAX_FILE_BYTES:
        raise ValueError("单份资料不能超过 1 MiB。")
    text = raw.decode("utf-8-sig").replace("\r\n", "\n").replace("\r", "\n")
    if not text.strip() or any(ord(c) < 32 and c not in "\n\t" for c in text):
        raise ValueError("资料为空或含二进制控制字符。")
    return text


def chunks(text):
    """Keep exact substrings; long lines are split without losing characters."""
    start, line = 0, 1
    while start < len(text):
        end = min(start + CHUNK_CHARS, len(text))
        if end < len(text):
            newline = text.rfind("\n", start + CHUNK_CHARS // 2, end)
            if newline >= 0:
                end = newline + 1
        part = text[start:end]
        yield {"text": part, "line_start": line,
               "line_end": line + part.rstrip("\n").count("\n")}
        line += part.count("\n")
        start = end


def terms(text):
    normalized = unicodedata.normalize("NFKC", text).lower()
    result = set(re.findall(r"[a-z0-9_]+", normalized))
    for word in re.findall(r"[\u3400-\u9fff]+", normalized):
        # Bigrams distinguish Chinese topics while single characters support short queries.
        result.update(word)
        result.update(word[i:i + 2] for i in range(len(word) - 1))
    return result


def retrieve(rows, query, limit=6):
    if not 1 <= limit <= 12:
        raise ValueError("检索数量须为 1–12。")
    query_terms = terms(query)
    # Multi-character queries must share a word/bigram, not just an incidental 汉字.
    if any(len(term) > 1 for term in query_terms):
        query_terms = {term for term in query_terms if len(term) > 1}
    if not query_terms:
        return []
    tokenized = [(row, terms(row["text"])) for row in rows]
    frequency = {term: sum(term in tokens for _, tokens in tokenized) for term in query_terms}
    ranked = []
    for row, tokens in tokenized:
        matches = tokens & query_terms
        if not matches:
            continue
        score = sum((2 if len(term) > 1 else 0.3) *
                    (1 + math.log((len(rows) + 1) / (frequency[term] + 1)))
                    for term in matches) / (1 + math.log1p(len(tokens)) * 0.1)
        ranked.append({**row, "score": round(score, 6)})
    return sorted(ranked, key=lambda item: (-item["score"], item["id"]))[:limit]
