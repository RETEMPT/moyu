"""Single-user SQLite store with transactions and no access to application data."""

from contextlib import contextmanager
from datetime import datetime, timezone
import json
from pathlib import Path
import sqlite3
import time
import uuid

from .sources import chunks, digest, read_source

APP_ID = 0x4D594149  # MYAI; never migrate an unrelated database.
SCHEMA = """
CREATE TABLE notebooks (name TEXT PRIMARY KEY);
CREATE TABLE documents (
 id TEXT PRIMARY KEY, notebook TEXT NOT NULL REFERENCES notebooks(name),
 name TEXT NOT NULL, digest TEXT NOT NULL, revision INTEGER NOT NULL,
 UNIQUE(notebook, name));
CREATE TABLE chunks (
 id TEXT PRIMARY KEY, document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
 text TEXT NOT NULL, line_start INTEGER NOT NULL, line_end INTEGER NOT NULL);
CREATE TABLE memories (
 id TEXT PRIMARY KEY, notebook TEXT NOT NULL REFERENCES notebooks(name),
 topic TEXT NOT NULL, status TEXT NOT NULL, note TEXT NOT NULL,
 revision INTEGER NOT NULL, updated_at TEXT NOT NULL, UNIQUE(notebook, topic));
CREATE TABLE jobs (
 id TEXT PRIMARY KEY, notebook TEXT NOT NULL REFERENCES notebooks(name),
 state TEXT NOT NULL, payload TEXT NOT NULL, preview_digest TEXT NOT NULL,
 result TEXT, error TEXT, created_at TEXT NOT NULL);
"""


def now():
    return datetime.now(timezone.utc).isoformat()


def encode(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def bounded(value, name, maximum=120):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum:
        raise ValueError(f"{name}须为 1–{maximum} 字符。")
    return value.strip()


class Store:
    def __init__(self, workspace):
        self.workspace = Path(workspace).resolve()
        self.workspace.mkdir(parents=True, exist_ok=True)
        self.db = sqlite3.connect(self.workspace / "learning.sqlite3", timeout=5)
        self.db.row_factory = sqlite3.Row
        try:
            self.db.execute("PRAGMA foreign_keys=ON")
            app = self.db.execute("PRAGMA application_id").fetchone()[0]
            version = self.db.execute("PRAGMA user_version").fetchone()[0]
            tables = self.db.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
            if app == 0 and version == 0 and not tables:
                self.db.executescript("BEGIN IMMEDIATE;\n" + SCHEMA +
                                     f"PRAGMA application_id={APP_ID};\nPRAGMA user_version=1;\nCOMMIT;")
            elif app != APP_ID or version != 1:
                raise ValueError("工作区数据库身份或版本不兼容；保留原文件，拒绝覆盖。")
        except BaseException:
            self.db.close()
            raise

    def close(self):
        self.db.close()

    def backup(self, destination):
        """Create a verified, independent workspace; never replace existing data."""
        if self.db.in_transaction:
            raise ValueError("请先结束当前事务再备份。")
        target = Path(destination).absolute()
        # Exclusive directory creation also rejects aliases to the live workspace.
        target.mkdir()
        database = target / "learning.sqlite3"
        connection = None
        started = time.monotonic()

        def progress(status, remaining, total):
            if time.monotonic() - started > 10:
                raise ValueError("备份等待超过 10 秒，请稍后重试。")

        try:
            connection = sqlite3.connect(database, timeout=5)
            self.db.backup(connection, pages=128, progress=progress, sleep=0.05)
            if connection.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                raise ValueError("备份完整性检查失败。")
            if connection.execute("PRAGMA foreign_key_check").fetchone():
                raise ValueError("备份关联检查失败。")
            if connection.execute("SELECT 1 FROM jobs WHERE state='running' LIMIT 1").fetchone():
                raise ValueError("快照含运行中任务，请等待完成或主动放弃后再备份。")
            counts = {table: connection.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
                      for table in ("notebooks", "documents", "chunks", "memories", "jobs")}
        except BaseException:
            if connection:
                connection.close()
                connection = None
            # Only remove files created inside this call's exclusive directory.
            database.unlink(missing_ok=True)
            target.rmdir()
            raise
        finally:
            if connection:
                connection.close()
        return {"workspace": str(target), "counts": counts, "verified": True}

    @contextmanager
    def transaction(self):
        self.db.execute("BEGIN IMMEDIATE")
        try:
            yield
            self.db.commit()
        except BaseException:
            self.db.rollback()
            raise

    def notebook(self, name):
        name = bounded(name, "笔记本名称")
        with self.transaction():
            self.db.execute("INSERT OR IGNORE INTO notebooks VALUES (?)", (name,))
        return {"name": name}

    def require_notebook(self, name):
        if not self.db.execute("SELECT 1 FROM notebooks WHERE name=?", (name,)).fetchone():
            raise ValueError("笔记本不存在，请先 notebook create。")

    def import_source(self, notebook, path, name=None):
        self.require_notebook(notebook)
        name = bounded(name or Path(path).name, "资料名称", 240)
        text = read_source(path)
        source_digest = digest(text)
        with self.transaction():
            old = self.db.execute("SELECT * FROM documents WHERE notebook=? AND name=?",
                                  (notebook, name)).fetchone()
            if old and old["digest"] == source_digest:
                return {**dict(old), "changed": False}
            identity = old["id"] if old else "d" + uuid.uuid4().hex
            revision = old["revision"] + 1 if old else 1
            self.db.execute("INSERT INTO documents VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET "
                            "digest=excluded.digest, revision=excluded.revision",
                            (identity, notebook, name, source_digest, revision))
            self.db.execute("DELETE FROM chunks WHERE document_id=?", (identity,))
            for index, part in enumerate(chunks(text), 1):
                self.db.execute("INSERT INTO chunks VALUES (?,?,?,?,?)",
                                (f"{identity}r{revision}c{index}", identity, part["text"],
                                 part["line_start"], part["line_end"]))
        return {"id": identity, "name": name, "digest": source_digest,
                "revision": revision, "changed": True}

    def documents(self, notebook):
        self.require_notebook(notebook)
        return [dict(row) for row in self.db.execute(
            "SELECT * FROM documents WHERE notebook=? ORDER BY name", (notebook,))]

    def remove_source(self, notebook, name):
        self.require_notebook(notebook)
        with self.transaction():
            removed = self.db.execute("DELETE FROM documents WHERE notebook=? AND name=?",
                                      (notebook, name)).rowcount
        return {"deleted": bool(removed)}

    def source_chunks(self, notebook):
        self.require_notebook(notebook)
        return [dict(row) for row in self.db.execute(
            "SELECT c.*, d.name, d.digest, d.revision FROM chunks c JOIN documents d "
            "ON c.document_id=d.id WHERE d.notebook=? ORDER BY d.name, c.rowid", (notebook,))]

    def memories(self, notebook):
        self.require_notebook(notebook)
        return [dict(row) for row in self.db.execute(
            "SELECT * FROM memories WHERE notebook=? ORDER BY topic", (notebook,))]

    def remember(self, notebook, topic, status, note=""):
        self.require_notebook(notebook)
        topic = bounded(topic, "知识点")
        if status not in {"new", "learning", "review", "mastered"}:
            raise ValueError("学习状态须为 new / learning / review / mastered。")
        if not isinstance(note, str) or len(note) > 1000:
            raise ValueError("学习备注不能超过 1000 字符。")
        with self.transaction():
            self.db.execute("INSERT INTO memories VALUES (?,?,?,?,?,?,?) "
                            "ON CONFLICT(notebook,topic) DO UPDATE SET status=excluded.status, "
                            "note=excluded.note, revision=memories.revision+1, updated_at=excluded.updated_at",
                            ("m" + uuid.uuid4().hex, notebook, topic, status, note, 1, now()))
        return next(row for row in self.memories(notebook) if row["topic"] == topic)

    def forget(self, notebook, topic):
        self.require_notebook(notebook)
        with self.transaction():
            removed = self.db.execute("DELETE FROM memories WHERE notebook=? AND topic=?",
                                      (notebook, topic)).rowcount
        return {"deleted": bool(removed)}

    def job(self, identity):
        row = self.db.execute("SELECT * FROM jobs WHERE id=?", (identity,)).fetchone()
        if not row:
            raise ValueError("任务不存在。")
        job = dict(row)
        job["payload"] = json.loads(job["payload"])
        job["result"] = json.loads(job["result"]) if job["result"] else None
        return job
