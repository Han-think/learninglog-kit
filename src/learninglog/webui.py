"""webui — 브라우저 기반 설치/설정/실행 UI (learninglog ui).

아무나 설치 후 'learninglog ui' 한 줄이면:
  - 작업 폴더 생성/선택
  - LLM provider 설정 (Gemini 기본 안내)
  - API 키 입력 + 연결 테스트
  - 노트 처리 / 블로그 발행을 버튼으로 실행

의존성: pip install "learninglog-kit[web]"  (fastapi, uvicorn)
"""

from __future__ import annotations

import csv
import os
import subprocess
import sys
import threading
import webbrowser
from pathlib import Path

from .config import find_config, load_config


# ─────────────────────────────────────────────────────────
# Gemini 우선 provider 안내 데이터
# ─────────────────────────────────────────────────────────
PROVIDERS = {
    "gemini": {
        "name": "Gemini (Google) — 무료 추천",
        "url": "https://aistudio.google.com/app/apikey",
        "hint": "구글 계정으로 로그인 → Create API key → AIzaSy... 복사",
        "needs_key": True, "default_model": "gemini-1.5-flash",
    },
    "groq": {
        "name": "Groq — 무료 (초고속)",
        "url": "https://console.groq.com",
        "hint": "무료 가입 → API Keys → Create → gsk_... 복사",
        "needs_key": True, "default_model": "llama-3.1-8b-instant",
    },
    "ollama": {
        "name": "Ollama — 완전 무료 (로컬)",
        "url": "https://ollama.com",
        "hint": "Ollama 설치 후: ollama pull gemma3:4b / ollama serve",
        "needs_key": False, "default_model": "gemma3:4b",
    },
}


def _html() -> str:
    return """<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LearningLog 설정</title>
<style>
  :root { --bg:#1a1713; --fg:#f5ede0; --acc:#c49a4a; --mut:#7a6e62; --card:#23201a; --line:#352e24; }
  * { box-sizing:border-box; }
  body { margin:0; font-family:'Noto Sans KR',system-ui,sans-serif; background:var(--bg); color:var(--fg); line-height:1.6; }
  .wrap { max-width:720px; margin:0 auto; padding:2rem 1.2rem 4rem; }
  h1 { font-size:1.5rem; margin:.2rem 0; }
  h2 { font-size:1.05rem; border-left:3px solid var(--acc); padding-left:.6rem; margin:2rem 0 .8rem; }
  .sub { color:var(--mut); font-size:.9rem; margin-top:0; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:10px; padding:1.2rem; margin-bottom:1rem; }
  label { display:block; font-size:.85rem; color:var(--mut); margin:.6rem 0 .2rem; }
  input, select { width:100%; padding:.6rem .7rem; background:var(--bg); color:var(--fg);
    border:1px solid var(--line); border-radius:7px; font-size:.95rem; }
  .prov { display:flex; gap:.5rem; flex-wrap:wrap; margin:.4rem 0; }
  .prov button { flex:1; min-width:150px; text-align:left; padding:.7rem; cursor:pointer;
    background:var(--bg); border:1px solid var(--line); border-radius:8px; color:var(--fg); }
  .prov button.on { border-color:var(--acc); background:#2d2718; }
  .prov .pn { font-weight:600; font-size:.9rem; }
  .prov .pu { color:var(--mut); font-size:.75rem; margin-top:.2rem; word-break:break-all; }
  button.act { background:var(--acc); color:#1a1713; border:none; border-radius:8px;
    padding:.7rem 1.1rem; font-weight:700; cursor:pointer; font-size:.95rem; }
  button.act:disabled { opacity:.5; cursor:default; }
  button.ghost { background:transparent; color:var(--fg); border:1px solid var(--line);
    border-radius:8px; padding:.6rem 1rem; cursor:pointer; }
  .row { display:flex; gap:.6rem; flex-wrap:wrap; align-items:center; margin-top:.8rem; }
  .hint { font-size:.82rem; color:var(--mut); margin-top:.4rem; }
  .hint a { color:var(--acc); }
  .stat { display:flex; gap:1.5rem; flex-wrap:wrap; }
  .stat div { text-align:center; }
  .stat .n { font-size:1.6rem; font-weight:700; color:var(--acc); }
  .stat .l { font-size:.75rem; color:var(--mut); }
  pre { background:#000; color:#ccc; padding:.9rem; border-radius:8px; font-size:.78rem;
    max-height:320px; overflow:auto; white-space:pre-wrap; }
  .ok { color:#7bbf7b; } .err { color:#cf6679; } .warn { color:#d4b04a; }
  .pill { display:inline-block; padding:.15rem .55rem; border-radius:20px; font-size:.72rem; border:1px solid var(--line); }
</style></head>
<body><div class="wrap">
  <h1>LearningLog <span style="color:var(--acc)">설정</span></h1>
  <p class="sub">설치 → 위치 → API키 → 실행. 브라우저에서 버튼으로 끝.</p>

  <h2>1. 작업 폴더</h2>
  <div class="card">
    <div id="proj"></div>
    <div class="hint">강의자료는 <code>00_inbox/lectures/</code>, 개인노트(.md)는 <code>00_inbox/personal_notes/</code> 에 넣습니다.</div>
    <div class="row"><button class="ghost" onclick="initFolders()">이 위치에 폴더 구조 생성</button></div>
  </div>

  <h2>2. LLM 선택 + API 키</h2>
  <div class="card">
    <div class="prov" id="provs"></div>
    <div id="keybox">
      <label>API 키 붙여넣기</label>
      <input id="apikey" type="password" placeholder="여기에 키 붙여넣기" autocomplete="off">
      <div class="hint" id="keyhint"></div>
    </div>
    <div class="row">
      <button class="act" onclick="saveCfg()">저장 + 연결 테스트</button>
      <span id="savestat"></span>
    </div>
  </div>

  <h2>3. 실행</h2>
  <div class="card">
    <div class="stat" id="stat"><div><div class="n">–</div><div class="l">전체</div></div></div>
    <div class="row">
      <button class="ghost" onclick="run('intake')">① intake 등록</button>
      <button class="ghost" onclick="run('extract')">② extract 처리</button>
      <button class="ghost" onclick="run('publish')">③ publish 발행</button>
      <button class="ghost" onclick="loadStatus()">↻ 새로고침</button>
    </div>
    <div class="row"><pre id="out">대기 중...</pre></div>
  </div>
</div>
<script>
let provider = "gemini";
let provData = {};

async function boot() {
  const r = await fetch('/api/info'); const d = await r.json();
  provData = d.providers; provider = d.current_provider || "gemini";
  document.getElementById('proj').innerHTML =
    `<span class="pill">📁 ${d.project_dir}</span> ` +
    (d.has_config ? '<span class="pill ok">설정됨</span>' : '<span class="pill warn">미설정</span>');
  const pe = document.getElementById('provs'); pe.innerHTML = '';
  for (const [k,v] of Object.entries(provData)) {
    const b = document.createElement('button');
    b.className = 'prov-b' + (k===provider?' on':'');
    b.dataset.k = k;
    b.innerHTML = `<div class="pn">${v.name}</div><div class="pu">${v.url}</div>`;
    b.onclick = ()=>{ provider=k; document.querySelectorAll('#provs button').forEach(x=>x.classList.remove('on')); b.classList.add('on'); renderKey(); };
    pe.appendChild(b);
  }
  renderKey(); loadStatus();
}
function renderKey() {
  const v = provData[provider];
  document.getElementById('keybox').style.display = v.needs_key ? 'block' : 'none';
  document.getElementById('keyhint').innerHTML = v.needs_key
    ? `발급: <a href="${v.url}" target="_blank">${v.url}</a> — ${v.hint}`
    : v.hint;
}
async function initFolders() {
  setOut('폴더 생성 중...');
  const r = await fetch('/api/init', {method:'POST'}); const d = await r.json();
  setOut(d.output); boot();
}
async function saveCfg() {
  const key = document.getElementById('apikey').value.trim();
  document.getElementById('savestat').textContent = '저장+테스트 중...';
  const r = await fetch('/api/setup', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({provider, api_key:key})});
  const d = await r.json();
  document.getElementById('savestat').innerHTML = d.ok
    ? '<span class="ok">✓ '+d.msg+'</span>' : '<span class="err">✗ '+d.msg+'</span>';
}
async function run(step) {
  setOut('▶ '+step+' 실행 중... (모델 로딩에 시간이 걸릴 수 있음)');
  const r = await fetch('/api/run/'+step, {method:'POST'}); const d = await r.json();
  setOut(d.output); loadStatus();
}
async function loadStatus() {
  const r = await fetch('/api/status'); const d = await r.json();
  document.getElementById('stat').innerHTML =
    `<div><div class="n">${d.total}</div><div class="l">전체 소스</div></div>
     <div><div class="n">${d.pending}</div><div class="l">대기</div></div>
     <div><div class="n">${d.drafted}</div><div class="l">초안</div></div>
     <div><div class="n">${d.published}</div><div class="l">발행</div></div>`;
}
function setOut(t){ document.getElementById('out').textContent = t; }
boot();
</script>
</body></html>"""


def create_app(project_dir: Path):
    try:
        from fastapi import FastAPI, Request
        from fastapi.responses import HTMLResponse, JSONResponse
    except ImportError:
        raise ImportError('웹 UI에는 추가 설치가 필요합니다: pip install "learninglog-kit[web]"')

    app = FastAPI(title="LearningLog UI")

    def _cfg_path() -> Path:
        return project_dir / ".learninglog" / "config.yaml"

    @app.get("/", response_class=HTMLResponse)
    def index():
        return _html()

    @app.get("/api/info")
    def info():
        cfg = load_config(_cfg_path()) if _cfg_path().exists() else {}
        return JSONResponse({
            "project_dir": str(project_dir),
            "has_config": _cfg_path().exists(),
            "current_provider": cfg.get("llm", {}).get("provider", "gemini"),
            "providers": PROVIDERS,
        })

    @app.post("/api/init")
    def api_init():
        out = _run_cmd(["init", str(project_dir)], skip_wizard=True)
        return JSONResponse({"output": out})

    @app.post("/api/setup")
    async def api_setup(request: Request):
        body = await request.json()
        prov = body.get("provider", "gemini")
        key  = (body.get("api_key") or "").strip()
        info = PROVIDERS.get(prov, {})

        # config.yaml 보장
        if not _cfg_path().exists():
            _run_cmd(["init", str(project_dir)], skip_wizard=True)

        from .setup_wizard import _update_config
        extra = {"host": "http://127.0.0.1:11434", "num_ctx": 4096} if prov == "ollama" else None
        _update_config(_cfg_path(), prov,
                       api_key=(key if info.get("needs_key") else None),
                       model=info.get("default_model", ""), extra=extra)

        # 연결 테스트
        if info.get("needs_key") and not key:
            return JSONResponse({"ok": False, "msg": "API 키를 입력하세요"})
        ok, msg = _test(prov, key, info.get("default_model", ""))
        return JSONResponse({"ok": ok, "msg": msg})

    @app.get("/api/status")
    def status():
        return JSONResponse(_status(project_dir))

    @app.post("/api/run/{step}")
    def run_step(step: str):
        if step not in ("intake", "extract", "publish", "queue"):
            return JSONResponse({"output": "알 수 없는 단계: " + step})
        return JSONResponse({"output": _run_cmd([step])})

    def _run_cmd(args: list[str], skip_wizard: bool = False) -> str:
        env = dict(os.environ)
        if skip_wizard:
            env["LEARNINGLOG_NO_WIZARD"] = "1"
        try:
            r = subprocess.run([sys.executable, "-m", "learninglog", *args],
                               cwd=str(project_dir), capture_output=True, text=True,
                               timeout=1800, env=env, encoding="utf-8", errors="replace")
            return (r.stdout or "") + (("\n[stderr]\n" + r.stderr) if r.stderr.strip() else "")
        except Exception as e:
            return f"실행 오류: {e}"

    return app


def _test(provider: str, key: str, model: str):
    try:
        if provider == "gemini":
            import google.generativeai as genai
            genai.configure(api_key=key)
            genai.GenerativeModel(model).generate_content("hi")
        elif provider == "groq":
            from groq import Groq
            Groq(api_key=key).chat.completions.create(
                model=model, messages=[{"role": "user", "content": "hi"}], max_tokens=5)
        elif provider == "ollama":
            import httpx
            httpx.get("http://127.0.0.1:11434/", timeout=3)
        return True, "연결 성공 — 설정 완료"
    except ImportError:
        return False, f'라이브러리 미설치: pip install "learninglog-kit[{provider}]"'
    except Exception as e:
        return False, f"연결 실패: {str(e)[:120]}"


def _status(project_dir: Path) -> dict:
    reg = project_dir / "01_registry" / "source_registry.csv"
    s = {"total": 0, "pending": 0, "drafted": 0, "published": 0}
    if reg.exists():
        with open(reg, encoding="utf-8") as f:
            for row in csv.DictReader(f):
                s["total"] += 1
                st = row.get("status", "")
                if st in ("registered", "new"): s["pending"] += 1
                elif st == "drafted": s["drafted"] += 1
                elif st == "published": s["published"] += 1
    return s


def run_ui(host: str = "127.0.0.1", port: int = 8765, project_dir: Path | None = None) -> None:
    try:
        import uvicorn
    except ImportError:
        raise ImportError('웹 UI에는 추가 설치가 필요합니다: pip install "learninglog-kit[web]"')

    pdir = project_dir or Path.cwd()
    cf = find_config(pdir)
    if cf:
        pdir = cf.parent.parent

    app = create_app(pdir)
    url = f"http://{host}:{port}"
    threading.Timer(1.0, lambda: webbrowser.open(url)).start()
    print(f"\n  LearningLog UI → {url}\n  (종료: Ctrl+C)\n")
    uvicorn.run(app, host=host, port=port, log_level="warning")
