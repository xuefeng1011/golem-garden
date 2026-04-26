# GolemGarden Web UI — 작업 플랜

## 왜 만드는가

GolemGarden이 CLI에서만 동작해서:
- 여러 세션 병렬 관리 불가 (터미널 창 N개 왔다갔다)
- SOUL 전환이 수동
- 툴 호출/파일 수정 진행 상황 한눈에 보기 어려움

**해결**: 얇은 웹 UI + Gateway로 브라우저 탭 = 세션 병렬 관리.

## 프로젝트 위치

```
C:\01_xuefeng\08_ai\golem-garden
```

## 아키텍처

```
브라우저 (탭 N개 = 독립 세션 + 선택된 SOUL)
        │ REST + SSE
        ▼
FastAPI Gateway (127.0.0.1:8642)
        │ subprocess
        ▼
Claude Code CLI (세션별 1개, stream-json 출력)
```

- UI: Hermes Web UI 포크 (Vue3 + Naive UI)
- Gateway: FastAPI 자작
- 모두 Windows 네이티브

## 실행 환경

- Windows 10/11 네이티브 (WSL 아님)
- 터미널: PowerShell 7 (`pwsh`)
- Claude Code: 기설치 (`claude` 명령 사용 가능)
- Python 3.11+, uv로 관리
- Node.js 18+ (Hermes UI 빌드용)

## 코드 작성 규칙

- 경로는 `pathlib.Path`, 문자열 하드코딩 금지
- subprocess 호출 시 `encoding="utf-8"`, `errors="replace"` 명시
- Claude Code 실행파일은 `shutil.which("claude")`로 해결 (Windows에선 `claude.cmd`일 수 있음)
- 바인딩은 `127.0.0.1`만 (방화벽 팝업 회피)
- `.gitattributes`: `* text=auto eol=lf` (CRLF 이슈 방지)

## 원칙

1. Gateway는 얇게 — Claude Code가 주인공
2. SOUL.md는 파일 그대로, DB에 안 넣음
3. MVP는 로컬 1인용 (인증/배포 없음)
4. Hermes UI 수정은 5개 파일 이내
5. 브랜치 격리: `feature/web-ui`에서만

## 폴더 구조

```
golem-garden/
├── souls/                       # 글로벌 SOUL 원본
├── .golem/souls/                # 프로젝트 오버라이드 (우선)
├── CLAUDE.md
├── docs/
│   └── WEB_UI_PLAN.md
└── web/
    ├── gateway/
    │   └── src/golem_gateway/
    └── ui/
```

> 참고: 상위 플랜 초안은 `.souls/*.md`로 적혀 있었으나, 이 프로젝트의 실제 경로 규약은
> `souls/` (글로벌) + `.golem/souls/` (프로젝트 오버라이드). Gateway는 후자를 우선 스캔.

## Phase 1: Gateway 스켈레톤 (반나절)

**목표**: 서버 뜨고 SOUL 목록 API 동작.

- `web/gateway/` FastAPI 프로젝트 (uv)
- 포트 `127.0.0.1:8642`
- CORS: `http://localhost:5173`, `http://localhost:8648`
- 엔드포인트:
  - `GET /health`
  - `GET /v1/souls` — `.golem/souls/*.md` + `souls/*.md` 스캔, frontmatter 파싱(없어도 OK)
  - `GET /v1/souls/{id}` — 본문 포함
- 모델: `id, name, rank, specialty, description, content`
- `python-frontmatter` 사용

**완료 기준**: `curl.exe http://127.0.0.1:8642/v1/souls` → JSON 목록.

## Phase 2: Claude Code 브리지 + SSE (하루)

**이 단계가 심장.**

**선행**: stream-json 실제 포맷 샘플링

```powershell
claude --print --output-format stream-json "hello" > sample.jsonl
```

이 파일 뜯어본 뒤 파서 설계.

- `POST /v1/runs` — body `{input, session_id, soul_id}`
  - subprocess: `claude --print --output-format stream-json --append-system-prompt <SOUL내용> <input>`
  - `shutil.which("claude")` 로 경로 해결
  - `run_id` 즉시 반환 (비동기)
- `GET /v1/runs/{run_id}/events` — SSE (`sse-starlette`)
  - stream-json → Hermes 호환 이벤트 변환
    - assistant delta → `message.delta`
    - tool_use → `tool.started`
    - tool_result → `tool.completed`
    - 프로세스 종료 → `run.completed`
- 세션 매니저: 메모리 dict `{session_id: ClaudeCodeSession}`

**완료 기준**: `curl.exe -X POST /v1/runs` 후 `/v1/runs/{id}/events` 스트리밍 확인.

## Phase 3: Hermes UI 포크 + 연결 (하루)

**목표**: 브라우저에서 SOUL 골라 대화, 세션 탭 여러 개.

- `web/ui/`에 Hermes UI 클론 (`https://github.com/EKKOLearnAI/hermes-web-ui`)
- `npm install && npm run dev` 기동 확인
- 수정 5개 파일:
  - `src/api/client.ts` — baseURL `http://127.0.0.1:8642`
  - `src/api/souls.ts` — 신규, `GET /v1/souls`
  - `src/stores/chat.ts` — 세션에 `soulId` 추가
  - `src/components/chat/ChatPanel.vue` — SOUL 드롭다운
  - `src/components/layout/AppSidebar.vue` — SOUL 뱃지
- Scheduled Jobs는 라우터에서 숨김 (삭제 X)

**완료 기준**: 탭 2개로 서로 다른 SOUL과 동시 대화.

## Phase 4 이후 (MVP 검증 후)

1. SOUL frontmatter `rank` 색상 뱃지 (Novice→Master)
2. Circuit breaker (토큰/시간 초과 중단)
3. Cross-agent review
4. SOUL 생성기 (UI에서 새 SOUL.md 만들기)
5. SQLite 세션 히스토리 영속화

## 리스크

| 리스크 | 대응 |
|---|---|
| stream-json 스펙 불안정 | Phase 2 시작 전 샘플 먼저 |
| `--resume` 세션 이어가기 동작 불명 | MVP는 단발 호출만, Phase 4로 미룸 |
| Hermes 업스트림 변경 | 수정 파일 5개 제한, 커스텀은 신규 파일 |
| Windows subprocess 경로 | `shutil.which`로 해결, 한글 깨지면 UTF-8 강제 |
| 동시 실행 시 토큰 한도 | Max 구독 기준 병렬 3~5개 OK, 초과 시 큐잉 |

## 안 할 것

- 멀티유저, 인증, 회원가입
- Docker, HTTPS, 배포
- Scheduled Jobs (Hermes 기능 숨김만)
- 모바일 반응형, 다국어

## 시작 명령 (PowerShell)

```powershell
# 프로젝트 이동 + 브랜치
cd C:\01_xuefeng\08_ai\golem-garden
git checkout -b feature/web-ui

# 디렉토리
mkdir web, docs

# uv 설치 (없으면: pip install uv 도 가능)
winget install --id=astral-sh.uv -e

# Claude Code 실행
claude
```
