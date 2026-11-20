"""HTTPS adapters for cloud Chat Completions, with provider-specific request fields."""

import http.client
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request

from .store import bounded, encode

MAX_RESPONSE_BYTES = 128 * 1024
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

    def _complete(self, messages, *, tools=None, tool_choice="auto"):
        provider = self.config["provider"]
        payload = {"model": self.config["model"], "messages": messages, "stream": False,
                   "response_format": {"type": "json_object"}}
        if provider == "openai":
            payload["max_completion_tokens"] = self.config["max_output_tokens"]
            payload["store"] = False
        else:
            payload["max_tokens"] = self.config["max_output_tokens"]
        if provider == "deepseek":
            payload["thinking"] = {"type": "disabled"}
        elif provider in QWEN_WORKSPACE:
            payload["enable_thinking"] = False
        if tools:
            payload["tools"] = tools
            payload["tool_choice"] = tool_choice
        request = urllib.request.Request(
            self.config["base_url"] + "/chat/completions", data=encode(payload).encode("utf-8"),
            headers={"Content-Type": "application/json", "Accept": "application/json",
                     "Authorization": "Bearer " + self._key}, method="POST")
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        try:
            with opener.open(request, timeout=self.timeout) as response:
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

    def generate(self, messages, *, tools=None, run_tool=None):
        response, choice, message = self._complete(messages, tools=tools)
        if tools and run_tool and choice.get("finish_reason") == "tool_calls":
            calls = message.get("tool_calls")
            if not isinstance(calls, list) or not 1 <= len(calls) <= 3 or message.get("refusal"):
                raise ValueError("模型返回了无效的资料工具请求。")
            replies = []
            seen = set()
            for call in calls:
                if not isinstance(call, dict) or call.get("type") != "function":
                    raise ValueError("模型返回了无效的资料工具请求。")
                identity, function = call.get("id"), call.get("function")
                if (not isinstance(identity, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", identity)
                        or identity in seen or not isinstance(function, dict)):
                    raise ValueError("模型返回了无效的资料工具请求。")
                seen.add(identity)
                replies.append({"role": "tool", "tool_call_id": identity, "content": encode(run_tool(function))})
            assistant = {"role": "assistant", "content": message.get("content"), "tool_calls": calls}
            response, choice, message = self._complete([*messages, assistant, *replies], tools=tools, tool_choice="none")

        try:
            if choice["finish_reason"] != "stop" or message.get("tool_calls") or message.get("function_call") or message.get("refusal"):
                raise ValueError("模型结果未正常完成、被拒绝或包含工具请求。")
            content = message["content"]
            if not isinstance(content, str) or not content.strip() or len(content.encode("utf-8")) > 32768:
                raise ValueError("模型正文为空或超出 32 KiB。")
            output = json.loads(content)
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
