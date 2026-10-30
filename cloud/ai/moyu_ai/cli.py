"""JSON CLI. All data lives in a separate explicit workspace."""

import argparse
import json
from pathlib import Path
import sqlite3
import sys

from .provider import profile
from .exchange import MAX_BYTES, capabilities, decode
from .sources import retrieve
from .store import Store
from .tutor import OPERATIONS, Tutor

DEFAULT_WORKSPACE = Path(__file__).resolve().parents[1] / ".data"


def parser():
    root = argparse.ArgumentParser(description="墨语独立 AI 学习实验，不连接主应用。")
    root.add_argument("--workspace", type=Path, default=DEFAULT_WORKSPACE, help="独立数据目录")
    groups = root.add_subparsers(dest="group", required=True)

    groups.add_parser("capabilities")
    groups.add_parser("validate-result").add_argument("file", type=Path)

    workspace = groups.add_parser("workspace").add_subparsers(dest="action", required=True)
    workspace.add_parser("backup").add_argument("destination", type=Path, help="尚不存在的新目录")

    notebooks = groups.add_parser("notebook").add_subparsers(dest="action", required=True)
    notebooks.add_parser("create").add_argument("name")
    notebooks.add_parser("list")

    sources = groups.add_parser("source").add_subparsers(dest="action", required=True)
    add = sources.add_parser("add")
    add.add_argument("notebook")
    add.add_argument("files", nargs="+", type=Path)
    add.add_argument("--name", help="稳定的资料名称；只用于单文件")
    sources.add_parser("list").add_argument("notebook")
    remove = sources.add_parser("remove")
    remove.add_argument("notebook")
    remove.add_argument("name")
    search = sources.add_parser("search")
    search.add_argument("notebook")
    search.add_argument("query")
    search.add_argument("--limit", type=int, default=6)

    memories = groups.add_parser("memory").add_subparsers(dest="action", required=True)
    memories.add_parser("list").add_argument("notebook")
    remember = memories.add_parser("set")
    remember.add_argument("notebook")
    remember.add_argument("topic")
    remember.add_argument("--status", required=True, choices=["new", "learning", "review", "mastered"])
    remember.add_argument("--note", default="")
    forget = memories.add_parser("forget")
    forget.add_argument("notebook")
    forget.add_argument("topic")

    jobs = groups.add_parser("job").add_subparsers(dest="action", required=True)
    prepare = jobs.add_parser("prepare")
    prepare.add_argument("notebook")
    prepare.add_argument("--operation", choices=OPERATIONS, required=True)
    prepare.add_argument("--goal", required=True)
    prepare.add_argument("--model", required=True, help="用户已部署的 Ollama 模型 ID")
    prepare.add_argument("--endpoint", default="http://127.0.0.1:11434")
    prepare.add_argument("--max-output-tokens", type=int, default=1600)
    prepare.add_argument("--limit", type=int, default=6)
    prepare.add_argument("--include-memory", action="store_true", help="预览并发送本笔记本的主动学习记录")
    for command in ["show", "accept", "abandon", "delete"]:
        jobs.add_parser(command).add_argument("id")
    run = jobs.add_parser("run")
    run.add_argument("id")
    run.add_argument("--approve", required=True, help="job show 中的完整 preview_digest")
    revise = jobs.add_parser("revise")
    revise.add_argument("id")
    revise.add_argument("--file", type=Path, required=True, help="仅含 title/sections/cards/warnings 的 UTF-8 JSON")
    export = jobs.add_parser("export")
    export.add_argument("id")
    export.add_argument("path", type=Path)
    export.add_argument("--portable", action="store_true", help="仅导出版本化学习结果与出处，不含完整任务快照")
    jobs.add_parser("list").add_argument("notebook")
    return root


def execute(store, args):
    if args.group == "workspace":
        return store.backup(args.destination)
    if args.group == "notebook":
        return store.notebook(args.name) if args.action == "create" else [
            dict(row) for row in store.db.execute("SELECT * FROM notebooks ORDER BY name")]
    if args.group == "source":
        if args.action == "add":
            if len(args.files) > 20 or (args.name and len(args.files) != 1):
                raise ValueError("每批最多 20 个文件；--name 只适用于单文件。")
            # Each file has its own transaction; errors report partial success explicitly.
            results = []
            for source in args.files:
                try:
                    results.append({"file": str(source), "source": store.import_source(args.notebook, source, args.name)})
                except (ValueError, OSError, UnicodeError) as exc:
                    results.append({"file": str(source), "error": str(exc)})
            return {"files": results, "partial_failure": any("error" in item for item in results)}
        if args.action == "list":
            return store.documents(args.notebook)
        if args.action == "remove":
            return store.remove_source(args.notebook, args.name)
        return retrieve(store.source_chunks(args.notebook), args.query, args.limit)
    if args.group == "memory":
        if args.action == "set":
            return store.remember(args.notebook, args.topic, args.status, args.note)
        if args.action == "forget":
            return store.forget(args.notebook, args.topic)
        return store.memories(args.notebook)

    tutor = Tutor(store)
    if args.action == "prepare":
        return tutor.prepare(args.notebook, args.operation, args.goal,
                             profile(args.endpoint, args.model, args.max_output_tokens),
                             args.include_memory, args.limit)
    if args.action == "list":
        store.require_notebook(args.notebook)
        return [dict(row) for row in store.db.execute(
            "SELECT id,state,error,created_at FROM jobs WHERE notebook=? ORDER BY rowid DESC", (args.notebook,))]
    if args.action == "show":
        return store.job(args.id)
    if args.action == "run":
        return tutor.run(args.id, args.approve)
    if args.action == "accept":
        return tutor.accept(args.id)
    if args.action == "abandon":
        return tutor.abandon(args.id)
    if args.action == "delete":
        return tutor.delete(args.id)
    if args.action == "revise":
        with args.file.open("rb") as stream:
            raw = stream.read(32769)
        if len(raw) > 32768:
            raise ValueError("编辑稿超过 32 KiB。")
        return tutor.revise(args.id, json.loads(raw.decode("utf-8-sig")))
    return tutor.export(args.id, args.path, args.portable)


def main(argv=None):
    args = parser().parse_args(argv)
    store = None
    try:
        if args.group == "capabilities":
            result = capabilities()
        elif args.group == "validate-result":
            with args.file.open("rb") as stream:
                value = decode(stream.read(MAX_BYTES + 1))
            result = {"valid": True, "job_id": value["job_id"], "operation": value["operation"],
                      "sources": len(value["sources"]), "cards": len(value["cards"])}
        else:
            store = Store(args.workspace)
            result = execute(store, args)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 1 if isinstance(result, dict) and result.get("partial_failure") else 0
    except (ValueError, OSError, sqlite3.Error, RecursionError) as exc:
        print(json.dumps({"error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print('{"error":"操作已中断；已发送的远端请求可能仍在执行。"}', file=sys.stderr)
        return 130
    finally:
        if store:
            store.close()
