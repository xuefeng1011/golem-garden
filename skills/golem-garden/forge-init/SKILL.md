---
name: forge-init
description: GolemGarden 프로젝트 초기화. 팀 구성과 SOUL 자동 생성.
trigger: forge-init, forge init
---

# forge-init — 프로젝트 초기화 실행 스킬

사용자가 `forge-init: {설명}` 형태로 입력하면 이 스킬이 실행된다.

## 실행 절차

### Step 1: 프로젝트 분석

사용자 입력에서 다음을 추출한다:
- **프로젝트 유형**: 웹앱, API, 풀스택, 게임, 데이터 분석 등
- **기술스택**: 언어, 프레임워크, DB
- **추가 요구사항**: 특별한 역할이나 도구

예시: `forge-init: 풀스택 웹앱, Spring Boot + React`
→ 유형=풀스택, BE=Spring Boot, FE=React

### Step 2: 도메인 팩 매칭 또는 개별 SOUL 구성

프로젝트 유형에 따라 결정:

| 유형 | 추천 |
|------|------|
| 풀스택 웹앱 | `bash forge.sh pack install fullstack` 실행 |
| 게임 개발 | `bash forge.sh pack install gamedev` 실행 |
| 주식/데이터 분석 | `bash forge.sh pack install trading` 실행 |
| 그 외 | 개별 SOUL 생성 (아래 참고) |

도메인 팩이 없는 경우 필요한 역할을 판단하여 개별 생성:
```bash
bash forge.sh soul-create backend-developer
bash forge.sh soul-create frontend-developer
bash forge.sh soul-create qa-tester
```

### Step 3: SOUL 컨텍스트 커스터마이징

생성된 각 SOUL 파일(`souls/{name}.md`)을 Read로 읽고,
사용자가 입력한 기술스택에 맞게 Edit으로 `프로젝트 컨텍스트` 섹션을 업데이트한다:

```markdown
## 프로젝트 컨텍스트 (프롬프트에 주입됨)
- 기술스택: {사용자가 지정한 스택}
- 아키텍처: {분석한 아키텍처 패턴}
- 우선순위: {판단한 우선순위}
```

### Step 4: forge-board.md 생성

프로젝트 루트에 `forge-board.md`를 생성한다.
`templates/forge-board.md`를 Read로 읽고 플레이스홀더를 채워서 Write한다.

### Step 5: 결과 보고

`bash forge.sh status` 실행하여 최종 팀 구성을 사용자에게 보여준다.

## 예시 실행 흐름

```
사용자: forge-init: 풀스택 웹앱, Spring Boot + React

AI 실행:
1. bash forge.sh pack install fullstack
   → Nex(기존), Ryn(기존), Kai(신규), Zen(신규), Bolt(신규)
2. souls/ryn.md Edit → 기술스택: Spring Boot 3.x, MariaDB 반영
3. souls/kai.md Edit → 기술스택: React 18, TypeScript, Tailwind 반영
4. forge-board.md Write → 팀 구성 완료
5. bash forge.sh status → 결과 출력

응답: "풀스택 팀 구성 완료! Nex(Director), Ryn(Backend), Kai(Frontend), Zen(QA), Bolt(DevOps)"
```
