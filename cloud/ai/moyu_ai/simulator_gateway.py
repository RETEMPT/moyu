"""Loopback gateway for the DevEco emulator, sharing the CLI's study workflow."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import re
import secrets
from threading import Lock
from uuid import uuid4

from .exchange import from_job, keys, serialize, text
from .provider import PRESETS, CloudChatProvider, profile
from .sources import digest, retrieve
from .store import encode
from .tutor import study_messages, validate_output

PORT = 8765
MAX_REQUEST = 48 * 1024
DEEPSEEK_MODELS = {"deepseek-flash": "DeepSeek Flash", "deepseek-v4-pro": "DeepSeek V4 Pro"}
SEARCH_TOOL = {
    "type": "function",
    "function": {
        "name": "search_selected_sources",
        "description": "按关键词查找用户已确认发送的资料片段。",
        "parameters": {
            "type": "object",
            "properties": {"query": {"type": "string", "description": "原文关键词，最多 120 个字符。"}},
            "required": ["query"],
            "additionalProperties": False,
        },
    },
}


def search_sources(function, sources):
    if function.get("name") != SEARCH_TOOL["function"]["name"]:
        raise ValueError("模型请求了网关未提供的工具。")
    arguments = function.get("arguments")
    if not isinstance(arguments, str) or len(arguments) > 2048:
        raise ValueError("资料检索参数无效。")
    try:
        args = json.loads(arguments)
        keys(args, "query")
        text(args["query"], 120)
    except (ValueError, RecursionError):
        raise ValueError("资料检索参数无效。") from None
    return {"matches": [{"source_id": source["id"], "text": source["text"]}
                        for source in retrieve(sources, args["query"], limit=3)]}


def generate(value, providers):
    keys(value, "model operation goal sources")
    model = value["model"]
    if not isinstance(model, str) or model not in providers:
        raise ValueError("此模型在电脑网关中不可用，请重新连接并选择模型。")
    provider = providers[model]
    operation = value["operation"]
    if operation not in ("qa", "summary", "report"):
        raise ValueError("模拟器支持问答、摘要和周报。")
    goal = value["goal"]
    text(goal, 800)
    sources = []
    ids = set()
    if not isinstance(value["sources"], list) or not 1 <= len(value["sources"]) <= 12:
        raise ValueError("请选择 1–12 个资料片段。")
    for fragment in value["sources"]:
        keys(fragment, "id text")
        source_id, content = fragment["id"], fragment["text"]
        text(source_id, 24)
        text(content, 1200, 4)
        if not re.fullmatch(r"s[1-9][0-9]*", source_id) or source_id in ids:
            raise ValueError("片段标识无效。")
        ids.add(source_id)
        sources.append({"id": source_id, "name": f"所选片段 {len(sources) + 1}", "text": content,
                        "revision": 1, "digest": digest(content), "line_start": 1, "line_end": len(content.split("\n"))})
    if sum(len(source["text"].encode("utf-16-le")) // 2 for source in sources) > 12000:
        raise ValueError("资料超过 12000 个 UTF-16 单元，请缩小范围。")
    agent = provider.config["provider"] == "deepseek"
    messages = study_messages(operation, goal, sources, search_tool=agent)
    if agent:
        draft, _ = provider.generate(messages, tools=[SEARCH_TOOL], run_tool=lambda call: search_sources(call, sources))
    else:
        draft, _ = provider.generate(messages)
    payload = {"operation": operation, "sources": sources}
    validate_output(draft, payload)
    return serialize(from_job({"id": "demo_" + uuid4().hex, "payload": payload,
                               "result": {"draft": draft, "warnings": ["仅覆盖所选资料，结论请对照原文。"]}}))


def handler(providers, pairing_code):
    busy = Lock()
    allowed_hosts = {f"127.0.0.1:{PORT}", f"10.0.2.2:{PORT}"}
    catalog = encode({"models": [
        {"id": model, "label": DEEPSEEK_MODELS.get(model, f"DeepSeek · {model}")
         if provider.config["provider"] == "deepseek" else f'{provider.config["provider"]} · {model}',
         "agent": provider.config["provider"] == "deepseek"}
        for model, provider in providers.items()
    ]}).encode("utf-8")

    class GatewayHandler(BaseHTTPRequestHandler):
        def setup(self):
            self.request.settimeout(8)
            super().setup()

        def log_message(self, format, *args):
            pass

        def reply(self, status, body):
            try:
                self.send_response(status)
                self.send_header("Content-Type", "application/json; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(body)
            except OSError:
                # The emulator may have closed the request while a cloud call was in flight.
                pass

        def error_json(self, status, message):
            self.reply(status, encode({"error": message}).encode("utf-8"))

        def authorized(self):
            token = self.headers.get("X-Moyu-Pairing", "")
            if (self.headers.get("Host") not in allowed_hosts or not token.isascii()
                    or not secrets.compare_digest(token, pairing_code)):
                self.error_json(403, "配对码错误或已过期。")
                return False
            return True

        def do_GET(self):
            if self.path != "/v1/models":
                self.error_json(404, "未知接口。")
            elif self.authorized():
                self.reply(200, catalog)

        def do_POST(self):
            if self.path != "/v1/study":
                self.error_json(404, "未知接口。")
                return
            if not self.authorized():
                return
            size = self.headers.get("Content-Length", "")
            if (self.headers.get_content_type() != "application/json" or self.headers.get("Transfer-Encoding")
                    or not re.fullmatch(r"[0-9]{1,6}", size) or not 0 < int(size) <= MAX_REQUEST):
                self.error_json(400, "请求格式或大小无效。")
                return
            try:
                raw = self.rfile.read(int(size))
                if len(raw) != int(size):
                    raise ValueError("请求正文不完整。")
                value = json.loads(raw.decode("utf-8"))
            except (ValueError, OSError, RecursionError):
                self.error_json(400, "请求正文不完整或不是 UTF-8 JSON。")
                return
            if not busy.acquire(blocking=False):
                self.error_json(409, "上一个请求仍在处理，请稍后再试。")
                return
            try:
                self.reply(200, generate(value, providers))
            except (UnicodeError, RecursionError):
                self.error_json(422, "资料文字无效。")
            except ValueError as error:
                self.error_json(422, str(error))
            finally:
                busy.release()

    return GatewayHandler


def main():
    parser = argparse.ArgumentParser(description="在电脑回环接口开启墨语模拟器网关。")
    parser.add_argument("--provider", choices=PRESETS, default="deepseek")
    parser.add_argument("--model", action="append", help="可重复指定，以在模拟器列出多个模型。")
    parser.add_argument("--base-url")
    args = parser.parse_args()
    try:
        models = args.model or (list(DEEPSEEK_MODELS) if args.provider == "deepseek" else [])
        if not 1 <= len(models) <= 12 or len(set(models)) != len(models):
            raise ValueError("请提供 1–12 个不同的模型 ID。")
        providers = {model: CloudChatProvider(profile(args.provider, model, base_url=args.base_url), timeout=30)
                     for model in models}
        pairing_code = secrets.token_hex(16)
        with ThreadingHTTPServer(("127.0.0.1", PORT), handler(providers, pairing_code)) as server:
            print(f"墨语模拟器网关  http://127.0.0.1:{PORT}  {args.provider} / {', '.join(models)}", flush=True)
            print(f"配对码  {pairing_code}", flush=True)
            server.serve_forever()
    except KeyboardInterrupt:
        print("网关已停止。")
    except (ValueError, OSError) as error:
        parser.exit(1, f"网关启动失败：{error}\n")


if __name__ == "__main__":
    main()
