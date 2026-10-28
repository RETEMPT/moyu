import copy
from contextlib import redirect_stderr, redirect_stdout
import io
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

from cloud.ai.moyu_ai.cli import main
from cloud.ai.moyu_ai.provider import MAX_RESPONSE_BYTES, NoRedirect, OllamaProvider, profile
from cloud.ai.moyu_ai.sources import CHUNK_CHARS, chunks, digest, read_source, retrieve
from cloud.ai.moyu_ai.store import APP_ID, Store, encode
from cloud.ai.moyu_ai.tutor import Tutor, validate_output


class FakeProvider:
    def __init__(self, draft, before_return=lambda: None):
        self.draft = draft
        self.before_return = before_return
        self.calls = 0

    def generate(self, messages):
        self.calls += 1
        self.before_return()
        return self.draft, {"model": "fixture", "usage": {"input_tokens": None, "output_tokens": None}}


class TutorTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.store = Store(self.root / "workspace")
        self.addCleanup(self.store.close)
        self.store.notebook("力学")
        self.source = self.root / "lesson.md"
        self.source.write_text("# 力学\n\n合外力决定加速度，F = ma。\n圆周运动的速度方向变化。\n", encoding="utf-8")
        self.store.import_source("力学", self.source)
        self.tutor = Tutor(self.store)
        self.config = profile("http://127.0.0.1:11434", "fixture")

    def prepare(self, operation="qa", memory=False):
        return self.tutor.prepare("力学", operation, "合外力", self.config, memory)

    def draft(self, job):
        citation = {"source_id": job["payload"]["sources"][0]["id"], "quote": "合外力决定加速度"}
        return {"title": "力学复习", "sections": [{"heading": "要点", "body": "F = ma。", "citations": [citation]}],
                "cards": ([{"question": "合外力与什么相关？", "answer": "加速度。", "citations": [citation]}]
                          if job["payload"]["operation"] == "quiz" else []), "warnings": []}

    def reviewed(self, operation="qa"):
        job = self.prepare(operation)
        return self.tutor.run(job["id"], job["preview_digest"], FakeProvider(self.draft(job)))

    def change_source(self):
        self.source.write_text("合外力的资料已经更新。", encoding="utf-8")
        self.store.import_source("力学", self.source)

    def test_import_is_idempotent_and_update_preserves_identity(self):
        first = self.store.documents("力学")[0]
        same = self.store.import_source("力学", self.source)
        self.assertFalse(same["changed"])
        self.change_source()
        changed = self.store.documents("力学")[0]
        self.assertEqual(first["id"], changed["id"])
        self.assertEqual(changed["revision"], 2)
        self.assertNotEqual(first["digest"], changed["digest"])

    def test_backup_preserves_wal_data_and_is_independent(self):
        self.store.db.execute("PRAGMA journal_mode=WAL")
        self.store.remember("力学", "合外力", "review", "需核对")
        job = self.reviewed()
        target = self.root / "backup"
        result = self.store.backup(target)
        self.assertTrue(result["verified"])
        self.assertEqual(result["counts"]["jobs"], 1)
        backup = Store(target)
        try:
            self.assertEqual(backup.job(job["id"]), self.store.job(job["id"]))
            self.assertEqual(backup.source_chunks("力学"), self.store.source_chunks("力学"))
            self.store.forget("力学", "合外力")
            self.assertEqual(backup.memories("力学")[0]["note"], "需核对")
        finally:
            backup.close()

    def test_backup_never_overwrites_existing_directory(self):
        for target in [self.store.workspace, self.root]:
            with self.assertRaises(FileExistsError):
                self.store.backup(target)
        self.assertEqual(len(self.store.documents("力学")), 1)

    def test_backup_rejects_running_snapshot_and_cleans_partial_output(self):
        job = self.prepare()
        with self.store.transaction():
            self.store.db.execute("UPDATE jobs SET state='running' WHERE id=?", (job["id"],))
        target = self.root / "backup"
        with self.assertRaisesRegex(ValueError, "运行中"):
            self.store.backup(target)
        self.assertFalse(target.exists())
        self.assertEqual(self.store.job(job["id"])["state"], "running")

    def test_backup_rejects_active_transaction_without_creating_directory(self):
        target = self.root / "backup"
        with self.store.transaction():
            with self.assertRaisesRegex(ValueError, "事务"):
                self.store.backup(target)
        self.assertFalse(target.exists())

    def test_backup_timeout_cleans_partial_output(self):
        target = self.root / "backup"
        with patch("cloud.ai.moyu_ai.store.time.monotonic", side_effect=[0, 11]):
            with self.assertRaisesRegex(ValueError, "10 秒"):
                self.store.backup(target)
        self.assertFalse(target.exists())

    def test_backup_cli_returns_verified_counts(self):
        output = io.StringIO()
        with redirect_stdout(output):
            code = main(["--workspace", str(self.store.workspace), "workspace", "backup",
                         str(self.root / "backup")])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(output.getvalue())["counts"]["documents"], 1)

    def test_portable_export_is_minimal_accepted_fresh_and_exclusive(self):
        from cloud.ai.moyu_ai.exchange import decode
        job = self.reviewed("quiz")
        target = self.root / "result.json"
        with self.assertRaises(ValueError):
            self.tutor.export(job["id"], target, True)
        self.assertFalse(target.exists())
        self.tutor.accept(job["id"])
        self.tutor.export(job["id"], target, True)
        result = decode(target.read_bytes())
        self.assertEqual(result["cards"], job["result"]["draft"]["cards"])
        self.assertEqual(set(result), {"format", "version", "job_id", "operation", "title",
                                       "sources", "sections", "cards", "warnings"})
        self.assertEqual(set(result["sources"][0]), {"id", "name", "text", "revision", "digest", "line_start", "line_end"})
        with self.assertRaises(FileExistsError):
            self.tutor.export(job["id"], target, True)
        with self.assertRaises(ValueError):
            self.tutor.export(job["id"], self.root / "invalid.md", True)
        self.change_source()
        with self.assertRaises(ValueError):
            self.tutor.export(job["id"], self.root / "stale.json", True)

    def test_notebooks_isolate_search_and_memory(self):
        self.store.notebook("化学")
        other = self.root / "chem.md"
        other.write_text("化学平衡随温度变化。", encoding="utf-8")
        self.store.import_source("化学", other)
        self.store.remember("化学", "化学平衡", "review")
        self.assertEqual(retrieve(self.store.source_chunks("力学"), "化学平衡"), [])
        self.assertEqual(self.store.memories("力学"), [])

    def test_memory_edit_forget_and_consent(self):
        self.store.remember("力学", "合外力", "review", "上次答错")
        self.store.remember("力学", "合外力", "mastered", "已核对")
        self.assertEqual(self.store.memories("力学")[0]["revision"], 2)
        excluded = self.prepare()
        included = self.prepare(memory=True)
        self.assertEqual(excluded["payload"]["memories"], [])
        self.assertNotIn("已核对", encode(excluded["payload"]["messages"]))
        self.assertIn("已核对", encode(included["payload"]["messages"]))
        self.assertTrue(self.store.forget("力学", "合外力")["deleted"])
        self.assertEqual(self.store.memories("力学"), [])

    def test_prepare_never_calls_network_and_snapshot_digest_matches(self):
        with patch("urllib.request.OpenerDirector.open", side_effect=AssertionError("network")):
            job = self.prepare()
        self.assertEqual(job["state"], "prepared")
        self.assertEqual(digest(encode(job["payload"])), job["preview_digest"])
        self.assertNotIn(str(self.source), encode(job["payload"]))
        self.assertNotIn("lesson.md", encode(job["payload"]["messages"]))

    def test_unmatched_qa_does_not_create_job(self):
        with self.assertRaisesRegex(ValueError, "没有匹配"):
            self.tutor.prepare("力学", "qa", "DNA replication", self.config)
        self.assertEqual(self.store.db.execute("SELECT count(*) FROM jobs").fetchone()[0], 0)

    def test_each_operation_has_a_valid_review_flow(self):
        for operation in ["summary", "qa", "quiz", "report", "plan"]:
            with self.subTest(operation=operation):
                result = self.reviewed(operation)
                self.assertEqual(result["state"], "review")
                self.assertEqual(len(result["result"]["draft"]["cards"]), int(operation == "quiz"))
                self.tutor.accept(result["id"])
                destination = self.root / f"{operation}.json"
                with redirect_stdout(io.StringIO()):
                    self.assertEqual(main(["--workspace", str(self.store.workspace), "job", "export",
                                           result["id"], str(destination), "--portable"]), 0)
                from cloud.ai.moyu_ai.exchange import decode
                self.assertEqual(decode(destination.read_bytes())["operation"], operation)

    def test_wrong_approval_cannot_send(self):
        job = self.prepare()
        fake = FakeProvider(self.draft(job))
        with self.assertRaisesRegex(ValueError, "preview_digest"):
            self.tutor.run(job["id"], "yes", fake)
        self.assertEqual(fake.calls, 0)
        self.assertEqual(self.store.job(job["id"])["state"], "prepared")

    def test_source_changes_block_send_accept_and_export(self):
        pending = self.prepare()
        review = self.reviewed()
        accepted = self.reviewed()
        self.tutor.accept(accepted["id"])
        self.change_source()
        for action in [lambda: self.tutor.run(pending["id"], pending["preview_digest"], FakeProvider({})),
                       lambda: self.tutor.accept(review["id"]),
                       lambda: self.tutor.export(accepted["id"], self.root / "out.md")]:
            with self.subTest(action=action), self.assertRaisesRegex(ValueError, "资料已变化"):
                action()

    def test_memory_changes_and_deletion_invalidate_opted_in_jobs(self):
        self.store.remember("力学", "合外力", "review")
        job = self.prepare(memory=True)
        self.store.forget("力学", "合外力")
        with self.assertRaisesRegex(ValueError, "记忆已变化"):
            self.tutor.run(job["id"], job["preview_digest"], FakeProvider(self.draft(job)))

    def test_memory_changes_do_not_invalidate_jobs_without_memory(self):
        job = self.prepare()
        self.store.remember("力学", "合外力", "review")
        self.assertEqual(self.tutor.run(job["id"], job["preview_digest"], FakeProvider(self.draft(job)))["state"], "review")

    def test_fabricated_outside_or_missing_citations_are_rejected(self):
        job = self.prepare()
        for citations in [[], [{"source_id": "elsewhere", "quote": "合外力决定加速度"}],
                          [{"source_id": job["payload"]["sources"][0]["id"], "quote": "不存在的原文句子"}]]:
            with self.subTest(citations=citations):
                draft = self.draft(job)
                draft["sections"][0]["citations"] = citations
                with self.assertRaises(ValueError):
                    validate_output(draft, job["payload"])

    def test_output_size_depth_tool_fields_and_card_contract(self):
        job = self.prepare()
        for mutate in [lambda d: d.update(tools=["shell"]),
                       lambda d: d["sections"][0].update(body="a" * 4001),
                       lambda d: d.update(cards=[{}]), lambda d: d.update(warnings="warning"),
                       lambda d: d["sections"][0]["citations"][0].update(source_id=[]),
                       lambda d: d.update(sections={})]:
            with self.subTest(mutate=mutate):
                draft = self.draft(job)
                mutate(draft)
                with self.assertRaises(ValueError):
                    validate_output(draft, job["payload"])

    def test_failed_generation_does_not_retry_or_save_draft(self):
        job = self.prepare()
        fake = FakeProvider({"wrong": "schema"})
        with self.assertRaises(ValueError):
            self.tutor.run(job["id"], job["preview_digest"], fake)
        with self.assertRaisesRegex(ValueError, "prepared"):
            self.tutor.run(job["id"], job["preview_digest"], fake)
        self.assertEqual(fake.calls, 1)
        self.assertIsNone(self.store.job(job["id"])["result"])

    def test_abandoned_running_job_rejects_late_output(self):
        job = self.prepare()
        fake = FakeProvider(self.draft(job), lambda: self.tutor.abandon(job["id"]))
        with self.assertRaisesRegex(ValueError, "迟到结果"):
            self.tutor.run(job["id"], job["preview_digest"], fake)
        self.assertEqual(self.store.job(job["id"])["state"], "abandoned")
        self.assertIsNone(self.store.job(job["id"])["result"])

    def test_sources_changing_during_generation_reject_late_output(self):
        job = self.prepare()
        with self.assertRaisesRegex(ValueError, "资料已变化"):
            self.tutor.run(job["id"], job["preview_digest"], FakeProvider(self.draft(job), self.change_source))
        self.assertEqual(self.store.job(job["id"])["state"], "failed")

    def test_two_senders_cannot_claim_same_job(self):
        job = self.prepare()
        other = Store(self.store.workspace)
        self.addCleanup(other.close)

        def duplicate():
            with self.assertRaisesRegex(ValueError, "prepared"):
                Tutor(other).run(job["id"], job["preview_digest"], FakeProvider({}))

        self.tutor.run(job["id"], job["preview_digest"], FakeProvider(self.draft(job), duplicate))

    def test_model_failure_details_are_not_persisted(self):
        job = self.prepare()

        def fail():
            raise RuntimeError("sensitive-provider-response")

        with self.assertRaises(RuntimeError):
            self.tutor.run(job["id"], job["preview_digest"], FakeProvider({}, fail))
        self.assertEqual(self.store.job(job["id"])["error"], "RuntimeError")

    def test_user_revision_acceptance_and_exclusive_export(self):
        job = self.reviewed("quiz")
        draft = copy.deepcopy(job["result"]["draft"])
        draft["sections"][0]["body"] = "用户校对 <script>alert(1)</script> [链接](https://example.org)"
        revised = self.tutor.revise(job["id"], draft)
        self.assertTrue(revised["result"]["edited_by_user"])
        with self.assertRaises(ValueError):
            self.tutor.export(job["id"], self.root / "out.md")
        self.tutor.accept(job["id"])
        self.tutor.accept(job["id"])
        path = self.root / "out.md"
        self.tutor.export(job["id"], path)
        exported = path.read_text(encoding="utf-8")
        self.assertIn("行 1–4", exported)
        self.assertIn("\\<script\\>", exported)
        self.assertIn("\\[链接\\]", exported)
        self.assertIn("题卡 1", exported)
        with self.assertRaises(FileExistsError):
            self.tutor.export(job["id"], path)
        with self.assertRaises(ValueError):
            self.tutor.revise(job["id"], draft)
        self.assertEqual(self.store.memories("力学"), [])

    def test_cli_offline_flow_and_batch_partial_failure(self):
        output, errors = io.StringIO(), io.StringIO()
        workspace = str(self.root / "cli")
        with redirect_stdout(output), redirect_stderr(errors):
            self.assertEqual(main(["--workspace", workspace, "notebook", "create", "课程"]), 0)
            self.assertEqual(main(["--workspace", workspace, "source", "add", "课程", str(self.source), str(self.root / "missing.txt")]), 1)
            self.assertEqual(main(["--workspace", workspace, "source", "search", "课程", "合外力"]), 0)
        self.assertIn('"partial_failure": true', output.getvalue())
        self.assertIn("合外力决定加速度", output.getvalue())

    def test_transaction_rollback_retains_existing_state(self):
        before = self.store.documents("力学")
        with self.assertRaises(RuntimeError):
            with self.store.transaction():
                self.store.db.execute("DELETE FROM documents")
                raise RuntimeError("injected storage failure")
        self.assertEqual(before, self.store.documents("力学"))
        self.assertTrue(self.store.source_chunks("力学"))

    def test_deletion_removes_live_source_and_job_snapshots(self):
        job = self.prepare()
        self.assertTrue(self.store.remove_source("力学", "lesson.md")["deleted"])
        self.assertTrue(self.source.exists())
        self.assertEqual(self.store.source_chunks("力学"), [])
        with self.assertRaisesRegex(ValueError, "资料已变化"):
            self.tutor.run(job["id"], job["preview_digest"], FakeProvider(self.draft(job)))
        self.assertTrue(self.tutor.delete(job["id"])["deleted"])
        with self.assertRaisesRegex(ValueError, "不存在"):
            self.store.job(job["id"])


class SourceTest(unittest.TestCase):
    def test_chunk_coordinates_preserve_long_lines_and_unicode(self):
        text = "首行\n" + "加" * 2500 + "\n末行\n"
        parts = list(chunks(text))
        self.assertEqual("".join(part["text"] for part in parts), text)
        self.assertTrue(all(len(part["text"]) <= CHUNK_CHARS for part in parts))
        offset = 0
        for part in parts:
            self.assertEqual(part["line_start"], text[:offset].count("\n") + 1)
            offset += len(part["text"])

    def test_unsupported_binary_empty_encoding_and_large_sources(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "source.txt"
            for content in [b"", b"binary\0text", b"\xff", b"a" * (1024 * 1024 + 1)]:
                path.write_bytes(content)
                with self.assertRaises((ValueError, UnicodeError)):
                    read_source(path)
            path = Path(folder) / "source.pdf"
            path.write_bytes(b"PDF")
            with self.assertRaises(ValueError):
                read_source(path)

    def test_utf8_bom_newlines_and_mixed_language_retrieval(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "source.md"
            path.write_bytes(b"\xef\xbb\xbf" + "合外力 F = ma\r\n".encode("utf-8"))
            self.assertEqual(read_source(path), "合外力 F = ma\n")
        rows = [{"id": "1", "text": "合外力 F = ma"}, {"id": "2", "text": "化学平衡"}]
        self.assertEqual(retrieve(rows, "合外力")[0]["id"], "1")
        self.assertEqual(retrieve(rows, "Ｆ")[0]["id"], "1")
        self.assertEqual(retrieve(rows, "unmatched"), [])

    def test_unrelated_or_future_database_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "learning.sqlite3"
            connection = sqlite3.connect(path)
            connection.execute("CREATE TABLE private_data(value TEXT)")
            connection.commit()
            connection.close()
            before = path.read_bytes()
            with self.assertRaises(ValueError):
                Store(folder)
            self.assertEqual(before, path.read_bytes())
            connection = sqlite3.connect(path)
            connection.execute(f"PRAGMA application_id={APP_ID}")
            connection.execute("PRAGMA user_version=999")
            connection.close()
            with self.assertRaises(ValueError):
                Store(folder)


class ProviderTest(unittest.TestCase):
    def test_endpoint_policy_and_no_redirects(self):
        for endpoint in ["http://remote.example", "file:///etc/passwd", "https://user:key@example.org",
                         "https://example.org/api", "https://example.org/?key=secret",
                         "https://example.org/#secret", "https://example.org:bad", "https://example.org\\evil"]:
            with self.subTest(endpoint=endpoint), self.assertRaises(ValueError):
                profile(endpoint, "model")
        self.assertEqual(profile("http://[::1]:11434/", "model")["endpoint"], "http://[::1]:11434")
        self.assertIsNone(NoRedirect().redirect_request(None, None, 302, "", {}, "https://elsewhere.org"))

    def invoke(self, response, **kwargs):
        raw = response if isinstance(response, bytes) else json.dumps(response).encode("utf-8")
        stream = io.BytesIO(raw)
        with patch("urllib.request.OpenerDirector.open", return_value=stream) as opened:
            result = OllamaProvider(profile("http://127.0.0.1:11434", "fixture")).generate([{ "role": "user", "content": "text"}])
            request = opened.call_args.args[0]
        return result, request

    def test_ollama_wire_request_and_unknown_usage(self):
        (draft, metadata), request = self.invoke({"done": True, "message": {"content": '{"test":true}'}})
        self.assertEqual(draft, {"test": True})
        self.assertIsNone(metadata["usage"]["input_tokens"])
        body = json.loads(request.data)
        self.assertFalse(body["stream"])
        self.assertEqual(body["format"], "json")
        self.assertNotIn("tools", body)
        self.assertEqual(request.full_url, "http://127.0.0.1:11434/api/chat")

    def test_response_size_invalid_json_incomplete_and_tool_calls(self):
        for response in [b"a" * (MAX_RESPONSE_BYTES + 1), b"not json", {},
                         {"done": False, "message": {"content": "{}"}},
                         {"done": True, "message": {"content": "{}", "tool_calls": ["tool"]}},
                         {"done": True, "message": {"content": "[]" * 20000}}]:
            with self.subTest(response=str(response)[:50]), self.assertRaises(ValueError):
                self.invoke(response)

    def test_http_error_does_not_leak_body_or_retry(self):
        error = urllib.error.HTTPError("https://example.org", 429, "SECRET", {}, io.BytesIO(b"PRIVATE"))
        with patch("urllib.request.OpenerDirector.open", side_effect=error) as opened:
            with self.assertRaisesRegex(ValueError, "HTTP 429") as caught:
                OllamaProvider(profile("https://example.org", "fixture")).generate([])
        self.assertEqual(opened.call_count, 1)
        self.assertNotIn("PRIVATE", str(caught.exception))
        self.assertNotIn("SECRET", str(caught.exception))

    def test_credentials_not_sent_over_loopback_http(self):
        with patch.dict(os.environ, {"MOYU_AI_API_KEY": "secret"}), patch("urllib.request.OpenerDirector.open") as opened:
            with self.assertRaisesRegex(ValueError, "HTTPS"):
                OllamaProvider(profile("http://localhost:11434", "fixture")).generate([])
        opened.assert_not_called()


if __name__ == "__main__":
    unittest.main()
