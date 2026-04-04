#!/bin/bash
# dashboard-web.sh — 웹 대시보드 (HTML 껍데기 + JSON 데이터 분리)
# HTML은 한번만 생성, 데이터는 refresh로 갱신, 브라우저 자동 새로고침
# Usage:
#   forge dashboard web       — HTML + 데이터 생성, 브라우저에서 열기
#   forge dashboard refresh   — 데이터만 갱신 (브라우저가 자동으로 반영)

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"
source "${GOLEM_ROOT}/lib/rank-system.sh"

# 출력 경로
DASHBOARD_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/dashboard"
DASHBOARD_HTML="${DASHBOARD_DIR}/index.html"
DASHBOARD_DATA="${DASHBOARD_DIR}/data.json"

# ─────────────────────────────────────────────────────────
# 데이터 수집 (JSON)
# ─────────────────────────────────────────────────────────

_dashboard_collect_souls() {
  local first=true
  echo "["
  while IFS= read -r soul_file; do
    [ -f "$soul_file" ] || continue
    soul_parse "$soul_file"
    local tasks=$(growth_log_task_count "$SOUL_NAME")
    local rate=$(growth_log_success_rate "$SOUL_NAME")
    local streak=$(growth_log_streak "$SOUL_NAME")
    local cost=$(_growth_log_total_cost "$SOUL_NAME" 2>/dev/null || echo "0.000")
    local ach_count=0
    local ach_file="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/achievements.jsonl"
    [ -f "$ach_file" ] && ach_count=$(grep -c "\"soul\":\"${SOUL_NAME}\"" "$ach_file" 2>/dev/null | tr -d ' \r')
    local spec=""
    local st_file="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/skill-trees.jsonl"
    [ -f "$st_file" ] && spec=$(grep "\"soul\":\"${SOUL_NAME}\"" "$st_file" 2>/dev/null | tail -1 | grep -o '"branch":"[^"]*"' | sed 's/"branch":"//;s/"//')
    local mem_count=0
    local mem_file="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/memory/${SOUL_NAME}.jsonl"
    [ -f "$mem_file" ] && mem_count=$(wc -l < "$mem_file" | tr -d ' \r')
    local next_rank="" progress=0
    case "$SOUL_RANK" in
      novice) next_rank="junior"; [ "$tasks" -gt 0 ] && progress=$((tasks * 100 / 10)); [ $progress -gt 100 ] && progress=100 ;;
      junior) next_rank="senior"; [ "$tasks" -gt 0 ] && progress=$((tasks * 100 / 50)); [ $progress -gt 100 ] && progress=100 ;;
      senior) next_rank="lead"; [ "$tasks" -gt 0 ] && progress=$((tasks * 100 / 100)); [ $progress -gt 100 ] && progress=100 ;;
      lead)   next_rank="master"; [ "$tasks" -gt 0 ] && progress=$((tasks * 100 / 200)); [ $progress -gt 100 ] && progress=100 ;;
      master) next_rank="max"; progress=100 ;;
    esac
    [ "$first" = true ] && first=false || echo ","
    echo "  {\"name\":\"${SOUL_NAME}\",\"role\":\"${SOUL_ROLE}\",\"rank\":\"${SOUL_RANK}\",\"model\":\"${SOUL_MODEL}\",\"specialty\":\"${SOUL_SPECIALTY}\",\"tasks\":${tasks},\"rate\":${rate},\"streak\":${streak},\"cost\":\"${cost}\",\"achievements\":${ach_count},\"spec\":\"${spec}\",\"memories\":${mem_count},\"nextRank\":\"${next_rank}\",\"progress\":${progress},\"isolation\":\"${SOUL_ISOLATION:-none}\",\"maxTurns\":${SOUL_MAX_TURNS:-15}}"
  done < <(_all_soul_files)
  echo "]"
}

_dashboard_collect_chemistry() {
  local chem_file="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/chemistry.jsonl"
  [ ! -f "$chem_file" ] && { echo "[]"; return; }
  echo "["
  local first=true
  grep -o '"pair":"[^"]*"' "$chem_file" | sort -u | sed 's/"pair":"//;s/"//' | while IFS= read -r pair; do
    [ -z "$pair" ] && continue
    local s1=$(echo "$pair" | cut -d: -f1) s2=$(echo "$pair" | cut -d: -f2)
    local total=$(grep "\"pair\":\"${pair}\"" "$chem_file" | wc -l | tr -d ' \r')
    local positive=$(grep "\"pair\":\"${pair}\"" "$chem_file" | grep -c '"result":"positive"' | tr -d ' \r')
    local score=$(( 50 + (positive * 2 - total) * 50 / (total > 0 ? total : 1) ))
    [ "$score" -lt 0 ] && score=0; [ "$score" -gt 100 ] && score=100
    [ "$first" = true ] && first=false || echo ","
    echo "  {\"pair\":\"${pair}\",\"s1\":\"${s1}\",\"s2\":\"${s2}\",\"score\":${score},\"records\":${total}}"
  done
  echo "]"
}

_dashboard_collect_sessions() {
  local sess_dir="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/sessions"
  echo "["
  local first=true
  if [ -d "$sess_dir" ]; then
    for meta in "$sess_dir"/*.meta; do
      [ -f "$meta" ] || continue
      local name=$(basename "$meta" .meta)
      local task=$(grep -o '"task":"[^"]*"' "$meta" | sed 's/"task":"//;s/"//')
      local status=$(grep -o '"status":"[^"]*"' "$meta" | sed 's/"status":"//;s/"//')
      local started=$(grep -o '"started":"[^"]*"' "$meta" | sed 's/"started":"//;s/"//')
      [ "$first" = true ] && first=false || echo ","
      echo "  {\"name\":\"${name}\",\"task\":\"${task}\",\"status\":\"${status}\",\"started\":\"${started}\"}"
    done
  fi
  echo "]"
}

# ─────────────────────────────────────────────────────────
# 데이터 JSON 생성 (refresh)
# ─────────────────────────────────────────────────────────

dashboard_web_refresh() {
  mkdir -p "$DASHBOARD_DIR"

  local project_name=$(basename "${GOLEM_PROJECT:-$(pwd)}")
  local generated=$(date +"%Y-%m-%d %H:%M:%S")
  local soul_count=0
  while IFS= read -r f; do [ -f "$f" ] && soul_count=$((soul_count+1)); done < <(_all_soul_files)
  local retro_dir="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/retrospectives"
  local retro_count=0
  [ -d "$retro_dir" ] && retro_count=$(ls "$retro_dir"/*.md 2>/dev/null | wc -l | tr -d ' \r')

  local dna_langs="" dna_fws="" dna_arch="" dna_domain=""
  local dna_file="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/project-dna.json"
  if [ -f "$dna_file" ]; then
    dna_langs=$(grep -o '"languages":"[^"]*"' "$dna_file" | sed 's/"languages":"//;s/"//')
    dna_fws=$(grep -o '"frameworks":"[^"]*"' "$dna_file" | sed 's/"frameworks":"//;s/"//')
    dna_arch=$(grep -o '"architecture":"[^"]*"' "$dna_file" | sed 's/"architecture":"//;s/"//')
    dna_domain=$(grep -o '"domain":"[^"]*"' "$dna_file" | sed 's/"domain":"//;s/"//')
  fi

  local souls_json=$(_dashboard_collect_souls)
  local chemistry_json=$(_dashboard_collect_chemistry)
  local sessions_json=$(_dashboard_collect_sessions)

  cat > "$DASHBOARD_DATA" <<DATAEOF
{
  "project": "${project_name}",
  "generated": "${generated}",
  "soulCount": ${soul_count},
  "retroCount": ${retro_count},
  "dna": {"languages":"${dna_langs}","frameworks":"${dna_fws}","architecture":"${dna_arch}","domain":"${dna_domain}"},
  "souls": ${souls_json},
  "chemistry": ${chemistry_json},
  "sessions": ${sessions_json}
}
DATAEOF

  echo "[dashboard] 데이터 갱신: ${DASHBOARD_DATA} (${generated})"
}

# ─────────────────────────────────────────────────────────
# HTML 껍데기 생성 (한번만)
# ─────────────────────────────────────────────────────────

dashboard_web_generate() {
  mkdir -p "$DASHBOARD_DIR"

  # 데이터 먼저 생성
  dashboard_web_refresh

  # HTML이 이미 있으면 데이터만 갱신
  if [ -f "$DASHBOARD_HTML" ]; then
    echo "[dashboard] HTML 이미 존재 — 데이터만 갱신됨"
    echo "  브라우저를 열어두면 30초마다 자동 갱신됩니다."
    echo "  수동 갱신: forge dashboard refresh"
    return
  fi

  cat > "$DASHBOARD_HTML" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>GolemGarden Dashboard</title>
<style>
:root{--bg:#0d1117;--card:#161b22;--border:#30363d;--text:#c9d1d9;--text-dim:#8b949e;--accent:#58a6ff;--green:#3fb950;--yellow:#d29922;--red:#f85149;--purple:#bc8cff;--orange:#d18616}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,'Segoe UI',monospace;background:var(--bg);color:var(--text);padding:20px}
.header{text-align:center;padding:20px 0 30px;border-bottom:1px solid var(--border);margin-bottom:30px}
.header h1{font-size:28px;color:var(--accent);margin-bottom:4px}
.header .sub{color:var(--text-dim);font-size:14px}
.header .meta{display:flex;justify-content:center;gap:24px;margin-top:12px;font-size:13px;color:var(--text-dim);flex-wrap:wrap}
.header .meta span{background:var(--card);padding:4px 12px;border-radius:12px;border:1px solid var(--border)}
.auto-refresh{font-size:11px;color:var(--green);margin-top:8px}
.auto-refresh.stale{color:var(--yellow)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:16px;margin-bottom:24px}
.card{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:16px}
.card h2{font-size:14px;color:var(--text-dim);text-transform:uppercase;letter-spacing:1px;margin-bottom:12px;border-bottom:1px solid var(--border);padding-bottom:8px}
.soul-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}
.soul-name{font-size:18px;font-weight:bold;color:var(--accent)}
.soul-rank{font-size:12px;padding:2px 8px;border-radius:10px;font-weight:bold}
.rank-novice{background:#1f2d1f;color:var(--green);border:1px solid var(--green)}
.rank-junior{background:#2d2b1f;color:var(--yellow);border:1px solid var(--yellow)}
.rank-senior{background:#2d1f2d;color:var(--purple);border:1px solid var(--purple)}
.rank-lead{background:#2d1f1f;color:var(--orange);border:1px solid var(--orange)}
.rank-master{background:#1f1f2d;color:var(--red);border:1px solid var(--red)}
.soul-role{color:var(--text-dim);font-size:13px}
.soul-stats{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin:10px 0}
.stat{text-align:center}.stat-value{font-size:18px;font-weight:bold}.stat-label{font-size:10px;color:var(--text-dim);text-transform:uppercase}
.progress-bar{height:6px;background:var(--border);border-radius:3px;overflow:hidden;margin-top:8px}
.progress-fill{height:100%;border-radius:3px;transition:width 0.5s}
.progress-label{font-size:11px;color:var(--text-dim);margin-top:4px;text-align:right}
.tags{display:flex;flex-wrap:wrap;gap:4px;margin-top:8px}
.tag{font-size:11px;padding:1px 6px;border-radius:4px;background:var(--bg);border:1px solid var(--border);color:var(--text-dim)}
.tag.spec{border-color:var(--purple);color:var(--purple)}
.tag.mem{border-color:var(--accent);color:var(--accent)}
.tag.ach{border-color:var(--yellow);color:var(--yellow)}
table{width:100%;border-collapse:collapse;font-size:13px}
th{text-align:left;color:var(--text-dim);font-weight:normal;padding:6px 8px;border-bottom:1px solid var(--border)}
td{padding:6px 8px;border-bottom:1px solid #21262d}
.chem-score{font-weight:bold}
.grade-S{color:var(--green)}.grade-A{color:#3fb950}.grade-B{color:var(--yellow)}.grade-C{color:var(--text-dim)}.grade-D{color:var(--orange)}.grade-F{color:var(--red)}
.dna-grid{display:grid;grid-template-columns:repeat(2,1fr);gap:8px}
.dna-item label{font-size:11px;color:var(--text-dim);display:block}.dna-item span{font-size:14px}
.session-status{padding:1px 6px;border-radius:4px;font-size:11px}
.status-active{background:#1f2d1f;color:var(--green)}.status-completed{background:var(--bg);color:var(--text-dim)}
.summary-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(120px,1fr));gap:12px}
.summary-item{text-align:center;padding:12px;background:var(--bg);border-radius:6px;border:1px solid var(--border)}
.summary-item .num{font-size:24px;font-weight:bold;color:var(--accent)}.summary-item .label{font-size:11px;color:var(--text-dim);margin-top:4px}
.footer{text-align:center;padding:20px;color:var(--text-dim);font-size:12px;border-top:1px solid var(--border);margin-top:30px}
</style>
</head>
<body>
<div class="header">
  <h1>GolemGarden Dashboard</h1>
  <div class="sub">AI Agent Growth & Team Orchestration</div>
  <div class="meta" id="headerMeta"></div>
  <div class="auto-refresh" id="autoRefresh">Auto-refresh: loading...</div>
</div>
<div class="card" style="margin-bottom:24px"><h2>Overview</h2><div class="summary-grid" id="summaryGrid"></div></div>
<div class="grid" id="soulGrid"></div>
<div class="grid">
  <div class="card"><h2>Team Chemistry</h2><div id="chemTable"></div></div>
  <div class="card"><h2>Project DNA</h2><div class="dna-grid" id="dnaGrid"></div></div>
</div>
<div class="card" style="margin-bottom:24px"><h2>Recent Sessions</h2><div id="sessionTable"></div></div>
<div class="footer">GolemGarden — Read-Only Dashboard | <span id="genTime"></span></div>

<script>
const REFRESH_INTERVAL = 30000; // 30초마다 자동 갱신
let lastData = null;

function grade(s){return s>=90?'S':s>=75?'A':s>=60?'B':s>=40?'C':s>=20?'D':'F'}

function render(DATA) {
  document.getElementById('headerMeta').innerHTML = `
    <span>Project: ${DATA.project}</span><span>SOULs: ${DATA.soulCount}</span><span>Retros: ${DATA.retroCount}</span>`;
  document.getElementById('genTime').textContent = 'Data: ' + DATA.generated;

  const totalTasks=DATA.souls.reduce((a,s)=>a+s.tasks,0);
  const totalCost=DATA.souls.reduce((a,s)=>a+parseFloat(s.cost),0).toFixed(3);
  const avgRate=DATA.souls.length?Math.round(DATA.souls.reduce((a,s)=>a+s.rate,0)/DATA.souls.length):0;
  const totalAch=DATA.souls.reduce((a,s)=>a+s.achievements,0);
  const totalMem=DATA.souls.reduce((a,s)=>a+s.memories,0);
  document.getElementById('summaryGrid').innerHTML=`
    <div class="summary-item"><div class="num">${DATA.soulCount}</div><div class="label">SOULs</div></div>
    <div class="summary-item"><div class="num">${totalTasks}</div><div class="label">Tasks</div></div>
    <div class="summary-item"><div class="num">${avgRate}%</div><div class="label">Success</div></div>
    <div class="summary-item"><div class="num">$${totalCost}</div><div class="label">Cost</div></div>
    <div class="summary-item"><div class="num">${totalAch}</div><div class="label">Achievements</div></div>
    <div class="summary-item"><div class="num">${totalMem}</div><div class="label">Memories</div></div>
    <div class="summary-item"><div class="num">${DATA.retroCount}</div><div class="label">Retros</div></div>
    <div class="summary-item"><div class="num">${DATA.sessions.length}</div><div class="label">Sessions</div></div>`;

  document.getElementById('soulGrid').innerHTML=DATA.souls.map(s=>{
    const pc=s.progress>=80?'var(--green)':s.progress>=50?'var(--yellow)':'var(--accent)';
    const tags=[];
    if(s.spec)tags.push(`<span class="tag spec">${s.spec}</span>`);
    if(s.memories>0)tags.push(`<span class="tag mem">${s.memories} memories</span>`);
    if(s.achievements>0)tags.push(`<span class="tag ach">${s.achievements} badges</span>`);
    return`<div class="card"><div class="soul-header"><span class="soul-name">${s.name}</span><span class="soul-rank rank-${s.rank}">${s.rank.toUpperCase()}</span></div><div class="soul-role">${s.role} · ${s.model} · T:${s.maxTurns} · ${s.isolation}</div><div class="soul-stats"><div class="stat"><div class="stat-value">${s.tasks}</div><div class="stat-label">Tasks</div></div><div class="stat"><div class="stat-value">${s.rate}%</div><div class="stat-label">Success</div></div><div class="stat"><div class="stat-value">${s.streak}</div><div class="stat-label">Streak</div></div><div class="stat"><div class="stat-value">$${s.cost}</div><div class="stat-label">Cost</div></div></div><div class="progress-bar"><div class="progress-fill" style="width:${s.progress}%;background:${pc}"></div></div><div class="progress-label">${s.rank==='master'?'MAX':s.progress+'% -> '+s.nextRank}</div>${tags.length?'<div class="tags">'+tags.join('')+'</div>':''}</div>`;
  }).join('');

  if(DATA.chemistry.length>0){
    document.getElementById('chemTable').innerHTML=`<table><tr><th>Pair</th><th>Score</th><th>Grade</th><th>Records</th></tr>${DATA.chemistry.map(c=>{const g=grade(c.score);return`<tr><td>${c.s1} + ${c.s2}</td><td class="chem-score">${c.score}</td><td class="grade-${g}">${g}</td><td>${c.records}</td></tr>`;}).join('')}</table>`;
  } else {
    document.getElementById('chemTable').innerHTML='<div style="color:var(--text-dim);font-size:13px;padding:8px">No chemistry data yet.</div>';
  }

  const d=DATA.dna;
  if(d.languages||d.frameworks){
    document.getElementById('dnaGrid').innerHTML=`<div class="dna-item"><label>Languages</label><span>${d.languages||'—'}</span></div><div class="dna-item"><label>Frameworks</label><span>${d.frameworks||'—'}</span></div><div class="dna-item"><label>Architecture</label><span>${d.architecture||'—'}</span></div><div class="dna-item"><label>Domain</label><span>${d.domain||'—'}</span></div>`;
  } else {
    document.getElementById('dnaGrid').innerHTML='<div style="color:var(--text-dim);font-size:13px">No DNA yet.</div>';
  }

  if(DATA.sessions.length>0){
    document.getElementById('sessionTable').innerHTML=`<table><tr><th>Session</th><th>Task</th><th>Status</th><th>Started</th></tr>${DATA.sessions.slice(-5).reverse().map(s=>`<tr><td>${s.name}</td><td>${s.task}</td><td><span class="session-status status-${s.status}">${s.status}</span></td><td>${s.started}</td></tr>`).join('')}</table>`;
  } else {
    document.getElementById('sessionTable').innerHTML='<div style="color:var(--text-dim);font-size:13px;padding:8px">No sessions yet.</div>';
  }
}

async function loadData() {
  try {
    const resp = await fetch('data.json?t=' + Date.now());
    if (!resp.ok) throw new Error('fetch failed');
    const data = await resp.json();
    lastData = data;
    render(data);
    const el = document.getElementById('autoRefresh');
    el.textContent = 'Auto-refresh: ' + new Date().toLocaleTimeString() + ' (every 30s)';
    el.className = 'auto-refresh';
  } catch(e) {
    // fetch 실패 시 (file:// 프로토콜) — 인라인 데이터 fallback
    const el = document.getElementById('autoRefresh');
    if (!lastData) {
      el.textContent = 'Auto-refresh unavailable (file:// mode). Run: forge dashboard refresh, then reload.';
      el.className = 'auto-refresh stale';
    }
  }
}

// 초기 로드 + 주기적 갱신
loadData();
setInterval(loadData, REFRESH_INTERVAL);
</script>
</body>
</html>
HTMLEOF

  echo "[dashboard] 대시보드 생성: ${DASHBOARD_HTML}"
  echo ""
  echo "  사용법:"
  echo "    1. 브라우저에서 열기: ${DASHBOARD_HTML}"
  echo "    2. 데이터 갱신:     forge dashboard refresh"
  echo "    3. 브라우저 열어두면 30초마다 자동 갱신"
  echo ""
  echo "  팁: Stop Hook으로 자동 갱신이 설정되어 있습니다."
  echo "       forge build 완료 시 data.json이 자동 갱신됩니다."
}

# 로컬 HTTP 서버 시작 (auto-refresh가 동작하려면 필요)
# dashboard_web_serve [port]
dashboard_web_serve() {
  local port="${1:-9470}"

  if [ ! -f "$DASHBOARD_HTML" ]; then
    dashboard_web_generate
  else
    dashboard_web_refresh
  fi

  # 기존 서버 프로세스 확인
  local pid_file="${DASHBOARD_DIR}/.server.pid"
  if [ -f "$pid_file" ]; then
    local old_pid=$(cat "$pid_file" | tr -d '\r\n')
    if kill -0 "$old_pid" 2>/dev/null; then
      echo "[dashboard] 서버 이미 실행 중 (PID: ${old_pid}, port: ${port})"
      echo "  http://localhost:${port}"
      return 0
    fi
  fi

  # Python 사용 가능 확인
  local python_cmd=""
  if command -v python3 >/dev/null 2>&1; then
    python_cmd="python3"
  elif command -v python >/dev/null 2>&1; then
    python_cmd="python"
  else
    echo "[dashboard] ERROR: Python이 없습니다. 수동으로 HTTP 서버를 시작하세요:"
    echo "  cd ${DASHBOARD_DIR} && python -m http.server ${port}"
    return 1
  fi

  # 백그라운드로 서버 시작
  cd "$DASHBOARD_DIR"
  $python_cmd -m http.server "$port" >/dev/null 2>&1 &
  local server_pid=$!
  echo "$server_pid" > "$pid_file"
  cd - >/dev/null

  echo "[dashboard] 로컬 서버 시작 (PID: ${server_pid}, port: ${port})"
  echo ""
  echo "  http://localhost:${port}"
  echo ""
  echo "  - 30초마다 자동 새로고침"
  echo "  - forge build 완료 시 자동 데이터 갱신 (Stop Hook)"
  echo "  - 서버 종료: forge dashboard stop"

  # 브라우저 자동 열기
  if command -v start >/dev/null 2>&1; then
    start "" "http://localhost:${port}" 2>/dev/null
  elif command -v open >/dev/null 2>&1; then
    open "http://localhost:${port}" 2>/dev/null
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "http://localhost:${port}" 2>/dev/null
  fi
}

# 서버 종료
dashboard_web_stop() {
  local pid_file="${DASHBOARD_DIR}/.server.pid"
  if [ -f "$pid_file" ]; then
    local pid=$(cat "$pid_file" | tr -d '\r\n')
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      echo "[dashboard] 서버 종료 (PID: ${pid})"
    else
      echo "[dashboard] 서버가 이미 종료됨"
    fi
    rm -f "$pid_file"
  else
    echo "[dashboard] 실행 중인 서버 없음"
  fi
}
