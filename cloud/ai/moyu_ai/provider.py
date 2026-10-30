"""Ollama adapter: one bounded request, no tools, redirects or automatic retries."""

import json
import os
import urllib.error
import urllib.parse
import urllib.request

from .store import bounded, encode

MAX_RESPONSE_BYTES = 128 * 1024


def profile(endpoint, model, max_tokens=1600):
    parsed = urllib.parse.urlsplit(endpoint)
    try:
        port = parsed.port
    except ValueError as exc:
        raise ValueError("模型端点端口无效。") from exc
    if (parsed.scheme not in {"http", "https"} or not parsed.hostname or
            parsed.username is not None or parsed.password is not None or
            parsed.query or parsed.fragment or parsed.path not in {"", "/"} or
            any(c.isspace() or ord(c) < 32 for c in endpoint) or "\\" in endpoint):
        raise ValueError("端点须为无路径、凭据、查询参数的 HTTP(S) 服务地址。")
    if parsed.scheme == "http" and parsed.hostname not in {"localhost", "127.0.0.1", "::1"}:
        raise ValueError("仅回环地址允许 HTTP；其他模型端点必须使用 HTTPS。")
    if type(max_tokens) is not int or not 128 <= max_tokens <= 4096:
        raise ValueError("输出 token 上限须为 128–4096。")
    host = parsed.hostname.lower()
    if ":" in host:
        host = f"[{host}]"
    endpoint = f"{parsed.scheme}://{host}" + (f":{port}" if port is not None else "")
    return {"provider": "ollama", "endpoint": endpoint,
            "model": bounded(model, "模型名称", 160), "max_output_tokens": max_tokens}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class OllamaProvider:
    def __init__(self, config, timeout=60):
        if config != profile(config["endpoint"], config["model"], config["max_output_tokens"]):
            raise ValueError("模型配置无效。")
        if not 1 <= timeout <= 120:
            raise ValueError("网络超时须为 1–120 秒。")
        self.config = config
        self.timeout = timeout

    def generate(self, messages):
        body = encode({"model": self.config["model"], "messages": messages,
                       "stream": False, "format": "json",
                       "options": {"temperature": 0.2,
                                   "num_predict": self.config["max_output_tokens"]}}).encode("utf-8")
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        key = os.environ.get("MOYU_AI_API_KEY")
        if key:
            if self.config["endpoint"].startswith("http:"):
                raise ValueError("携带凭据时必须使用 HTTPS。")
            headers["Authorization"] = "Bearer " + key
        request = urllib.request.Request(self.config["endpoint"] + "/api/chat",
                                         data=body, headers=headers, method="POST")
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        try:
            with opener.open(request, timeout=self.timeout) as response:
                raw = response.read(MAX_RESPONSE_BYTES + 1)
        except urllib.error.HTTPError as exc:
            # Never echo provider response bodies: they can contain input or credentials.
            raise ValueError(f"模型服务返回 HTTP {exc.code}；未自动重试。") from None
        except (urllib.error.URLError, OSError, TimeoutError):
            raise ValueError("模型服务连接失败或超时；未自动重试。") from None
        if len(raw) > MAX_RESPONSE_BYTES:
            raise ValueError("模型服务响应超过 128 KiB。")
        try:
            response = json.loads(raw)
            message = response["message"]
            if response.get("done") is not True or message.get("tool_calls"):
                raise ValueError("模型响应未完成或尝试调用工具。")
            content = message["content"]
            if not isinstance(content, str) or len(content.encode("utf-8")) > 32768:
                raise ValueError("生成内容无效或超过 32 KiB。")
            output = json.loads(content)
            actual_model = bounded(response.get("model", self.config["model"]), "返回的模型标识", 200)
            usage = {}
            for source, target in [("prompt_eval_count", "input_tokens"), ("eval_count", "output_tokens")]:
                value = response.get(source)
                usage[target] = value if type(value) is int and value >= 0 else None
            return output, {"model": actual_model, "usage": usage}
        except (KeyError, TypeError, AttributeError, RecursionError, json.JSONDecodeError):
            raise ValueError("模型服务未返回有效的结构化 JSON。") from None
