"""HTTPS adapters for cloud Chat Completions, with provider-specific request fields."""

import http.client
import json
import os
import re
from time import monotonic
import urllib.error
import urllib.parse
import urllib.request

from .store import bounded, encode

MAX_RESPONSE_BYTES = 128 * 1024
MAX_STREAM_BYTES = 2 * 1024 * 1024
REASONING_EFFORTS = ("none", "low", "high")
PRESETS = {
    "deepseek": ("https://api.deepseek.com", "DEEPSEEK_API_KEY"),
    "qwen-cn": ("https://dashscope.aliyuncs.com/compatible-mode/v1", "DASHSCOPE_API_KEY"),
    "qwen-intl": ("https://dashscope-intl.aliyuncs.com/compatible-mode/v1", "DASHSCOPE_API_KEY"),
    "openai": ("https://api.openai.com/v1", "OPENAI_API_KEY"),
    "compatible": ("", "MOYU_AI_API_KEY"),
}
QWEN_WORKSPACE = {
    "qwen-cn": r"[a-z0-9-]+\.cn-beijing\.maas\.aliyuncs\.com",
    "qwen-intl": r"[a-z0-9-]+\.(?:ap-southeast-1|ap-northeast-1|us-east-1|cn-hongkong)\.maas\.aliyuncs\.com",
}


def https_base(value):
    if not isinstance(value, str) or any(char.isspace() or ord(char) < 32 for char in value) or any(char in value for char in "\\?#"):
        raise ValueError("模型 Base URL 无效。")
    try:
        parsed = urllib.parse.urlsplit(value)
        host, port = parsed.hostname, parsed.port
    except ValueError:
        raise ValueError("模型 Base URL 无效。") from None
    path = parsed.path.rstrip("/")
    if (parsed.scheme != "https" or not host or parsed.username is not None or parsed.password is not None
            or port == 0 or not re.fullmatch(r"(?:[a-z0-9][a-z0-9-]*\.)+[a-z][a-z0-9-]*", host)
            or host.endswith((".localhost", ".local", ".internal"))
            or not re.fullmatch(r"(?:/[a-zA-Z0-9_-]+)*", path)
            or path.endswith("/chat/completions")):
        raise ValueError("Base URL 须为 HTTPS 域名与接口前缀，不能含密钥、查询参数或 /chat/completions。")
    return urllib.parse.urlunsplit(("https", host + (f":{port}" if port and port != 443 else ""), path, "", ""))


def profile(provider, model, max_tokens=1600, *, base_url=None):
    if not isinstance(provider, str) or provider not in PRESETS:
        raise ValueError("请选择现有云模型供应商。旧 Ollama 任务可以查看，请为云端生成重新准备任务。")
    default_url, _ = PRESETS[provider]
    if not base_url and not default_url:
        raise ValueError("compatible 供应商需要指定 HTTPS Base URL。")
    url = https_base(base_url or default_url)
    if provider != "compatible" and url != default_url:
        parsed = urllib.parse.urlsplit(url)
        pattern = QWEN_WORKSPACE.get(provider)
        if (not pattern or not re.fullmatch(pattern, parsed.netloc)
                or parsed.path != "/compatible-mode/v1"):
            raise ValueError("端点与供应商或区域不匹配；自有兼容端点请选择 compatible。")
    if type(max_tokens) is not int or not 128 <= max_tokens <= 4096:
        raise ValueError("输出 token 上限须为 128–4096。")
    model = bounded(model, "模型名称", 160)
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/-]*", model):
        raise ValueError("模型名称无效，请使用供应商给出的模型 ID。")
    return {"provider": provider, "base_url": url, "model": model, "max_output_tokens": max_tokens}


def validate_profile(config):
    if not isinstance(config, dict) or not isinstance(config.get("provider"), str) or config["provider"] not in PRESETS:
        raise ValueError("模型配置不兼容，请选择云端供应商并重新准备任务。")
    expected = profile(config["provider"], config.get("model"), config.get("max_output_tokens"),
                       base_url=config.get("base_url"))
    if config != expected:
        raise ValueError("模型配置无效。")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def read_deepseek_stream(response, on_reasoning, on_web_event=None):
    message = {"role": "assistant", "content": "", "reasoning_content": ""}
    calls = {}
    metadata = {}
    finish = None
    received = 0
    limit = MAX_STREAM_BYTES * 4 if on_web_event else MAX_STREAM_BYTES
    while line := response.readline(min(MAX_RESPONSE_BYTES, limit - received + 1)):
        received += len(line)
        if received > limit or len(line) == MAX_RESPONSE_BYTES:
            raise ValueError("模型服务流式响应过大。")
        if not line.startswith(b"data:"):
            continue
        data = line[5:].strip()
        if data == b"[DONE]":
            if finish is None:
                break
            if calls:
                if sorted(calls) != list(range(len(calls))):
                    raise ValueError("模型返回的工具调用顺序无效。")
                message["tool_calls"] = [calls[index] for index in range(len(calls))]
            return metadata, {"finish_reason": finish}, message
        try:
            chunk = json.loads(data)
            for field in ("model", "usage"):
                if chunk.get(field) is not None:
                    metadata[field] = chunk[field]
            choices = chunk["choices"]
            if choices == []:
                continue  # DeepSeek can send usage in a separate chunk.
            choice = choices[0]
            delta = choice.get("delta") or {}
            if finish is not None or len(choices) != 1 or choice.get("index", 0) != 0:
                raise ValueError("模型服务返回了重复或无效的流式选择。")
            finish = choice.get("finish_reason")
            for field in ("content", "reasoning_content", "refusal"):
                value = delta.get(field)
                if value is not None:
                    message[field] = message.get(field, "") + value
                    if field == "reasoning_content" and on_reasoning:
                        on_reasoning(value)
            if on_web_event and choice.get("server_tool_event"):
                on_web_event(choice["server_tool_event"])
            if on_web_event and "annotations" in delta:
                message["annotations"] = delta["annotations"]
            for part in delta.get("tool_calls") or []:
                index = part["index"]
                if type(index) is not int or not 0 <= index < 3:
                    raise ValueError("模型返回了无效的资料工具请求。")
                call = calls.setdefault(index, {"function": {"arguments": ""}})
                function = part.get("function") or {}
                for field in ("id", "type"):
                    if field in part:
                        call[field] = part[field]
                if "name" in function:
                    call["function"]["name"] = function["name"]
                call["function"]["arguments"] += function.get("arguments") or ""
        except (KeyError, IndexError, TypeError, AttributeError, UnicodeError, RecursionError, json.JSONDecodeError):
            raise ValueError("模型服务未返回有效的 DeepSeek 流式事件。") from None
    raise ValueError("模型流中断，可重试本轮。")


def web_citations(content, annotations):
    links = {}
    for annotation in annotations or []:
        citation = annotation.get("url_citation") or {}
        url, title = citation.get("url"), citation.get("title")
        if annotation.get("type") != "url_citation" or not isinstance(url, str) or len(url) > 1500:
            continue
        if not re.fullmatch(r"https?://[A-Za-z0-9.-]+(?::[0-9]+)?(?:[/?#][^\s<>\\]*)?", url):
            continue
        host = urllib.parse.urlsplit(url).hostname
        if not host or "." not in host:
            continue
        label = " ".join(title.split())[:160] if isinstance(title, str) else ""
        links.setdefault(url, {"url": url, "title": label or host})
        if len(links) == 12:
            break
    return {"reply": content, "sources": list(links.values())}


class CloudChatProvider:
    def __init__(self, config, timeout=60):
        validate_profile(config)
        if not 1 <= timeout <= 120:
            raise ValueError("网络超时须为 1–120 秒。")
        key_name = PRESETS[config["provider"]][1]
        self._key = os.environ.get(key_name, "").strip()
        if not re.fullmatch(r"[!-~]+", self._key):
            raise ValueError(f"请通过环境变量 {key_name} 提供有效 API Key。")
        self.config = config
        self.timeout = timeout

    def _complete(self, messages, *, tools=None, tool_choice="auto", effort="none", on_reasoning=None, on_web_event=None, web=False):
        provider = self.config["provider"]
        streaming = on_reasoning is not None or on_web_event is not None
        payload = {"model": self.config["model"], "messages": messages, "stream": streaming,
                   "response_format": {"type": "text" if web else "json_object"}}
        if streaming:
            payload["stream_options"] = {"include_usage": True}
        if provider == "openai":
            payload["max_completion_tokens"] = self.config["max_output_tokens"]
            payload["store"] = False
        else:
            payload["max_tokens"] = self.config["max_output_tokens"]
        if provider == "deepseek":
            payload["thinking"] = {"type": "disabled" if effort == "none" else "enabled"}
            if effort != "none":
                payload["reasoning_effort"] = effort
                payload["max_tokens"] = max(12288 if effort == "high" else 6144, self.config["max_output_tokens"])
        elif provider in QWEN_WORKSPACE:
            payload["enable_thinking"] = False
        if tools:
            payload["tools"] = tools
            if effort == "none" or tool_choice == "none":
                payload["tool_choice"] = tool_choice
        request = urllib.request.Request(
            self.config["base_url"] + "/chat/completions", data=encode(payload).encode("utf-8"),
            headers={"Content-Type": "application/json", "Accept": "text/event-stream" if streaming else "application/json",
                     "Authorization": "Bearer " + self._key}, method="POST")
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        try:
            with opener.open(request, timeout=self.timeout) as response:
                if streaming:
                    return read_deepseek_stream(response, on_reasoning, on_web_event)
                raw = response.read(MAX_RESPONSE_BYTES + 1)
        except urllib.error.HTTPError as exc:
            raise ValueError(f"{provider} 返回 HTTP {exc.code}，未自动重试。") from None
        except (OSError, http.client.HTTPException):
            raise ValueError(f"{provider} 连接失败、响应中断或超时，未自动重试。") from None
        if len(raw) > MAX_RESPONSE_BYTES:
            raise ValueError("模型服务响应超过 128 KiB。")

        try:
            response = json.loads(raw)
            choice = response["choices"][0]
            message = choice["message"]
            if not isinstance(message, dict) or message.get("role", "assistant") != "assistant":
                raise ValueError("模型服务未返回有效的助手消息。")
            return response, choice, message
        except (KeyError, IndexError, TypeError, UnicodeError, RecursionError, json.JSONDecodeError):
            raise ValueError("模型服务未返回有效的 Chat Completions JSON。") from None

    def generate(self, messages, *, tools=None, run_tool=None, progress=None, effort=None, web=False):
        conversation = list(messages)
        deepseek = self.config["provider"] == "deepseek"
        effort = effort or ("low" if progress and deepseek else "none")
        thinking = effort != "none"
        if web:
            tools = [{"type": "deepseek_web_search"}]
        web_events = 0

        def publish_search(event):
            nonlocal web_events
            if event.get("type") == "call_completed" and web_events < 12:
                call = event.get("call") or {}
                action = call.get("action") or {}
                label = "检索网页" if action.get("type") == "search" else "查阅网页"
                progress("tool", label, "已完成" if call.get("status") == "completed" else "未获取结果")
                web_events += 1

        def complete(round_number, choice="auto"):
            if progress:
                progress("model", "调用模型", f"第 {round_number} 轮")
            options = {"tools": tools, "tool_choice": choice, "effort": effort, "web": web}
            buffered = ""
            shown = 0
            last_update = 0

            def publish_reasoning(value="", *, flush=False):
                nonlocal buffered, shown, last_update
                buffered += value[:4500 - shown - len(buffered)]
                now = monotonic()
                if buffered and (flush or now - last_update >= 0.25):
                    progress("reasoning", f"第 {round_number} 轮模型思考", buffered)
                    shown += len(buffered)
                    buffered = ""
                    last_update = now

            if thinking and progress:
                options["on_reasoning"] = publish_reasoning
            if web and progress:
                options["on_web_event"] = publish_search
            round_result = self._complete(conversation, **options)
            if thinking and progress:
                publish_reasoning(flush=True)
            return round_result

        response, choice, message = complete(1)
        seen = set()
        for round_index in range(2):
            if not (tools and run_tool and choice.get("finish_reason") == "tool_calls"):
                break
            calls = message.get("tool_calls")
            if not isinstance(calls, list) or not 1 <= len(calls) <= 3 or message.get("refusal"):
                raise ValueError("模型返回了无效的资料工具请求。")
            replies = []
            for call in calls:
                if not isinstance(call, dict) or call.get("type") != "function":
                    raise ValueError("模型返回了无效的资料工具请求。")
                identity, function = call.get("id"), call.get("function")
                if (not isinstance(identity, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", identity)
                        or identity in seen or not isinstance(function, dict)):
                    raise ValueError("模型返回了无效的资料工具请求。")
                seen.add(identity)
                replies.append({"role": "tool", "tool_call_id": identity, "content": encode(run_tool(function))})
            assistant = {"role": "assistant", "content": message.get("content") or None, "tool_calls": calls}
            if thinking:
                if not isinstance(message.get("reasoning_content"), str):
                    raise ValueError("模型未返回可继续工具调用的思考字段。")
                assistant["reasoning_content"] = message["reasoning_content"]
            conversation = [*conversation, assistant, *replies]
            # The final round must answer from the completed calls even if the model could search again.
            response, choice, message = complete(round_index + 2, "none" if round_index == 1 else "auto")

        try:
            if choice["finish_reason"] != "stop" or message.get("tool_calls") or message.get("function_call") or message.get("refusal"):
                raise ValueError("模型结果未正常完成、被拒绝或包含工具请求。")
            content = message["content"]
            if not isinstance(content, str) or not content.strip() or len(content.encode("utf-8")) > 32768:
                raise ValueError("模型正文为空或超出 32 KiB。")
            output = web_citations(content, message.get("annotations")) if web else json.loads(content)
            if not isinstance(output, dict):
                raise ValueError("模型正文须为 JSON 对象。")
            actual_model = bounded(response.get("model", self.config["model"]), "返回的模型标识", 200)
            usage = response.get("usage") or {}
            count = {}
            for source, target in (("prompt_tokens", "input_tokens"), ("completion_tokens", "output_tokens")):
                value = usage.get(source)
                count[target] = value if type(value) is int and value >= 0 else None
            return output, {"provider": self.config["provider"], "model": actual_model, "usage": count}
        except (KeyError, IndexError, TypeError, AttributeError, UnicodeError, RecursionError, json.JSONDecodeError):
            raise ValueError("模型服务未返回有效的 Chat Completions JSON。") from None
