# .golem/

GolemGarden 프로젝트별 런타임 데이터 디렉토리.

```
.golem/
├── forge-board.md      ← 이 프로젝트의 팀 구성
├── souls/              ← 프로젝트별 SOUL 컨텍스트 오버라이드
│   └── ryn.md          (글로벌 ryn.md의 프로젝트 특화 버전)
└── growth-log/         ← 이 프로젝트에서의 성장 기록
    ├── ryn.jsonl
    └── kai.jsonl
```

## 경로 우선순위

- SOUL: `.golem/souls/` > `~/.claude/golem-garden/souls/` (프로젝트 오버라이드 우선)
- Growth Log: `.golem/growth-log/` (프로젝트별 독립)
- Forge Board: `.golem/forge-board.md` (프로젝트별 독립)

## .gitignore

`.golem/`은 `.gitignore`에 넣어도 되고 커밋해도 됩니다.
- 커밋하면: 팀원과 팀 구성 공유 가능
- .gitignore에 넣으면: 로컬에서만 사용
