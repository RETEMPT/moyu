"""Loopback gateway for the DevEco emulator, sharing the CLI's study workflow."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import re
import secrets
from threading import Lock
from uuid import uuid4

from .exchange import from_job, keys, serialize, text
from .provider import PRESETS, REASONING_EFFORTS, CloudChatProvider, profile
from .sources import digest, retrieve
from .store import encode
from .tutor import CHAT_REPLY_STYLE, study_messages, validate_output

PORT = 8765
MAX_REQUEST = 48 * 1024
MAX_CHAT_CONTEXT = 7000
MAX_STUDY_CONTEXT = 2400
DEEPSEEK_MODELS = {"deepseek-flash": "DeepSeek Flash", "deepseek-v4-pro": "DeepSeek V4 Pro"}


def options_for(value, provider):
    options = {}
    if "effort" in value:
        if provider.config["provider"] != "deepseek" or value["effort"] not in REASONING_EFFORTS:
            raise ValueError("此模型不支持所选思考深度。")
        options["effort"] = value["effort"]
    if "web" in value:
        if value["web"] is not True or provider.config["provider"] != "deepseek" or value["model"] != "deepseek-flash":
            raise ValueError("联网搜索当前仅支持 DeepSeek Flash。")
        options["web"] = True
    return options
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
READ_TOOL = {
    "type": "function",
    "function": {
        "name": "read_selected_source",
        "description": "读取已获用户确认的片段，用于核对引用和上下文。",
        "parameters": {
            "type": "object",
            "properties": {"source_id": {"type": "string", "description": "已选资料的片段编号，如 s1。"}},
            "required": ["source_id"],
            "additionalProperties": False,
        },
    },
}


def search_sources(function, sources):
    name = function.get("name")
    if name not in (SEARCH_TOOL["function"]["name"], READ_TOOL["function"]["name"]):
        raise ValueError("模型请求了网关未提供的工具。")
    arguments = function.get("arguments")
    if not isinstance(arguments, str) or len(arguments) > 2048:
        raise ValueError("资料检索参数无效。")
    try:
        args = json.loads(arguments)
        if name == READ_TOOL["function"]["name"]:
            keys(args, "source_id")
            text(args["source_id"], 24)
            selected = next((source for source in sources if source["id"] == args["source_id"]), None)
            return ({"source_id": selected["id"], "text": selected["text"]} if selected else
                    {"error": "片段不在本次已确认的资料中。"})
        keys(args, "query")
        text(args["query"], 120)
    except (ValueError, RecursionError):
        raise ValueError("资料检索参数无效。") from None
    return {"matches": [{"source_id": source["id"], "text": source["text"]}
                        for source in retrieve(sources, args["query"], limit=3)]}


def generate(value, providers, *, trace=False, progress=None):
    required = {"model", "operation", "goal", "sources"}
    if not isinstance(value, dict) or not required <= value.keys() <= required | {"context", "focus", "effort"}:
        raise ValueError("资料请求格式无效，请确认电脑网关与调试包版本一致。")
    model = value["model"]
    if not isinstance(model, str) or model not in providers:
        raise ValueError("此模型在电脑网关中不可用，请重新连接并选择模型。")
    provider = providers[model]
    operation = value["operation"]
    if operation not in ("qa", "summary", "report", "quiz"):
        raise ValueError("未知的学习任务。")
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
    context = value.get("context", [])
    if not isinstance(context, list) or len(context) > 8 or len(context) % 2:
        raise ValueError("资料问答的对话上下文格式无效。")
    context_units = 0
    for index, item in enumerate(context):
        keys(item, "role content")
        expected = "assistant" if index % 2 else "user"
        if item["role"] != expected:
            raise ValueError("资料问答的对话上下文顺序无效。")
        text(item["content"], 800 if expected == "assistant" else 1200)
        context_units += len(item["content"].encode("utf-16-le")) // 2
    if context_units > MAX_STUDY_CONTEXT:
        raise ValueError("资料问答的对话上下文过长。")
    focus = value.get("focus")
    if "focus" in value:
        keys(focus, "source_id quote")
        text(focus["source_id"], 24)
        text(focus["quote"], 480, 4)
        if not any(source["id"] == focus["source_id"] and focus["quote"] in source["text"] for source in sources):
            raise ValueError("当前引用已变化或不在本次确认的资料范围内。")
    agent = provider.config["provider"] == "deepseek"
    messages = study_messages(operation, goal, sources, search_tool=agent, context=context, focus=focus, conversation=trace)
    used_tools = []
    def execute(call):
        labels = {"search_selected_sources": "检索附件", "read_selected_source": "读取原文"}
        result = search_sources(call, sources)
        if progress:
            arguments = json.loads(call["arguments"])
            if "matches" in result:
                detail = f'关键词「{arguments["query"]}」，匹配 {len(result["matches"])} 个片段'
            elif "error" in result:
                detail = result["error"]
            else:
                detail = f'已读取 {result["source_id"]}，共 {len(result["text"])} 字符'
            progress("tool", labels[call["name"]], detail)
        if call["name"] not in used_tools:
            used_tools.append(call["name"])
        return result

    if progress:
        progress("prepare", "已限定附件范围", f"{len(sources)} 个已确认的片段")
    options = options_for(value, provider)
    if progress:
        options["progress"] = progress
    if agent:
        draft, _ = provider.generate(messages, tools=[SEARCH_TOOL, READ_TOOL], run_tool=execute, **options)
    else:
        draft, _ = provider.generate(messages, **options)
    payload = {"operation": operation, "sources": sources}
    validate_output(draft, payload)
    if progress:
        count = sum(len(section["citations"]) for section in draft["sections"])
        progress("verify", "已校验引用", f"{count} 处引用与发送片段一致")
    result = serialize(from_job({"id": "demo_" + uuid4().hex, "payload": payload,
                                 "result": {"draft": draft, "warnings": []}}))
    return encode({"result": json.loads(result), "tools": used_tools}).encode("utf-8") if trace else result


def chat(value, providers, *, progress=None):
    required = {"model", "messages"}
    if not isinstance(value, dict) or not required <= value.keys() <= required | {"effort", "web"}:
        raise ValueError("对话请求格式无效。")
    model = value["model"]
    if not isinstance(model, str) or model not in providers:
        raise ValueError("此模型在电脑网关中不可用，请重新连接并选择模型。")
    history = value["messages"]
    if not isinstance(history, list) or not 1 <= len(history) <= 13 or len(history) % 2 == 0:
        raise ValueError("对话格式无效。")

    provider = providers[model]
    options = options_for(value, provider)
    web = options.get("web")
    mode = ('需要检索资料时使用联网工具并引用来源。请直接输出 Markdown。' if web else
            '当前没有提供资料库内容。输出 JSON 对象，只包含字符串字段 "reply"。')
    messages = [{"role": "system", "content": '你是墨语学习对话助手。请用用户的语言回答。' + CHAT_REPLY_STYLE + mode}]
    units = 0
    for index, item in enumerate(history):
        keys(item, "role content")
        role = "user" if index % 2 == 0 else "assistant"
        limit = 1200 if role == "user" else 4800
        content = item["content"]
        if item["role"] != role or not isinstance(content, str) or not content.strip():
            raise ValueError("对话消息格式无效。")
        length = len(content.encode("utf-16-le")) // 2
        units += length
        if length > limit or units > MAX_CHAT_CONTEXT:
            raise ValueError("对话内容过长，请缩短问题或新建对话。")
        messages.append({"role": role, "content": content})

    if progress:
        options["progress"] = progress
    answer, _ = provider.generate(messages, **options)
    keys(answer, "reply sources" if web else "reply")
    reply = answer["reply"]
    if not isinstance(reply, str) or not reply.strip() or len(reply.encode("utf-16-le")) // 2 > 4800:
        raise ValueError("模型返回的回复为空或过长。")
    answer["reply"] = reply.strip()
    return encode(answer).encode("utf-8")


def handler(providers, pairing_code):
    busy = Lock()
    allowed_hosts = {f"127.0.0.1:{PORT}", f"10.0.2.2:{PORT}"}
    catalog = encode({"models": [
        {"id": model, "label": DEEPSEEK_MODELS.get(model, f"DeepSeek · {model}")
         if provider.config["provider"] == "deepseek" else f'{provider.config["provider"]} · {model}',
         "agent": provider.config["provider"] == "deepseek", "reasoning": provider.config["provider"] == "deepseek",
         "webSearch": provider.config["provider"] == "deepseek" and model == "deepseek-flash"}
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
            if self.path not in ("/v1/study", "/v1/chat", "/v1/agent", "/v1/agent/run", "/v1/chat/run"):
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
                if self.path.endswith("/run"):
                    self.run_stream(value)
                else:
                    result = chat(value, providers) if self.path == "/v1/chat" else generate(
                        value, providers, trace=self.path == "/v1/agent")
                    self.reply(200, result)
            except (UnicodeError, RecursionError):
                self.error_json(422, "资料文字无效。")
            except ValueError as error:
                self.error_json(422, str(error))
            finally:
                busy.release()

        def run_stream(self, value):
            live = self.headers.get("X-Moyu-Trace") == "live-v1"
            pending = None

            def send(event):
                self.wfile.write((encode(event) + "\n").encode("utf-8"))
                self.wfile.flush()

            def flush_reasoning():
                nonlocal pending
                if pending:
                    send({"event": "step", "step": pending})
                    pending = None

            def progress(kind, title, detail):
                nonlocal pending
                step = {"kind": kind, "title": title, "detail": detail}
                if kind == "reasoning" and not live:
                    if pending is None:
                        pending = step
                    else:
                        pending["detail"] += detail
                    return
                flush_reasoning()
                send({"event": "reasoning_delta" if kind == "reasoning" else "step", "step": step})

            try:
                self.send_response(200)
                self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Connection", "close")
                self.end_headers()
                try:
                    result = chat(value, providers, progress=progress) if self.path == "/v1/chat/run" else generate(
                        value, providers, trace=True, progress=progress)
                    flush_reasoning()
                    send({"event": "result", "payload": json.loads(result)})
                except (UnicodeError, RecursionError):
                    flush_reasoning()
                    send({"event": "error", "message": "资料文字无效。"})
                except ValueError as error:
                    flush_reasoning()
                    send({"event": "error", "message": str(error)})
            except OSError:
                # A stopped client need not wait for the upstream round already in progress.
                pass

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
