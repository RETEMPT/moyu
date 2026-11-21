import copy
from contextlib import redirect_stderr, redirect_stdout
from email.message import Message
import io
import json
import os
from pathlib import Path
import sqlite3
import tempfile
import unittest
from unittest.mock import Mock, patch
import urllib.error

from cloud.ai.moyu_ai.cli import main
from cloud.ai.moyu_ai.provider import CloudChatProvider, MAX_RESPONSE_BYTES, NoRedirect, PRESETS, profile
from cloud.ai.moyu_ai.simulator_gateway import chat, generate, handler
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
        self.config = profile("deepseek", "fixture")

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

    def test_explicit_sources_limit_retrieval_and_summary_fallback(self):
        other = self.root / "other.txt"
        other.write_text("合外力属于另一份资料。", encoding="utf-8")
        self.store.import_source("力学", other, "另一份")
        for operation, question in (("qa", "合外力"), ("summary", "completely_unmatched")):
            job = self.tutor.prepare("力学", operation, question, self.config, source_names=["另一份"])
            self.assertEqual({item["name"] for item in job["payload"]["sources"]}, {"另一份"})
            self.assertNotIn("F = ma", job["payload"]["messages"][1]["content"])
        with self.assertRaisesRegex(ValueError, "不在当前笔记本"):
            self.tutor.prepare("力学", "qa", "合外力", self.config, source_names=["其他课程"])

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

    def test_agent_authorization_is_explicit_single_use_and_not_copied(self):
        job = self.prepare()
        identity = job["id"]
        provider = FakeProvider(self.draft(job))
        with self.assertRaisesRegex(ValueError, "授权"):
            self.tutor.run(identity, None, provider, authorized_only=True)
        with self.assertRaisesRegex(ValueError, "preview_digest"):
            self.tutor.authorize(identity, "wrong")
        self.assertEqual(self.tutor.authorize(identity, job["preview_digest"])["state"], "approved")
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(ValueError, "DEEPSEEK_API_KEY"):
                self.tutor.run(identity, None, authorized_only=True)
        self.assertEqual(self.store.job(identity)["state"], "approved")
        target = self.root / "approval-backup"
        self.store.backup(target)
        backup = Store(target)
        try:
            self.assertEqual(backup.job(identity)["state"], "prepared")
        finally:
            backup.close()
        self.assertEqual(self.tutor.run(identity, None, provider, authorized_only=True)["state"], "review")
        with self.assertRaisesRegex(ValueError, "授权"):
            self.tutor.run(identity, None, provider, authorized_only=True)
        self.assertEqual(provider.calls, 1)

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
        with self.assertRaisesRegex(ValueError, "仅待发送任务可执行"):
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
            with self.assertRaisesRegex(ValueError, "仅待发送任务可执行"):
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
                         "https://127.0.0.1", "https://example.org/v1/chat/completions", "https://example.org/?key=secret",
                         "https://example.org/#secret", "https://example.org:bad", "https://example.org\\evil"]:
            with self.subTest(endpoint=endpoint), self.assertRaises(ValueError):
                profile("compatible", "model", base_url=endpoint)
        self.assertEqual(profile("compatible", "model", base_url="https://example.org/v1/")["base_url"], "https://example.org/v1")
        with self.assertRaises(ValueError):
            profile("openai", "fixture", base_url="https://example.org")
        region = "https://llm-123.ap-northeast-1.maas.aliyuncs.com/compatible-mode/v1"
        self.assertEqual(profile("qwen-intl", "fixture", base_url=region)["base_url"], region)
        with self.assertRaises(ValueError):
            profile("qwen-cn", "fixture", base_url=region)
        self.assertIsNone(NoRedirect().redirect_request(None, None, 302, "", {}, "https://elsewhere.org"))

    def invoke(self, response, provider="deepseek", **kwargs):
        raw = response if isinstance(response, bytes) else json.dumps(response).encode("utf-8")
        stream = io.BytesIO(raw)
        with patch.dict(os.environ, {PRESETS[provider][1]: "provider-key"}, clear=True), \
                patch("urllib.request.build_opener") as build_opener:
            opened = build_opener.return_value.open
            opened.return_value = stream
            result = CloudChatProvider(profile(provider, "fixture", **kwargs)).generate([{"role": "user", "content": "text"}])
            request = opened.call_args.args[0]
            proxy, redirects = build_opener.call_args.args
            self.assertEqual(proxy.proxies, {})
            self.assertIsInstance(redirects, NoRedirect)
        return result, request

    def test_provider_request_fields_and_usage(self):
        response = {"choices": [{"finish_reason": "stop", "message": {"content": '{"test":true}'}}],
                    "usage": {"completion_tokens": 9}}
        for provider in PRESETS:
            with self.subTest(provider=provider):
                kwargs = {"base_url": "https://example.org/openai/v1"} if provider == "compatible" else {}
                (draft, metadata), request = self.invoke(response, provider, **kwargs)
                body = json.loads(request.data)
                self.assertEqual(draft, {"test": True})
                self.assertEqual(metadata["usage"], {"input_tokens": None, "output_tokens": 9})
                self.assertFalse(body["stream"])
                self.assertEqual(body["response_format"], {"type": "json_object"})
                self.assertNotIn("tools", body)
                self.assertEqual(body["max_completion_tokens" if provider == "openai" else "max_tokens"], 1600)
                self.assertEqual(body.get("thinking"), {"type": "disabled"} if provider == "deepseek" else None)
                self.assertEqual(body.get("enable_thinking"), False if provider.startswith("qwen") else None)
                self.assertEqual(request.full_url, (kwargs.get("base_url") or PRESETS[provider][0]) + "/chat/completions")
                self.assertEqual(request.get_header("Authorization"), "Bearer provider-key")

    def test_response_size_invalid_json_incomplete_and_tool_calls(self):
        for response in [b"a" * (MAX_RESPONSE_BYTES + 1), b"not json", {},
                         {"choices": [{"finish_reason": "length", "message": {"content": "{}"}}]},
                         {"choices": [{"finish_reason": "stop", "message": {"content": "{}", "tool_calls": ["tool"]}}]},
                         {"choices": [{"finish_reason": "stop", "message": {"content": " " * 3}}]},
                         {"choices": [{"finish_reason": "stop", "message": {"content": "[]" * 20000}}]}]:
            with self.subTest(response=str(response)[:50]), self.assertRaises(ValueError):
                self.invoke(response)

    def test_http_error_does_not_leak_body_or_retry(self):
        error = urllib.error.HTTPError("https://example.org", 429, "SECRET", {}, io.BytesIO(b"PRIVATE"))
        with patch.dict(os.environ, {"OPENAI_API_KEY": "secret"}, clear=True), \
                patch("urllib.request.build_opener") as build_opener:
            opened = build_opener.return_value.open
            opened.side_effect = error
            with self.assertRaisesRegex(ValueError, "HTTP 429") as caught:
                CloudChatProvider(profile("openai", "fixture")).generate([])
        self.assertEqual(opened.call_count, 1)
        self.assertNotIn("PRIVATE", str(caught.exception))
        self.assertNotIn("SECRET", str(caught.exception))

    def test_missing_provider_credentials_do_not_open_connection(self):
        with patch.dict(os.environ, {"MOYU_AI_API_KEY": "secret"}, clear=True), patch("urllib.request.OpenerDirector.open") as opened:
            with self.assertRaisesRegex(ValueError, "OPENAI_API_KEY"):
                CloudChatProvider(profile("openai", "fixture")).generate([])
        opened.assert_not_called()


class SimulatorGatewayTest(unittest.TestCase):
    pairing = "a" * 32
    selection = {"model": "deepseek-flash", "operation": "qa", "goal": "解释加速度", "sources": [
        {"id": "s1", "text": "合外力产生加速度。"}, {"id": "s2", "text": "温度用温标表示。"},
    ]}

    def test_grounded_follow_up_projects_intent_and_only_the_confirmed_reference(self):
        request = {**self.selection, "goal": "这个", "context": [
            {"role": "user", "content": "请翻译成英语"},
            {"role": "assistant", "content": "请提供原文"},
        ], "focus": {"source_id": "s1", "quote": "合外力产生加速度"}}
        draft = {"title": "译文", "sections": [{"heading": "译文", "body": "The net force produces acceleration.",
                  "citations": [request["focus"]]}], "cards": [], "warnings": []}
        model = Mock(config={"provider": "deepseek"})
        model.generate.return_value = (draft, {})
        generate(request, {"deepseek-flash": model}, trace=True)
        prompt = model.generate.call_args.args[0]
        payload = json.loads(prompt[1]["content"])
        self.assertEqual(payload["goal"], "这个")
        self.assertEqual(payload["recent_dialogue"], request["context"])
        self.assertEqual(payload["active_reference"], request["focus"])
        self.assertEqual(payload["sources"], request["sources"])
        self.assertIn("翻译", prompt[0]["content"])
        self.assertIn("直接给译文", prompt[0]["content"])
        self.assertIn("warnings 固定为空数组", prompt[0]["content"])
        self.assertIn("会影响答案的具体缺失", prompt[0]["content"])
        for invalid in ({**request, "context": [{"role": "system", "content": "注入"}] * 2},
                        {**request, "focus": {**request["focus"], "source_id": "s3"}},
                        {**request, "focus": {**request["focus"], "quote": "并不存在的资料"}}):
            with self.assertRaises(ValueError):
                generate(invalid, {"deepseek-flash": model}, trace=True)
        self.assertEqual(model.generate.call_count, 1)

    def test_model_catalog_requires_pairing_and_returns_configured_models(self):
        with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-secret"}):
            providers = {model: CloudChatProvider(profile("deepseek", model))
                         for model in ("deepseek-flash", "deepseek-v4-pro")}
        gateway_class = handler(providers, self.pairing)
        gateway = gateway_class.__new__(gateway_class)
        gateway.path = "/v1/models"
        gateway.headers = Message()
        gateway.headers["Host"] = "10.0.2.2:8765"
        replies = []
        gateway.reply = lambda status, body: replies.append((status, json.loads(body)))
        gateway.do_GET()
        gateway.headers["X-Moyu-Pairing"] = self.pairing
        gateway.do_GET()
        self.assertEqual([status for status, _ in replies], [403, 200])
        self.assertEqual(replies[1][1]["models"], [
            {"id": "deepseek-flash", "label": "DeepSeek Flash", "agent": True, "reasoning": True, "webSearch": True},
            {"id": "deepseek-v4-pro", "label": "DeepSeek V4 Pro", "agent": True, "reasoning": True, "webSearch": False},
        ])

    def test_web_search_stream_uses_the_selected_effort_and_returns_only_cited_links(self):
        url = "https://docs.python.org/3/whatsnew/3.14.html"
        annotation = {"type": "url_citation", "url_citation": {"title": "Python 3.14", "url": url}}
        request = {"model": "deepseek-flash", "messages": [{"role": "user", "content": "查找 Python 文档"}],
                   "effort": "high", "web": True}
        chunks = [
            {"delta": {"reasoning_content": "先查官网。"}},
            {"delta": {}, "server_tool_event": {"type": "call_completed", "call": {"action": {"type": "search"},
                                                                              "status": "completed"}}},
            {"delta": {"content": "已查到 Python 3.14 文档。"}},
            {"delta": {"annotations": [annotation, annotation, {"type": "url_citation", "url_citation": {
                "url": "javascript:alert(1)"}}]}, "finish_reason": "stop"},
        ]
        wire = "".join("data: " + encode({"choices": [chunk]}) + "\n\n" for chunk in chunks) + "data: [DONE]\n\n"
        with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-secret"}), patch("urllib.request.build_opener") as opener:
            model = CloudChatProvider(profile("deepseek", "deepseek-flash"))
            upstream = opener.return_value.open
            upstream.return_value = io.BytesIO(wire.encode())
            progress = Mock()
            result = json.loads(chat(request, {"deepseek-flash": model}, progress=progress))
            payload = json.loads(upstream.call_args.args[0].data)
            self.assertEqual(payload["tools"], [{"type": "deepseek_web_search"}])
            self.assertEqual(payload["response_format"], {"type": "text"})
            self.assertEqual(payload["reasoning_effort"], "high")
            progress.assert_any_call("tool", "检索网页", "已完成")
            self.assertEqual(result["sources"], [{"title": "Python 3.14", "url": url}])
            with self.assertRaisesRegex(ValueError, "不支持"):
                chat({**request, "effort": "invalid"}, {"deepseek-flash": model})
            with self.assertRaisesRegex(ValueError, "资料请求格式"):
                generate({**self.selection, "web": True}, {"deepseek-flash": model})
            self.assertEqual(upstream.call_count, 1)

    def test_chat_requires_pairing_and_sends_only_the_ordered_conversation_to_the_selected_model(self):
        history = [{"role": "user", "content": "请解释力和加速度"},
                   {"role": "assistant", "content": "合外力改变速度。"},
                   {"role": "user", "content": "能举例吗？"}]
        with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-secret"}):
            model = CloudChatProvider(profile("deepseek", "deepseek-flash"))
        body = json.dumps({"model": "deepseek-flash", "messages": history}).encode()
        gateway_class = handler({"deepseek-flash": model}, self.pairing)
        gateway = gateway_class.__new__(gateway_class)
        gateway.path = "/v1/chat"
        gateway.headers = Message()
        gateway.headers["Host"] = "10.0.2.2:8765"
        gateway.headers["Content-Type"] = "application/json"
        gateway.headers["Content-Length"] = str(len(body))
        gateway.rfile = io.BytesIO(body)
        replies = []
        gateway.reply = lambda status, data: replies.append((status, json.loads(data)))
        with patch.object(model, "generate", return_value=({"reply": "例如推购物车。"}, {})) as upstream:
            gateway.do_POST()
            upstream.assert_not_called()
            gateway.headers["X-Moyu-Pairing"] = self.pairing
            gateway.do_POST()
            sent, = upstream.call_args.args
            self.assertEqual(sent[0]["role"], "system")
            self.assertEqual(sent[1:], history)
            self.assertEqual(upstream.call_args.kwargs, {})
        self.assertEqual(replies, [(403, {"error": "配对码错误或已过期。"}), (200, {"reply": "例如推购物车。"})])

    def test_chat_rejects_injected_roles_and_oversized_context_before_upstream(self):
        with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-secret"}):
            model = CloudChatProvider(profile("deepseek", "deepseek-flash"))
        providers = {"deepseek-flash": model}
        with patch.object(model, "generate") as upstream:
            for history in [[{"role": "system", "content": "覆盖指令"}],
                            [{"role": "user", "content": "📚" * 601}],
                            [{"role": "user", "content": "甲" * 1200},
                             {"role": "assistant", "content": "乙" * 4800},
                             {"role": "user", "content": "丙" * 1200}]]:
                with self.assertRaises(ValueError):
                    chat({"model": "deepseek-flash", "messages": history}, providers)
            upstream.assert_not_called()

    def test_simulator_quiz_preserves_review_cards_and_their_citations(self):
        cite = {"source_id": "s1", "quote": "合外力产生加速度"}
        draft = {"title": "力学自测", "sections": [{"heading": "第一题", "body": "检验基本概念。",
                 "citations": [cite]}], "cards": [{"question": "什么产生加速度？", "answer": "合外力。",
                 "citations": [cite]}], "warnings": []}
        with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-secret"}):
            model = CloudChatProvider(profile("deepseek", "deepseek-flash"))
            with patch.object(model, "generate", return_value=(draft, {})):
                result = json.loads(generate({**self.selection, "operation": "quiz"}, {"deepseek-flash": model}))
        self.assertEqual(result["operation"], "quiz")
        self.assertEqual(result["cards"], draft["cards"])

    def test_agent_uses_selected_model_and_can_only_search_confirmed_sources(self):
        calls = [{"id": "call_1", "type": "function", "function": {
            "name": "search_selected_sources", "arguments": json.dumps({"query": "加速度"}),
        }}]
        reads = [{"id": "call_2", "type": "function", "function": {
            "name": "read_selected_source", "arguments": json.dumps({"source_id": "s1"}),
        }}]
        draft = {"title": "加速度", "sections": [{"heading": "回答", "body": "合外力会改变速度。",
                  "citations": [{"source_id": "s1", "quote": "合外力产生加速度"}]}], "cards": [], "warnings": []}
        with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-secret"}), \
                patch("urllib.request.build_opener") as opener:
            model = CloudChatProvider(profile("deepseek", "deepseek-flash"))
            upstream = opener.return_value.open
            upstream.side_effect = [io.BytesIO(encode({"choices": [{"finish_reason": reason, "message": message}]}).encode())
                                    for reason, message in [
                                        ("tool_calls", {"content": None, "tool_calls": calls}),
                                        ("tool_calls", {"content": None, "tool_calls": reads}),
                                        ("stop", {"content": encode(draft)}),
                                    ]]
            result = json.loads(generate(self.selection, {"deepseek-flash": model}, trace=True))
            first, second, third = [json.loads(call.args[0].data) for call in upstream.call_args_list]
            self.assertEqual(first["model"], "deepseek-flash")
            self.assertEqual(first["tool_choice"], "auto")
            self.assertEqual(second["tool_choice"], "auto")
            self.assertEqual(third["tool_choice"], "none")
            self.assertEqual(json.loads(second["messages"][-1]["content"]),
                             {"matches": [{"source_id": "s1", "text": "合外力产生加速度。"}]})
            self.assertEqual(third["messages"][-1]["tool_call_id"], "call_2")
            self.assertEqual(json.loads(third["messages"][-1]["content"]),
                             {"source_id": "s1", "text": "合外力产生加速度。"})
            self.assertEqual(result["result"]["title"], draft["title"])
            self.assertEqual(result["tools"], ["search_selected_sources", "read_selected_source"])

            with self.assertRaisesRegex(ValueError, "不可用"):
                generate({**self.selection, "model": "other-model"}, {"deepseek-flash": model})
            self.assertEqual(upstream.call_count, 3)

            calls[0]["function"]["name"] = "read_file"
            upstream.side_effect = [io.BytesIO(encode({"choices": [
                {"finish_reason": "tool_calls", "message": {"tool_calls": calls}},
            ]}).encode())]
            with self.assertRaisesRegex(ValueError, "未提供的工具"):
                generate(self.selection, {"deepseek-flash": model})
            self.assertEqual(upstream.call_count, 4)

    def test_agent_stream_emits_thinking_before_tools_and_replays_it_to_the_provider(self):
        def event_stream(deltas, finish):
            events = [{"choices": [{"index": 0, "delta": delta, "finish_reason": None}]} for delta in deltas]
            events.append({"choices": [{"index": 0, "delta": {}, "finish_reason": finish}]})
            events.append({"choices": [], "usage": {"completion_tokens": 12}})
            return io.BytesIO(("\n\n".join("data: " + encode(event) for event in events) + "\n\ndata: [DONE]\n\n").encode())

        draft = {"title": "加速度", "sections": [{"heading": "回答", "body": "合外力会改变速度。",
                  "citations": [{"source_id": "s1", "quote": "合外力产生加速度"}]}], "cards": [], "warnings": []}
        with patch.dict(os.environ, {"DEEPSEEK_API_KEY": "test-secret"}), patch("urllib.request.build_opener") as opener:
            model = CloudChatProvider(profile("deepseek", "deepseek-flash"))
            upstream = opener.return_value.open
            upstream.side_effect = [event_stream([
                {"role": "assistant", "reasoning_content": "先检索"},
                {"reasoning_content": "证据。"},
                {"tool_calls": [{"index": 0, "id": "lookup", "type": "function", "function": {
                    "name": "search_selected_sources", "arguments": '{"que',
                }}]},
                {"tool_calls": [{"index": 0, "function": {"arguments": 'ry":"加速度"}'}}]},
            ], "tool_calls"), event_stream([
                {"reasoning_content": "已有经过核验的出处。"}, {"content": encode(draft)},
            ], "stop")]
            cls = handler({"deepseek-flash": model}, self.pairing)
            gateway = cls.__new__(cls)
            gateway.path = "/v1/agent/run"
            gateway.headers = {"X-Moyu-Trace": "live-v1"}
            gateway.send_response = Mock()
            gateway.send_header = Mock()
            gateway.end_headers = Mock()
            gateway.wfile = io.BytesIO()
            gateway.run_stream(self.selection)
            outgoing = [json.loads(line) for line in gateway.wfile.getvalue().splitlines()]
            self.assertEqual([event["step"]["kind"] for event in outgoing[:-1] if event["event"] == "step"],
                             ["prepare", "model", "tool", "model", "verify"])
            first_round = outgoing[2:next(index for index, event in enumerate(outgoing) if event.get("step", {}).get("kind") == "tool")]
            self.assertTrue(all(event["event"] == "reasoning_delta" for event in first_round))
            self.assertEqual("".join(event["step"]["detail"] for event in first_round), "先检索证据。")
            self.assertEqual(outgoing[-1]["event"], "result")
            self.assertEqual(outgoing[-1]["payload"]["tools"], ["search_selected_sources"])
            first, second = [json.loads(call.args[0].data) for call in upstream.call_args_list]
            self.assertEqual(first["thinking"], {"type": "enabled"})
            self.assertTrue(first["stream"])
            self.assertEqual(second["messages"][-2]["reasoning_content"], "先检索证据。")
            self.assertEqual(second["messages"][-1]["tool_call_id"], "lookup")

            gateway.wfile = io.BytesIO()
            gateway.headers = {}
            upstream.side_effect = [event_stream([{"reasoning_content": "已读取原文。"}, {"content": encode(draft)}], "stop")]
            gateway.run_stream(self.selection)
            outgoing = [json.loads(line) for line in gateway.wfile.getvalue().splitlines()]
            self.assertEqual([event["step"]["kind"] for event in outgoing[:-1] if event["event"] == "step"],
                             ["prepare", "model", "reasoning", "verify"])
            self.assertEqual(outgoing[-1]["event"], "result")

            gateway.wfile = io.BytesIO()
            gateway.run_stream({**self.selection, "model": "unavailable"})
            failure = json.loads(gateway.wfile.getvalue())
            self.assertEqual(failure["event"], "error")
            self.assertIn("不可用", failure["message"])

            gateway.wfile = io.BytesIO()
            upstream.side_effect = [io.BytesIO(b'data: {"choices":[{"delta":{},"finish_reason":"stop"}]}\n')]
            gateway.run_stream(self.selection)
            terminal = json.loads(gateway.wfile.getvalue().splitlines()[-1])
            self.assertEqual(terminal["event"], "error")
            self.assertIn("流中断", terminal["message"])


if __name__ == "__main__":
    unittest.main()
