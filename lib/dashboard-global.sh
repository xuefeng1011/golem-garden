#!/bin/bash
# dashboard-global.sh — 글로벌 대시보드 (전체 프로젝트 통합 현황)
# 프로젝트별 대시보드와 별개로, GOLEM_ROOT(~/.claude/golem-garden/) 기준 전체 현황
# Usage:
#   forge dashboard global        — 글로벌 HTML + 데이터 생성
#   forge dashboard global-refresh — 글로벌 데이터만 갱신
#   forge dashboard global-serve  — 글로벌 서버 시작 (port 9471)

GOLEM_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${GOLEM_ROOT}/lib/soul-parser.sh"
source "${GOLEM_ROOT}/lib/growth-log.sh"
source "${GOLEM_ROOT}/lib/rank-system.sh"

# 글로벌 대시보드 경로
GLOBAL_DASHBOARD_DIR="${GOLEM_ROOT}/dashboard"
GLOBAL_DASHBOARD_HTML="${GLOBAL_DASHBOARD_DIR}/index.html"
GLOBAL_DASHBOARD_DATA="${GLOBAL_DASHBOARD_DIR}/data.json"

# ─────────────────────────────────────────────────────────
# 프로젝트 검색: .golem/ 디렉토리를 가진 프로젝트 탐색
# ─────────────────────────────────────────────────────────

# 알려진 프로젝트 목록 파일
PROJECTS_FILE="${GOLEM_ROOT}/projects.jsonl"

# 프로젝트 등록
# dashboard_global_register [project_path]
dashboard_global_register() {
  local project_path="${1:-${GOLEM_PROJECT:-$(pwd)}}"
  project_path=$(cd "$project_path" 2>/dev/null && pwd || echo "$project_path")

  # .golem/ 있는지 확인
  if [ ! -d "${project_path}/.golem" ]; then
    echo "[global-dashboard] ${project_path}: .golem/ 없음 — GolemGarden 프로젝트가 아닙니다"
    return 1
  fi

  # GOLEM_ROOT 자체는 프로젝트로 등록 금지
  # Windows(MSYS2) 경로 정규화: /c/Users/... vs C:/Users/... 차이 대응
  local resolved_root
  resolved_root=$(cd "$GOLEM_ROOT" 2>/dev/null && pwd || echo "$GOLEM_ROOT")
  local norm_path=$(echo "$project_path" | sed 's|^/\([a-zA-Z]\)/|\1:/|')
  local norm_root=$(echo "$resolved_root" | sed 's|^/\([a-zA-Z]\)/|\1:/|')
  if [ "$project_path" = "$resolved_root" ] || [ "$norm_path" = "$norm_root" ]; then
    return 0
  fi

  # 중복 체크
  if [ -f "$PROJECTS_FILE" ] && grep -q "\"path\":\"${project_path}\"" "$PROJECTS_FILE" 2>/dev/null; then
    echo "[global-dashboard] ${project_path}: 이미 등록됨"
    return 0
  fi

  local name=$(basename "$project_path")
  local date=$(date +%Y-%m-%d)
  echo "{\"name\":\"${name}\",\"path\":\"${project_path}\",\"registered\":\"${date}\"}" >> "$PROJECTS_FILE"
  echo "[global-dashboard] 프로젝트 등록: ${name} (${project_path})"
}

# 등록된 프로젝트 목록
_global_project_list() {
  if [ ! -f "$PROJECTS_FILE" ]; then
    echo ""
    return
  fi
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local path=$(echo "$line" | grep -o '"path":"[^"]*"' | sed 's/"path":"//;s/"//')
    # 경로가 여전히 유효한지
    [ -d "${path}/.golem" ] && echo "$path"
  done < "$PROJECTS_FILE"
}

# ─────────────────────────────────────────────────────────
# 글로벌 데이터 수집
# ─────────────────────────────────────────────────────────

# SOUL 종합 데이터 (글로벌 growth-log 기준 + 프로젝트별 집계)
_global_collect_souls() {
  local first=true
  echo "["

  # 글로벌 SOUL 기준
  local global_growth="${GOLEM_ROOT}/growth-log"
  for soul_file in "${GOLEM_ROOT}/souls/"*.md; do
    [ -f "$soul_file" ] || continue

    # 글로벌 환경에서 파싱
    local saved_dir="$GOLEM_DIR"
    GOLEM_DIR="$GOLEM_ROOT"
    GROWTH_DIR="$global_growth"
    soul_parse "$soul_file"

    local g_tasks=$(growth_log_task_count "$SOUL_NAME")
    local g_rate=$(growth_log_success_rate "$SOUL_NAME")
    local g_streak=$(growth_log_streak "$SOUL_NAME")
    local g_cost=$(_growth_log_total_cost "$SOUL_NAME" 2>/dev/null || echo "0.000")

    # 프로젝트별 태스크 수 집계
    local project_stats=""
    local total_project_tasks=0
    local total_project_cost="0.000"
    local project_count=0

    while IFS= read -r proj_path; do
      [ -z "$proj_path" ] && continue
      local proj_name=$(basename "$proj_path")
      local proj_growth="${proj_path}/.golem/growth-log"
      local proj_log="${proj_growth}/${SOUL_NAME}.jsonl"

      if [ -f "$proj_log" ]; then
        GROWTH_DIR="$proj_growth"
        local p_tasks=$(growth_log_task_count "$SOUL_NAME")
        local p_cost=$(_growth_log_total_cost "$SOUL_NAME" 2>/dev/null || echo "0.000")

        # forge-init만 있어도 프로젝트에 등록된 SOUL이면 포함 (태스크 0이어도)
        local p_total_lines=$(grep -c "" "$proj_log" 2>/dev/null || echo 0)
        if [ "$p_tasks" -gt 0 ] 2>/dev/null || [ "$p_total_lines" -gt 0 ] 2>/dev/null; then
          project_count=$((project_count + 1))
          total_project_tasks=$((total_project_tasks + p_tasks))
          total_project_cost=$(echo "$total_project_cost $p_cost" | awk '{printf "%.3f", $1+$2}')
          project_stats="${project_stats}{\"name\":\"${proj_name}\",\"tasks\":${p_tasks},\"cost\":\"${p_cost}\"},"
        fi
      fi
    done < <(_global_project_list)

    # 프로젝트 stats JSON 정리
    project_stats=$(echo "[$project_stats]" | sed 's/,]/]/')

    # 업적 (글로벌)
    local ach_count=0
    local ach_file="${GOLEM_ROOT}/achievements.jsonl"
    [ -f "$ach_file" ] && ach_count=$(grep -c "\"soul\":\"${SOUL_NAME}\"" "$ach_file" 2>/dev/null | tr -d ' \r')
    # 프로젝트별 업적도 합산
    while IFS= read -r proj_path; do
      [ -z "$proj_path" ] && continue
      local proj_ach="${proj_path}/.golem/achievements.jsonl"
      if [ -f "$proj_ach" ]; then
        local pa=$(grep -c "\"soul\":\"${SOUL_NAME}\"" "$proj_ach" 2>/dev/null | tr -d ' \r')
        ach_count=$((ach_count + pa))
      fi
    done < <(_global_project_list)

    # 전문화
    local spec=""
    local st_file="${GOLEM_ROOT}/skill-trees.jsonl"
    [ -f "$st_file" ] && spec=$(grep "\"soul\":\"${SOUL_NAME}\"" "$st_file" 2>/dev/null | tail -1 | grep -o '"branch":"[^"]*"' | sed 's/"branch":"//;s/"//')

    # 랭크 진행률
    local all_tasks=$((g_tasks + total_project_tasks))
    local next_rank="" progress=0
    case "$SOUL_RANK" in
      novice) next_rank="junior"; [ "$all_tasks" -gt 0 ] && progress=$((all_tasks * 100 / 10)); [ $progress -gt 100 ] && progress=100 ;;
      junior) next_rank="senior"; [ "$all_tasks" -gt 0 ] && progress=$((all_tasks * 100 / 50)); [ $progress -gt 100 ] && progress=100 ;;
      senior) next_rank="lead"; [ "$all_tasks" -gt 0 ] && progress=$((all_tasks * 100 / 100)); [ $progress -gt 100 ] && progress=100 ;;
      lead)   next_rank="master"; [ "$all_tasks" -gt 0 ] && progress=$((all_tasks * 100 / 200)); [ $progress -gt 100 ] && progress=100 ;;
      master) next_rank="max"; progress=100 ;;
    esac

    local all_cost=$(echo "$g_cost $total_project_cost" | awk '{printf "%.3f", $1+$2}')

    # GOLEM_DIR 복원
    GOLEM_DIR="$saved_dir"
    GROWTH_DIR="${GOLEM_DIR:-${GOLEM_ROOT}/.golem}/growth-log"

    [ "$first" = true ] && first=false || echo ","
    echo "  {\"name\":\"${SOUL_NAME}\",\"role\":\"${SOUL_ROLE}\",\"rank\":\"${SOUL_RANK}\",\"model\":\"${SOUL_MODEL}\",\"globalTasks\":${g_tasks},\"projectTasks\":${total_project_tasks},\"totalTasks\":${all_tasks},\"rate\":${g_rate},\"streak\":${g_streak},\"globalCost\":\"${g_cost}\",\"projectCost\":\"${total_project_cost}\",\"totalCost\":\"${all_cost}\",\"achievements\":${ach_count},\"spec\":\"${spec}\",\"projects\":${project_count},\"projectStats\":${project_stats},\"nextRank\":\"${next_rank}\",\"progress\":${progress}}"
  done

  echo "]"
}

# 프로젝트 목록 데이터
_global_collect_projects() {
  echo "["
  local first=true

  while IFS= read -r proj_path; do
    [ -z "$proj_path" ] && continue
    local proj_name=$(basename "$proj_path")

    # 프로젝트별 SOUL 수
    local soul_count=0
    if [ -d "${proj_path}/.golem/souls" ]; then
      soul_count=$(ls "${proj_path}/.golem/souls/"*.md 2>/dev/null | wc -l | tr -d ' \r')
    fi

    # 프로젝트별 총 비용
    local proj_cost="0.000"
    if [ -d "${proj_path}/.golem/growth-log" ]; then
      for lf in "${proj_path}/.golem/growth-log/"*.jsonl; do
        [ -f "$lf" ] || continue
        local c=$(grep -o '"cost_usd":[0-9.]*' "$lf" 2>/dev/null | cut -d: -f2 | awk '{s+=$1} END {printf "%.3f", s+0}')
        proj_cost=$(echo "$proj_cost $c" | awk '{printf "%.3f", $1+$2}')
      done
    fi

    # 세션 수
    local sess_count=0
    [ -d "${proj_path}/.golem/sessions" ] && sess_count=$(ls "${proj_path}/.golem/sessions/"*.meta 2>/dev/null | wc -l | tr -d ' \r')

    # DNA
    local dna_fws=""
    local dna_file="${proj_path}/.golem/project-dna.json"
    [ -f "$dna_file" ] && dna_fws=$(grep -o '"frameworks":"[^"]*"' "$dna_file" | sed 's/"frameworks":"//;s/"//')

    # 등록일
    local reg_date=""
    [ -f "$PROJECTS_FILE" ] && reg_date=$(grep "\"path\":\"${proj_path}\"" "$PROJECTS_FILE" | head -1 | grep -o '"registered":"[^"]*"' | sed 's/"registered":"//;s/"//')

    [ "$first" = true ] && first=false || echo ","
    echo "  {\"name\":\"${proj_name}\",\"path\":\"${proj_path}\",\"souls\":${soul_count},\"cost\":\"${proj_cost}\",\"sessions\":${sess_count},\"frameworks\":\"${dna_fws}\",\"registered\":\"${reg_date}\"}"
  done < <(_global_project_list)

  echo "]"
}

# ─────────────────────────────────────────────────────────
# 글로벌 데이터 JSON 생성
# ─────────────────────────────────────────────────────────

dashboard_global_refresh() {
  mkdir -p "$GLOBAL_DASHBOARD_DIR"

  local generated=$(date +"%Y-%m-%d %H:%M:%S")

  # 프로젝트 자동 등록은 Stop hook(auto-dashboard-refresh.sh)에서 처리
  # refresh는 데이터 갱신만 수행

  local souls_json=$(_global_collect_souls)
  local projects_json=$(_global_collect_projects)

  local project_count=0
  while IFS= read -r p; do [ -n "$p" ] && project_count=$((project_count+1)); done < <(_global_project_list)
  local soul_count=$(ls "${GOLEM_ROOT}/souls/"*.md 2>/dev/null | wc -l | tr -d ' \r')

  cat > "$GLOBAL_DASHBOARD_DATA" <<DATAEOF
{
  "type": "global",
  "generated": "${generated}",
  "soulCount": ${soul_count},
  "projectCount": ${project_count},
  "souls": ${souls_json},
  "projects": ${projects_json}
}
DATAEOF

  echo "[global-dashboard] 데이터 갱신: ${GLOBAL_DASHBOARD_DATA} (${generated})"
}

# ─────────────────────────────────────────────────────────
# 글로벌 HTML 생성
# ─────────────────────────────────────────────────────────

dashboard_global_generate() {
  mkdir -p "$GLOBAL_DASHBOARD_DIR"
  dashboard_global_refresh

  if [ -f "$GLOBAL_DASHBOARD_HTML" ]; then
    echo "[global-dashboard] HTML 이미 존재 — 데이터만 갱신됨"
    return
  fi

  cat > "$GLOBAL_DASHBOARD_HTML" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>GolemGarden — Global Dashboard</title>
<style>
:root{--bg:#0d1117;--card:#161b22;--border:#30363d;--text:#c9d1d9;--text-dim:#8b949e;--accent:#58a6ff;--green:#3fb950;--yellow:#d29922;--red:#f85149;--purple:#bc8cff;--orange:#d18616}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,'Segoe UI',monospace;background:var(--bg);color:var(--text);padding:20px;max-width:1400px;margin:0 auto}
.header{text-align:center;padding:20px 0 30px;border-bottom:1px solid var(--border);margin-bottom:30px}
.header h1{font-size:28px;color:var(--accent);margin-bottom:4px}
.header .sub{color:var(--text-dim);font-size:14px}
.header .badge{display:inline-block;background:var(--purple);color:#fff;font-size:11px;padding:2px 8px;border-radius:8px;margin-left:8px;vertical-align:middle}
.refresh-info{font-size:11px;color:var(--text-dim);margin-top:10px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:16px;margin-bottom:24px}
.card{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:16px}
.card h2{font-size:14px;color:var(--text-dim);text-transform:uppercase;letter-spacing:1px;margin-bottom:12px;border-bottom:1px solid var(--border);padding-bottom:8px}
.summary-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(130px,1fr));gap:12px}
.summary-item{text-align:center;padding:12px;background:var(--bg);border-radius:6px;border:1px solid var(--border)}
.summary-item .num{font-size:24px;font-weight:bold;color:var(--accent)}
.summary-item .label{font-size:11px;color:var(--text-dim);margin-top:4px}
.soul-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:8px}
.soul-name{font-size:18px;font-weight:bold;color:var(--accent)}
.soul-rank{font-size:12px;padding:2px 8px;border-radius:10px;font-weight:bold}
.rank-novice{background:#1f2d1f;color:var(--green);border:1px solid var(--green)}
.rank-junior{background:#2d2b1f;color:var(--yellow);border:1px solid var(--yellow)}
.rank-senior{background:#2d1f2d;color:var(--purple);border:1px solid var(--purple)}
.rank-lead{background:#2d1f1f;color:var(--orange);border:1px solid var(--orange)}
.rank-master{background:#1f1f2d;color:var(--red);border:1px solid var(--red)}
.soul-role{color:var(--text-dim);font-size:13px}
.soul-stats{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin:10px 0}
.stat{text-align:center}.stat-value{font-size:16px;font-weight:bold}.stat-label{font-size:10px;color:var(--text-dim);text-transform:uppercase}
.progress-bar{height:6px;background:var(--border);border-radius:3px;overflow:hidden;margin-top:8px}
.progress-fill{height:100%;border-radius:3px;transition:width 0.5s}
.progress-label{font-size:11px;color:var(--text-dim);margin-top:4px;text-align:right}
.project-breakdown{font-size:12px;color:var(--text-dim);margin-top:6px;padding-top:6px;border-top:1px solid var(--border)}
.project-breakdown span{display:inline-block;background:var(--bg);padding:1px 6px;border-radius:4px;margin:2px;border:1px solid var(--border)}
.tags{display:flex;flex-wrap:wrap;gap:4px;margin-top:6px}
.tag{font-size:11px;padding:1px 6px;border-radius:4px;background:var(--bg);border:1px solid var(--border);color:var(--text-dim)}
.tag.spec{border-color:var(--purple);color:var(--purple)}
.tag.ach{border-color:var(--yellow);color:var(--yellow)}
table{width:100%;border-collapse:collapse;font-size:13px}
th{text-align:left;color:var(--text-dim);font-weight:normal;padding:6px 8px;border-bottom:1px solid var(--border)}
td{padding:6px 8px;border-bottom:1px solid #21262d}
.footer{text-align:center;padding:20px;color:var(--text-dim);font-size:12px;border-top:1px solid var(--border);margin-top:30px}
</style>
</head>
<body>
<div class="header">
  <h1>GolemGarden<span class="badge">GLOBAL</span></h1>
  <div class="sub">All Projects &middot; All SOULs &middot; Total Overview</div>
  <div class="refresh-info" id="refreshInfo">Loading...</div>
</div>
<div class="card" style="margin-bottom:24px"><h2>Global Overview</h2><div class="summary-grid" id="summaryGrid"></div></div>
<div class="card" style="margin-bottom:24px"><h2>Projects</h2><div id="projectTable"></div></div>
<div class="grid" id="soulGrid"></div>
<div class="footer">GolemGarden Global Dashboard &middot; <span id="genTime"></span></div>

<script>
const REFRESH_INTERVAL = 30000;

function render(D) {
  document.getElementById('genTime').textContent = 'Data: ' + D.generated;
  document.getElementById('refreshInfo').textContent = 'Auto-refresh: ' + new Date().toLocaleTimeString() + ' (every 30s)';

  const totalTasks=D.souls.reduce((a,s)=>a+s.totalTasks,0);
  const totalCost=D.souls.reduce((a,s)=>a+parseFloat(s.totalCost),0).toFixed(3);
  const avgRate=D.souls.length?Math.round(D.souls.reduce((a,s)=>a+s.rate,0)/D.souls.length):0;
  const totalAch=D.souls.reduce((a,s)=>a+s.achievements,0);

  document.getElementById('summaryGrid').innerHTML=`
    <div class="summary-item"><div class="num">${D.projectCount}</div><div class="label">Projects</div></div>
    <div class="summary-item"><div class="num">${D.soulCount}</div><div class="label">SOULs</div></div>
    <div class="summary-item"><div class="num">${totalTasks}</div><div class="label">Total Tasks</div></div>
    <div class="summary-item"><div class="num">${avgRate}%</div><div class="label">Avg Success</div></div>
    <div class="summary-item"><div class="num">$${totalCost}</div><div class="label">Total Cost</div></div>
    <div class="summary-item"><div class="num">${totalAch}</div><div class="label">Achievements</div></div>`;

  // Projects table
  if(D.projects.length>0){
    document.getElementById('projectTable').innerHTML=`<table>
      <tr><th>Project</th><th>SOULs</th><th>Sessions</th><th>Cost</th><th>Frameworks</th><th>Registered</th></tr>
      ${D.projects.map(p=>`<tr><td style="color:var(--accent)">${p.name}</td><td>${p.souls}</td><td>${p.sessions}</td><td>$${p.cost}</td><td>${p.frameworks||'—'}</td><td>${p.registered||'—'}</td></tr>`).join('')}
    </table>`;
  } else {
    document.getElementById('projectTable').innerHTML='<div style="color:var(--text-dim);font-size:13px;padding:8px">No projects registered. Run forge dashboard global in a project.</div>';
  }

  // Soul cards (global view)
  document.getElementById('soulGrid').innerHTML=D.souls.map(s=>{
    const pc=s.progress>=80?'var(--green)':s.progress>=50?'var(--yellow)':'var(--accent)';
    const tags=[];
    if(s.spec)tags.push(`<span class="tag spec">${s.spec}</span>`);
    if(s.achievements>0)tags.push(`<span class="tag ach">${s.achievements} badges</span>`);
    // Project breakdown
    let projBreak='';
    if(s.projectStats&&s.projectStats.length>0){
      projBreak='<div class="project-breakdown">'+s.projectStats.map(p=>`<span>${p.name}: ${p.tasks}t/$${p.cost}</span>`).join('')+'</div>';
    }
    return`<div class="card">
      <div class="soul-header"><span class="soul-name">${s.name}</span><span class="soul-rank rank-${s.rank}">${s.rank.toUpperCase()}</span></div>
      <div class="soul-role">${s.role} &middot; ${s.projects} projects</div>
      <div class="soul-stats">
        <div class="stat"><div class="stat-value">${s.totalTasks}</div><div class="stat-label">Total Tasks</div></div>
        <div class="stat"><div class="stat-value">${s.rate}%</div><div class="stat-label">Success</div></div>
        <div class="stat"><div class="stat-value">$${s.totalCost}</div><div class="stat-label">Total Cost</div></div>
      </div>
      <div class="progress-bar"><div class="progress-fill" style="width:${s.progress}%;background:${pc}"></div></div>
      <div class="progress-label">${s.rank==='master'?'MAX':s.progress+'% -> '+s.nextRank}</div>
      ${tags.length?'<div class="tags">'+tags.join('')+'</div>':''}
      ${projBreak}
    </div>`;
  }).join('');
}

async function loadData(){
  try{
    const r=await fetch('data.json?t='+Date.now());
    if(!r.ok)throw new Error();
    render(await r.json());
  }catch(e){
    document.getElementById('refreshInfo').textContent='Auto-refresh unavailable (file:// mode). Reload manually.';
  }
}
loadData();
setInterval(loadData,REFRESH_INTERVAL);
</script>
</body>
</html>
HTMLEOF

  echo "[global-dashboard] 글로벌 대시보드 생성: ${GLOBAL_DASHBOARD_HTML}"
  echo ""
  echo "  사용법:"
  echo "    브라우저: ${GLOBAL_DASHBOARD_HTML}"
  echo "    서버:    forge dashboard global-serve"
  echo "    갱신:    forge dashboard global-refresh"
}

# 글로벌 서버
dashboard_global_serve() {
  local port="${1:-9471}"

  if [ ! -f "$GLOBAL_DASHBOARD_HTML" ]; then
    dashboard_global_generate
  else
    dashboard_global_refresh
  fi

  local pid_file="${GLOBAL_DASHBOARD_DIR}/.server.pid"
  if [ -f "$pid_file" ]; then
    local old_pid=$(cat "$pid_file" | tr -d '\r\n')
    if kill -0 "$old_pid" 2>/dev/null; then
      echo "[global-dashboard] 서버 이미 실행 중 (PID: ${old_pid})"
      echo "  http://localhost:${port}"
      return 0
    fi
  fi

  local python_cmd=""
  command -v python3 >/dev/null 2>&1 && python_cmd="python3"
  [ -z "$python_cmd" ] && command -v python >/dev/null 2>&1 && python_cmd="python"
  if [ -z "$python_cmd" ]; then
    echo "[global-dashboard] ERROR: Python 필요. 수동: cd ${GLOBAL_DASHBOARD_DIR} && python -m http.server ${port}"
    return 1
  fi

  cd "$GLOBAL_DASHBOARD_DIR"
  $python_cmd -m http.server "$port" >/dev/null 2>&1 &
  echo "$!" > "$pid_file"
  cd - >/dev/null

  echo "[global-dashboard] 서버 시작 (port: ${port})"
  echo ""
  echo "  http://localhost:${port}"
  echo ""
  echo "  프로젝트별: http://localhost:9470 (forge dashboard serve)"
  echo "  글로벌:     http://localhost:${port}"

  if command -v start >/dev/null 2>&1; then
    start "" "http://localhost:${port}" 2>/dev/null
  elif command -v open >/dev/null 2>&1; then
    open "http://localhost:${port}" 2>/dev/null
  fi
}

dashboard_global_stop() {
  local pid_file="${GLOBAL_DASHBOARD_DIR}/.server.pid"
  if [ -f "$pid_file" ]; then
    local pid=$(cat "$pid_file" | tr -d '\r\n')
    kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null
    rm -f "$pid_file"
    echo "[global-dashboard] 서버 종료"
  else
    echo "[global-dashboard] 실행 중인 서버 없음"
  fi
}

# 프로젝트 목록 조회
dashboard_global_projects() {
  echo "=== GolemGarden Registered Projects ==="
  echo ""
  if [ ! -f "$PROJECTS_FILE" ]; then
    echo "  등록된 프로젝트 없음"
    echo "  프로젝트에서 forge dashboard global 실행 시 자동 등록"
    return
  fi
  printf "%-20s %-50s %s\n" "Name" "Path" "Registered"
  printf "%-20s %-50s %s\n" "----" "----" "----------"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    local name=$(echo "$line" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//')
    local path=$(echo "$line" | grep -o '"path":"[^"]*"' | sed 's/"path":"//;s/"//')
    local reg=$(echo "$line" | grep -o '"registered":"[^"]*"' | sed 's/"registered":"//;s/"//')
    local status="OK"
    [ ! -d "${path}/.golem" ] && status="MISSING"
    printf "%-20s %-50s %s\n" "$name" "$path" "${reg} (${status})"
  done < "$PROJECTS_FILE"
}
