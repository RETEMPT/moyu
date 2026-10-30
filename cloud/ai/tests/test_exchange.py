import copy
from contextlib import redirect_stderr, redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from cloud.ai.moyu_ai.cli import main
from cloud.ai.moyu_ai.exchange import MAX_BYTES, OPERATIONS, decode, serialize
from cloud.ai.moyu_ai.tutor import OPERATIONS as TUTOR_OPERATIONS

FIXTURE = json.loads((Path(__file__).resolve().parents[3] /
                      "tools/fixtures/learning-result.json").read_text(encoding="utf-8"))


def changed(case):
    value = copy.deepcopy(FIXTURE["result"])
    for path, replacement in case["changes"]:
        parts = path.split(".")
        current = value
        for part in parts[:-1]:
            current = current[int(part)] if isinstance(current, list) else current[part]
        key = int(parts[-1]) if isinstance(current, list) else parts[-1]
        current[key] = replacement
    return value


class ExchangeTest(unittest.TestCase):
    def test_shared_cross_runtime_contract(self):
        self.assertEqual(set(OPERATIONS), set(TUTOR_OPERATIONS))
        for case in FIXTURE["cases"]:
            with self.subTest(case=case["name"]):
                raw = json.dumps(changed(case), ensure_ascii=True).encode("utf-8")
                if case["valid"]:
                    self.assertEqual(decode(raw), decode(serialize(decode(raw))))
                else:
                    with self.assertRaises(ValueError):
                        decode(raw)

    def test_size_unicode_and_duplicate_source_limits(self):
        with self.assertRaises(ValueError):
            decode(b" " * (MAX_BYTES + 1))
        for size, accepted in [(100, True), (101, False)]:
            value = copy.deepcopy(FIXTURE["result"])
            value["title"] = "🧭" * size
            if accepted:
                serialize(value)
            else:
                with self.assertRaises(ValueError):
                    serialize(value)
        value = copy.deepcopy(FIXTURE["result"])
        value["sources"].append(value["sources"][0])
        with self.assertRaises(ValueError):
            serialize(value)

    def test_capabilities_and_validation_do_not_open_workspace_or_network(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "result.json"
            path.write_bytes(serialize(FIXTURE["result"]))
            for command in [["capabilities"], ["validate-result", str(path)]]:
                with patch("cloud.ai.moyu_ai.cli.Store") as store, \
                        patch("urllib.request.OpenerDirector.open") as network, \
                        redirect_stdout(io.StringIO()) as output:
                    self.assertEqual(main(command), 0)
                    self.assertIsInstance(json.loads(output.getvalue()), dict)
                store.assert_not_called()
                network.assert_not_called()
            path.write_text('{"format": "unsupported"}', encoding="utf-8")
            with redirect_stderr(io.StringIO()):
                self.assertEqual(main(["validate-result", str(path)]), 1)


if __name__ == "__main__":
    unittest.main()
