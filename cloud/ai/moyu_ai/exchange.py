"""Versioned offline results. No workspace, transport or application access."""

import json
import re

FORMAT = "moyu.learning-result"
VERSION = 1
MAX_BYTES = 128 * 1024
OPERATIONS = ("summary", "qa", "quiz", "report", "plan")
WHITESPACE = "\u0009\u000a\u000b\u000c\u000d\u0020\u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff"


def capabilities():
    return {"format": FORMAT, "version": VERSION, "operations": list(OPERATIONS),
            "max_bytes": MAX_BYTES, "transport": "offline-file",
            "application_entry_enabled": False, "automatic_save": False}


def keys(value, expected):
    if not isinstance(value, dict) or set(value) != set(expected.split()):
        raise ValueError("学习结果字段不符合约定。")


def text(value, maximum, minimum=1):
    if not isinstance(value, str):
        raise ValueError("学习结果文字类型无效。")
    try:
        size = len(value.encode("utf-16-le")) // 2
    except UnicodeError as exc:
        raise ValueError("学习结果含无效 Unicode。") from exc
    if not minimum <= size <= maximum or not value.strip(WHITESPACE):
        raise ValueError("学习结果文字长度无效。")


def items(value, minimum, maximum):
    if not isinstance(value, list) or not minimum <= len(value) <= maximum:
        raise ValueError("学习结果列表长度无效。")


def integer(value):
    if type(value) not in (int, float) or not 1 <= value <= 2147483647 or int(value) != value:
        raise ValueError("学习结果版本或行号无效。")


def validate(value):
    keys(value, "format version job_id operation title sources sections cards warnings")
    if value["format"] != FORMAT or type(value["version"]) not in (int, float) or value["version"] != VERSION:
        raise ValueError("不支持的学习结果格式或版本。")
    if value["operation"] not in OPERATIONS:
        raise ValueError("不支持的学习任务。")
    text(value["job_id"], 80)
    if not re.fullmatch(r"[A-Za-z0-9_-]+", value["job_id"]):
        raise ValueError("任务标识无效。")
    text(value["title"], 200)
    items(value["sources"], 1, 12)
    sources = {}
    for source in value["sources"]:
        keys(source, "id name text revision digest line_start line_end")
        text(source["id"], 100)
        if not re.fullmatch(r"[A-Za-z0-9_-]+", source["id"]) or source["id"] in sources:
            raise ValueError("资料标识无效或重复。")
        text(source["name"], 480)
        text(source["text"], 2400)
        if not isinstance(source["digest"], str) or not re.fullmatch(r"[a-f0-9]{64}", source["digest"]):
            raise ValueError("资料摘要格式无效。")
        for field in ("revision", "line_start", "line_end"):
            integer(source[field])
        if source["line_end"] < source["line_start"]:
            raise ValueError("资料行号范围无效。")
        sources[source["id"]] = source

    def citations(values):
        items(values, 1, 6)
        for citation in values:
            keys(citation, "source_id quote")
            text(citation["source_id"], 100)
            text(citation["quote"], 480, 4)
            source = sources.get(citation["source_id"])
            if not source or citation["quote"] not in source["text"]:
                raise ValueError("引用缺失或不在资料片段内。")

    items(value["sections"], 1, 8)
    for section in value["sections"]:
        keys(section, "heading body citations")
        text(section["heading"], 300)
        text(section["body"], 4000)
        citations(section["citations"])
    items(value["cards"], 0, 8)
    if (value["operation"] == "quiz") != bool(value["cards"]):
        raise ValueError("题卡与任务类型不一致。")
    for card in value["cards"]:
        keys(card, "question answer citations")
        text(card["question"], 300)
        text(card["answer"], 4000)
        citations(card["citations"])
    items(value["warnings"], 0, 16)
    for warning in value["warnings"]:
        text(warning, 1000)
    return value


def decode(raw):
    if len(raw) > MAX_BYTES:
        raise ValueError("学习结果超过 128 KiB。")
    try:
        return validate(json.loads(raw.decode("utf-8")))
    except (UnicodeError, RecursionError) as exc:
        raise ValueError("学习结果编码或嵌套无效。") from exc


def serialize(value):
    raw = (json.dumps(validate(value), ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    decode(raw)
    return raw


def from_job(job):
    """Export only result and source evidence, never prompts, memory or configuration."""
    draft = job["result"]["draft"]
    source_fields = "id name text revision digest line_start line_end".split()
    return {"format": FORMAT, "version": VERSION, "job_id": job["id"],
            "operation": job["payload"]["operation"], "title": draft["title"],
            "sources": [{key: source[key] for key in source_fields} for source in job["payload"]["sources"]],
            "sections": draft["sections"], "cards": draft["cards"],
            "warnings": draft["warnings"] + job["result"]["warnings"]}
