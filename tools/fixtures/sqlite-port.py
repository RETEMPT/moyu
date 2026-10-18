"""Test-only JSON-lines bridge to real SQLite; never loaded by the app."""
import json
import sqlite3
import sys

connection = sqlite3.connect(':memory:', isolation_level=None)
for line in sys.stdin:
    request = json.loads(line)
    try:
        cursor = connection.execute(request['sql'], request.get('args', []))
        rows = cursor.fetchall() if cursor.description else []
        print(json.dumps({'id': request['id'], 'rows': rows}, ensure_ascii=True), flush=True)
    except Exception as error:
        print(json.dumps({'id': request['id'], 'error': str(error)}), flush=True)
connection.close()
