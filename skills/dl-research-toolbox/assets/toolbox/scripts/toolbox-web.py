#!/usr/bin/env python3
# Local-only web control panel for DL Research Toolbox.
from __future__ import annotations

import argparse
import datetime as _dt
import html
import json
import os
import secrets
import subprocess
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PORT = 8765
MAX_OUTPUT_CHARS = 20000
TOKEN = ""
SERVER_HOST = "127.0.0.1"
SERVER_PORT = DEFAULT_PORT

ACTIONS: dict[str, tuple[str, list[str], int]] = {
    "mihomo_start": ("启动 mihomo", ["bash", "scripts/mihomo-start.sh"], 45),
    "mihomo_stop": ("停止 mihomo", ["bash", "scripts/mihomo-stop.sh"], 45),
    "mihomo_restart": ("重启 mihomo", ["bash", "-lc", "bash scripts/mihomo-stop.sh && bash scripts/mihomo-start.sh"], 60),
    "mihomo_status": ("刷新 mihomo 状态", ["bash", "scripts/mihomo-status.sh", "--test-proxy", "--no-log"], 90),
    "doctor_quick": ("快速体检", ["bash", "scripts/doctor.sh", "--quick"], 120),
    "doctor_full": ("完整体检", ["bash", "scripts/doctor.sh"], 300),
    "deep_proxy": ("深度代理检查", ["bash", "scripts/verify-proxy-deep.sh"], 300),
    "autostart_status": ("自启状态", ["bash", "scripts/mihomo-autostart.sh", "status"], 60),
    "autostart_install": ("安装/修复自启", ["bash", "scripts/mihomo-autostart.sh", "install", "--mode", "auto", "--enable-linger"], 120),
}


def now_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).astimezone().isoformat(timespec="seconds")


def trim_output(text: str) -> str:
    if len(text) <= MAX_OUTPUT_CHARS:
        return text
    return text[-MAX_OUTPUT_CHARS:] + "\n[output trimmed]\n"


def run_cmd(cmd: list[str], timeout: int) -> dict[str, Any]:
    started = time.time()
    try:
        proc = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
            env=os.environ.copy(),
        )
        output = proc.stdout or ""
        return {
            "ok": proc.returncode == 0,
            "code": proc.returncode,
            "duration_sec": round(time.time() - started, 2),
            "output": trim_output(output),
        }
    except subprocess.TimeoutExpired as exc:
        output = exc.stdout or ""
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        return {
            "ok": False,
            "code": 124,
            "duration_sec": round(time.time() - started, 2),
            "output": trim_output(output + f"\n[timeout after {timeout}s]\n"),
        }


def read_pid_state() -> dict[str, Any]:
    state_dir = Path(os.environ.get("MIHOMO_STATE_DIR", str(Path.home() / ".local/state/mihomo")))
    pid_file = Path(os.environ.get("MIHOMO_PID_FILE", str(state_dir / "mihomo.pid")))
    config_file = Path(os.environ.get("MIHOMO_CONFIG_DIR", str(Path.home() / ".config/mihomo"))) / "config.yaml"
    pid = ""
    running = False
    if pid_file.exists():
        pid = pid_file.read_text(errors="replace").strip()
        if pid.isdigit():
            try:
                os.kill(int(pid), 0)
                running = True
            except ProcessLookupError:
                running = False
            except PermissionError:
                running = True
    return {
        "config_exists": config_file.exists(),
        "config_path": str(config_file),
        "pid_file": str(pid_file),
        "pid": pid,
        "running": running,
    }


def status_payload() -> dict[str, Any]:
    return {
        "time": now_iso(),
        "repo_root": str(REPO_ROOT),
        "mihomo": read_pid_state(),
        "status": run_cmd(["bash", "scripts/mihomo-status.sh", "--no-log"], 30),
    }


def page_html() -> str:
    token_js = json.dumps(TOKEN)
    port = SERVER_PORT
    return f'''<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>DL Research Toolbox</title>
  <style>
    :root {{
      color-scheme: light dark;
      --bg: #f6f7f9;
      --panel: #ffffff;
      --text: #16181d;
      --muted: #5f6876;
      --border: #d9dde5;
      --accent: #176b87;
      --ok: #157347;
      --bad: #b42318;
      --code: #0f172a;
    }}
    @media (prefers-color-scheme: dark) {{
      :root {{
        --bg: #101317;
        --panel: #171b21;
        --text: #edf1f7;
        --muted: #9aa4b2;
        --border: #2b313b;
        --accent: #65b7cf;
        --ok: #53c27d;
        --bad: #ff8a7a;
        --code: #05070a;
      }}
    }}
    * {{ box-sizing: border-box; }}
    body {{ margin: 0; font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: var(--bg); color: var(--text); }}
    header {{ padding: 28px 24px 18px; border-bottom: 1px solid var(--border); background: var(--panel); }}
    main {{ max-width: 1180px; margin: 0 auto; padding: 24px; }}
    h1 {{ margin: 0 0 8px; font-size: 28px; letter-spacing: 0; }}
    h2 {{ margin: 0 0 12px; font-size: 18px; letter-spacing: 0; }}
    p {{ color: var(--muted); line-height: 1.55; }}
    .wrap {{ max-width: 1180px; margin: 0 auto; }}
    .grid {{ display: grid; grid-template-columns: repeat(12, 1fr); gap: 16px; }}
    .panel {{ background: var(--panel); border: 1px solid var(--border); border-radius: 8px; padding: 16px; }}
    .span-4 {{ grid-column: span 4; }}
    .span-8 {{ grid-column: span 8; }}
    .span-12 {{ grid-column: span 12; }}
    @media (max-width: 800px) {{ .span-4, .span-8 {{ grid-column: span 12; }} main {{ padding: 16px; }} }}
    .status {{ display: flex; align-items: center; gap: 10px; font-weight: 700; }}
    .dot {{ width: 10px; height: 10px; border-radius: 50%; background: var(--muted); }}
    .dot.ok {{ background: var(--ok); }}
    .dot.bad {{ background: var(--bad); }}
    .muted {{ color: var(--muted); }}
    .actions {{ display: flex; flex-wrap: wrap; gap: 8px; }}
    button {{ border: 1px solid var(--border); background: var(--panel); color: var(--text); border-radius: 6px; padding: 9px 12px; font-size: 14px; cursor: pointer; }}
    button.primary {{ background: var(--accent); color: #fff; border-color: var(--accent); }}
    button.danger {{ color: var(--bad); }}
    button:disabled {{ opacity: 0.55; cursor: wait; }}
    pre {{ margin: 0; padding: 14px; border-radius: 8px; overflow: auto; background: var(--code); color: #e5e7eb; min-height: 180px; max-height: 560px; white-space: pre-wrap; word-break: break-word; }}
    code {{ font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; }}
    .kv {{ display: grid; grid-template-columns: 140px 1fr; gap: 8px 12px; font-size: 14px; }}
    .kv div:nth-child(odd) {{ color: var(--muted); }}
  </style>
</head>
<body>
  <header>
    <div class="wrap">
      <h1>DL Research Toolbox 控制台</h1>
      <p>通过 SSH 端口转发访问的本地控制台。默认只监听服务器 <code>127.0.0.1</code>，用于 mihomo 启停、代理检查和安装后体检。</p>
    </div>
  </header>
  <main>
    <div class="grid">
      <section class="panel span-4">
        <h2>mihomo</h2>
        <div class="status"><span id="run-dot" class="dot"></span><span id="run-text">读取中</span></div>
        <p id="config-text" class="muted">配置状态读取中</p>
        <div class="actions">
          <button class="primary" data-action="mihomo_start">启动</button>
          <button class="danger" data-action="mihomo_stop">停止</button>
          <button data-action="mihomo_restart">重启</button>
          <button data-action="mihomo_status">代理出口检查</button>
        </div>
      </section>
      <section class="panel span-4">
        <h2>体检</h2>
        <p>快速体检适合确认代理和机器状态，完整体检会检查 GitHub、Hugging Face、PyPI、npm、Codex CLI、uv 和 Python 工具层。</p>
        <div class="actions">
          <button class="primary" data-action="doctor_quick">快速体检</button>
          <button data-action="doctor_full">完整体检</button>
          <button data-action="deep_proxy">深度代理检查</button>
        </div>
      </section>
      <section class="panel span-4">
        <h2>自启</h2>
        <p>默认推荐 <code>auto</code> 模式：优先 systemd system service，必要时退到 user/profile。</p>
        <div class="actions">
          <button data-action="autostart_status">查看自启</button>
          <button data-action="autostart_install">安装/修复自启</button>
        </div>
      </section>
      <section class="panel span-8">
        <h2>输出</h2>
        <pre id="output">等待操作...</pre>
      </section>
      <section class="panel span-4">
        <h2>连接方式</h2>
        <p>服务器上启动：</p>
        <pre><code>cd ~/dl-research-toolbox
bash scripts/web-ui.sh --port {port}</code></pre>
        <p>本地机器转发：</p>
        <pre><code>ssh -N -L {port}:127.0.0.1:{port} user@server</code></pre>
      </section>
      <section class="panel span-12">
        <h2>状态详情</h2>
        <div class="kv">
          <div>仓库</div><div id="repo">-</div>
          <div>时间</div><div id="time">-</div>
          <div>PID</div><div id="pid">-</div>
          <div>PID 文件</div><div id="pid-file">-</div>
          <div>配置文件</div><div id="config-path">-</div>
        </div>
      </section>
    </div>
  </main>
  <script>
    const REQUIRED_TOKEN = {token_js};
    const url = new URL(window.location.href);
    const token = url.searchParams.get('token') || REQUIRED_TOKEN || '';
    const out = document.getElementById('output');
    const buttons = Array.from(document.querySelectorAll('button[data-action]'));

    function apiUrl(path) {{
      const u = new URL(path, window.location.origin);
      if (token) u.searchParams.set('token', token);
      return u.toString();
    }}

    function setBusy(busy) {{ buttons.forEach(b => b.disabled = busy); }}
    function writeOutput(text) {{ out.textContent = text || '(no output)'; }}

    async function refresh() {{
      const res = await fetch(apiUrl('/api/status'));
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || 'status failed');
      document.getElementById('repo').textContent = data.repo_root;
      document.getElementById('time').textContent = data.time;
      document.getElementById('pid').textContent = data.mihomo.pid || '-';
      document.getElementById('pid-file').textContent = data.mihomo.pid_file;
      document.getElementById('config-path').textContent = data.mihomo.config_path;
      document.getElementById('config-text').textContent = data.mihomo.config_exists ? '配置文件存在' : '配置文件缺失';
      const dot = document.getElementById('run-dot');
      dot.className = 'dot ' + (data.mihomo.running ? 'ok' : 'bad');
      document.getElementById('run-text').textContent = data.mihomo.running ? '运行中' : '未运行';
      writeOutput(data.status.output);
    }}

    async function runAction(action) {{
      setBusy(true);
      writeOutput('运行中: ' + action + ' ...');
      try {{
        const res = await fetch(apiUrl('/api/action'), {{
          method: 'POST',
          headers: {{ 'Content-Type': 'application/json' }},
          body: JSON.stringify({{ action }})
        }});
        const data = await res.json();
        writeOutput(`[${{data.ok ? 'ok' : 'fail'}}] ${{data.label}}\nexit=${{data.code}} duration=${{data.duration_sec}}s\n\n${{data.output || ''}}`);
        await refresh();
      }} catch (err) {{
        writeOutput(String(err));
      }} finally {{
        setBusy(false);
      }}
    }}

    buttons.forEach(btn => btn.addEventListener('click', () => runAction(btn.dataset.action)));
    refresh().catch(err => writeOutput(String(err)));
    setInterval(() => refresh().catch(() => {{}}), 20000);
  </script>
</body>
</html>'''


class Handler(BaseHTTPRequestHandler):
    server_version = "DLResearchToolboxWeb/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("[%s] %s\n" % (now_iso(), fmt % args))

    def token_ok(self) -> bool:
        if not TOKEN:
            return True
        query = parse_qs(urlparse(self.path).query)
        provided = query.get("token", [""])[0] or self.headers.get("X-Toolbox-Token", "")
        return secrets.compare_digest(provided, TOKEN)

    def send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, text: str, status: int = 200, content_type: str = "text/plain; charset=utf-8") -> None:
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def require_token(self) -> bool:
        if self.token_ok():
            return True
        self.send_json({"ok": False, "error": "forbidden: invalid or missing token"}, 403)
        return False

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/healthz":
            self.send_json({"ok": True, "time": now_iso()})
            return
        if not self.require_token():
            return
        if parsed.path in ("/", "/index.html"):
            self.send_text(page_html(), content_type="text/html; charset=utf-8")
            return
        if parsed.path == "/api/status":
            self.send_json(status_payload())
            return
        self.send_json({"ok": False, "error": "not found"}, 404)

    def do_POST(self) -> None:  # noqa: N802
        if not self.require_token():
            return
        parsed = urlparse(self.path)
        if parsed.path != "/api/action":
            self.send_json({"ok": False, "error": "not found"}, 404)
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self.send_json({"ok": False, "error": "invalid json"}, 400)
            return
        action = str(payload.get("action", ""))
        if action not in ACTIONS:
            self.send_json({"ok": False, "error": "unknown action"}, 400)
            return
        label, cmd, timeout = ACTIONS[action]
        result = run_cmd(cmd, timeout)
        result.update({"label": label, "action": action})
        self.send_json(result, 200 if result["ok"] else 500)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Local web UI for DL Research Toolbox")
    parser.add_argument("--host", default=os.environ.get("TOOLBOX_WEB_HOST", "127.0.0.1"), help="Bind host. Default: 127.0.0.1")
    parser.add_argument("--port", type=int, default=int(os.environ.get("TOOLBOX_WEB_PORT", DEFAULT_PORT)), help=f"Bind port. Default: {DEFAULT_PORT}")
    parser.add_argument("--token", default=os.environ.get("TOOLBOX_WEB_TOKEN", ""), help="Access token. Default: random token")
    parser.add_argument("--no-token", action="store_true", help="Disable token check. Only use with localhost binding.")
    return parser.parse_args()


def main() -> int:
    global TOKEN, SERVER_HOST, SERVER_PORT
    args = parse_args()
    SERVER_HOST = args.host
    SERVER_PORT = args.port
    TOKEN = "" if args.no_token else (args.token or secrets.token_urlsafe(24))

    if args.host not in ("127.0.0.1", "localhost", "::1"):
        print("WARNING: binding outside localhost. Prefer SSH port forwarding with --host 127.0.0.1.", file=sys.stderr)

    server = ThreadingHTTPServer((args.host, args.port), Handler)

    print("DL Research Toolbox web UI")
    print(f"repo: {REPO_ROOT}")
    print(f"listen: http://{args.host}:{args.port}")
    if TOKEN:
        print(f"open: http://127.0.0.1:{args.port}/?token={html.escape(TOKEN)}")
    else:
        print(f"open: http://127.0.0.1:{args.port}/")
    print("ssh tunnel from your local machine:")
    print(f"  ssh -N -L {args.port}:127.0.0.1:{args.port} user@server")
    print("Press Ctrl-C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
