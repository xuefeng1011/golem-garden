# SOUL Spec v1.0

> A portable, open format for defining persistent AI agent personas with measurable growth.

**Status**: Draft v1.0
**Date**: 2026-04-18
**License**: MIT

---

## Overview

A SOUL (Sentient Operational Unit for Labor) is a persistent AI agent persona that carries identity, rank, memory, and growth history across sessions. Unlike stateless agent definitions, SOULs are designed to evolve through measurable experience.

SOUL Spec defines:
1. **Identity** -- who the agent is
2. **Capability** -- what the agent can do (earned, not granted)
3. **Growth** -- how the agent improves over time
4. **Collaboration** -- how agents work together

## File Format

A SOUL is a Markdown file (`{name}.md`) with YAML frontmatter and structured body sections.

```
{name}.md
```

### Frontmatter (YAML)

```yaml
---
name: ryn
role: backend-developer
rank: junior
specialty: [spring-boot, mariadb, rest-api, jpa, clean-architecture]
personality: "..."
model: sonnet
tools: [Read, Edit, Write, Bash, Grep, Glob]
maxTurns: 25
isolation: none
effort: medium
created: 2026-03-30
---
```

### Body (Markdown sections)

```markdown
## Project Context
## Domain Knowledge
## Behavioral Principles
## Growth Summary
```

---

## Frontmatter Fields

### Core Identity

| Field | Required | Type | Description |
|-------|----------|------|-------------|
| `name` | **Yes** | `string` | Unique identifier. 1-32 chars, first letter may be capitalized. Must match filename. |
| `role` | **Yes** | `enum` | Professional role. See [Role Enum](#role-enum). |
| `rank` | **Yes** | `enum` | Current experience level. See [Rank Enum](#rank-enum). |
| `specialty` | **Yes** | `string[]` | Domain expertise keywords. Max 10 items, kebab-case. |
| `personality` | No | `string` | Human-readable description. NOT injected into prompts. For operator reference only. |
| `created` | **Yes** | `date` | ISO 8601 date of SOUL creation (YYYY-MM-DD). |

### Capability

| Field | Required | Type | Default | Description |
|-------|----------|------|---------|-------------|
| `model` | No | `enum` | `sonnet` | Preferred LLM model tier. See [Model Enum](#model-enum). |
| `tools` | No | `string[]` | Rank-derived | Allowed tools. If omitted, derived from `rank`. See [Tool Progression](#tool-progression). |
| `maxTurns` | No | `integer` | Rank-derived | Maximum conversation turns per task. Range: 1-200. |
| `isolation` | No | `enum` | Rank-derived | Execution isolation mode. See [Isolation Enum](#isolation-enum). |
| `effort` | No | `enum` | Model-derived | Reasoning effort level. See [Effort Enum](#effort-enum). |

---

## Enumerations

### Role Enum

Roles define the SOUL's professional function and determine available specialization branches.

| Role | Description | OMC Agent Mapping |
|------|-------------|-------------------|
| `director` | Task orchestrator. Cannot write code. | `architect` |
| `backend-developer` | Server-side logic, APIs, databases | `executor` |
| `frontend-developer` | UI, client-side, responsive design | `designer` |
| `qa-tester` | Testing, quality assurance | `test-engineer` |
| `devops-engineer` | Infrastructure, CI/CD, deployment | `executor` |
| `data-analyst` | Data analysis, ML, visualization | `scientist` |
| `technical-writer` | Documentation, API docs | `writer` |
| `security-auditor` | Security review, vulnerability analysis | `security-reviewer` |
| `knowledge-auditor` | Knowledge quality, deduplication | `executor` |
| `game-logic-developer` | Game mechanics, physics, AI | `executor` |
| `game-designer` | Game design, UX flow, balance | `planner` |

Custom roles are allowed. Unknown roles map to `executor` by default.

### Rank Enum

Ranks represent earned experience levels with progressive capability unlocking.

| Rank | Promotion Threshold | Key Unlock |
|------|---------------------|------------|
| `novice` | -- (starting rank) | Read-only tools, mandatory review |
| `junior` | 10 successful tasks | Write + Bash access |
| `senior` | 50 tasks + 10-streak | Agent delegation, specialization branch |
| `lead` | 100 tasks | SendMessage, delegation authority |
| `master` | 200 tasks | Full tool access, review exempt |

### Model Enum

| Model | Use Case | Cost Tier |
|-------|----------|-----------|
| `haiku` | Quick lookups, simple tasks | Low |
| `sonnet` | Standard development work | Medium |
| `opus` | Deep reasoning, architecture | High |

Implementations MAY extend this enum with provider-specific model identifiers (e.g., `gpt-4o`, `gemini-2.5-pro`).

### Isolation Enum

| Value | Description | Default For |
|-------|-------------|-------------|
| `none` | Shared workspace | novice, junior, director, qa-tester |
| `worktree` | Git worktree isolation | senior, lead, master |

### Effort Enum

| Value | Description | Default For |
|-------|-------------|-------------|
| `low` | Minimal reasoning | haiku |
| `medium` | Balanced | sonnet |
| `high` | Maximum depth | opus |

---

## Tool Progression

When `tools` is omitted, it is derived from `rank`:

| Rank | Default Tools |
|------|---------------|
| `novice` | `Read, Edit, Grep, Glob` |
| `junior` | `Read, Edit, Write, Bash, Grep, Glob` |
| `senior` | `Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch` |
| `lead` | `Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch, SendMessage` |
| `master` | `Read, Edit, Write, Bash, Grep, Glob, Agent, WebFetch, SendMessage, TaskCreate` |

**Director override**: Regardless of rank, `director` role SOULs are restricted to:
`Agent, SendMessage, TaskCreate, TaskStop, Read, Grep, Glob`

Directors MUST NOT have access to: `Edit, Write, Bash, FileEdit, FileWrite, NotebookEdit`

---

## Body Sections

### `## Project Context`

Runtime-injected section describing the current project assignment.

```markdown
## Project Context
- Role: Backend API developer
- Tech Stack: Spring Boot 3, MariaDB, JPA
- Architecture: Clean Architecture (controller → service → repository)
- Priority: > API stability > test coverage > performance
```

### `## Domain Knowledge`

Context hints injected into prompts. Domain-specific expertise the SOUL has accumulated.

```markdown
## Domain Knowledge
- Connection pooling: HikariCP default, tune maximumPoolSize for load
- JPA N+1: Always use @EntityGraph or JOIN FETCH for collections
```

### `## Behavioral Principles`

Guiding rules for the SOUL's decision-making. Injected as system-level instructions.

```markdown
## Behavioral Principles
- Write tests before implementation (TDD)
- Prefer composition over inheritance
- Never expose internal exceptions to API consumers
```

### `## Growth Summary`

Auto-generated section tracking rank progression milestones.

```markdown
## Growth Summary
- 2026-03-30: Created as novice
- 2026-04-08: Promoted to junior (10 tasks, 90% success rate)
```

---

## Runtime Data (External to SOUL file)

The following data is tracked externally in JSONL files, not embedded in the SOUL frontmatter.

### Growth Log (`growth-log/{name}.jsonl`)

One line per completed task:

```json
{
  "date": "2026-04-18",
  "soul": "ryn",
  "task": "Implement user authentication API",
  "result": "success",
  "files_changed": 5,
  "tests_passed": 12,
  "tokens_in": 15000,
  "tokens_out": 3000,
  "tokens_cache": 8000,
  "cost_usd": 0.015,
  "model": "sonnet",
  "duration_ms": 45000,
  "reviewer": "zen",
  "review_result": "pass"
}
```

### Chemistry (`chemistry.jsonl`)

Pairwise collaboration tracking:

```json
{
  "date": "2026-04-18",
  "pair": "ryn:zen",
  "type": "review",
  "result": "positive",
  "detail": "Thorough review caught edge case"
}
```

**Interaction types**: `review`, `collab`, `dependency`, `conflict`
**Results**: `positive`, `negative`, `neutral`

**Chemistry Score**: 0-100 (default 50)
Formula: `50 + (positive - negative) * 50 / total`

**Chemistry Grade**:

| Grade | Score Range |
|-------|-------------|
| S | >= 90 |
| A | >= 75 |
| B | >= 60 |
| C | >= 40 |
| D | >= 20 |
| F | < 20 |

### Achievements (`achievements.jsonl`)

Milestone badges earned once:

```json
{
  "date": "2026-04-18",
  "soul": "ryn",
  "id": "streak_5",
  "name": "Hot Streak",
  "desc": "5 consecutive successes"
}
```

**Achievement Catalog**:

| ID | Name | Condition |
|----|------|-----------|
| `first_blood` | First Blood | tasks >= 1 |
| `streak_5` | Hot Streak | streak >= 5 |
| `streak_10` | Streak Master | streak >= 10 |
| `streak_20` | Untouchable | streak >= 20 |
| `tasks_10` | Getting Started | tasks >= 10 |
| `tasks_50` | Veteran | tasks >= 50 |
| `tasks_100` | Centurion | tasks >= 100 |
| `tasks_200` | Grandmaster | tasks >= 200 |
| `perfect_rate` | Perfectionist | 100% success on 10+ tasks |
| `reviewer_5` | Code Inspector | 5 reviews authored |
| `reviewer_20` | Mentor | 20 reviews authored |
| `reviewed_10` | Reviewed Veteran | 10 reviews received |
| `rank_junior` | Promoted! | Reached junior |
| `rank_senior` | Expert | Reached senior |
| `rank_master` | Grandmaster | Reached master |

### Skill Tree (`skill-trees.jsonl`)

Specialization branch selection (available at senior rank):

```json
{
  "date": "2026-04-18",
  "soul": "ryn",
  "role": "backend-developer",
  "branch": "security",
  "detail": "auth/authz, OWASP, vulnerability scanning"
}
```

**Branches by Role**:

| Role | Branches |
|------|----------|
| `backend-developer` | `performance`, `security`, `architecture` |
| `frontend-developer` | `performance`, `accessibility`, `animation` |
| `devops-engineer` | `reliability`, `security`, `cost` |
| `qa-tester` | `automation`, `performance`, `security` |
| `game-logic-developer` | `physics`, `ai`, `networking` |
| `data-analyst` | `ml`, `visualization`, `pipeline` |
| `director` | `strategy`, `people`, `process` |

### Soul Memory (`memory/{name}.jsonl`)

Episodic learning records per SOUL:

```json
{
  "date": "2026-04-18",
  "task": "JWT authentication",
  "lesson": "Refresh token expiry requires new token issuance flow",
  "tags": "jwt,auth,token",
  "ts": "2026-04-18T14:30:00"
}
```

Top 5 keyword-matched lessons are auto-injected into task prompts.

### Session (`sessions/{id}.meta`, `sessions/{id}.jsonl`)

Session metadata and chronological event log:

```json
// .meta
{
  "task": "Build authentication API",
  "souls": ["ryn", "zen"],
  "status": "completed",
  "started": "2026-04-18T10:00:00",
  "ended": "2026-04-18T11:30:00"
}

// .jsonl (event log)
{"ts": "...", "event": "session_start", "detail": "..."}
{"ts": "...", "event": "soul_assigned", "soul": "ryn", "detail": "..."}
{"ts": "...", "event": "task_complete", "soul": "ryn", "detail": "..."}
{"ts": "...", "event": "session_end", "detail": "..."}
```

### Mailbox (`mailbox/{name}.jsonl`)

Async inter-SOUL communication:

```json
{
  "id": "msg-001",
  "from": "nex",
  "to": "ryn",
  "type": "task_assign",
  "content": "Implement /api/users endpoint",
  "timestamp": "2026-04-18T10:00:00",
  "status": "pending"
}
```

**Message types**: `task_assign`, `task_done`, `review_request`, `shutdown_request`, `budget_warning`, `escalation`
**Status**: `pending`, `read`, `acked`

### Budget (`budget-state.json`)

Session-level cost tracking:

```json
{
  "token_budget": 500000,
  "dollar_budget": 10.00,
  "tokens_used": 125000,
  "dollars_spent": 1.250,
  "turns": 15,
  "stagnant_turns": 0,
  "status": "ok",
  "started": "2026-04-18T10:00:00"
}
```

**Status**: `ok`, `warning` (80%+ used), `exceeded`, `stagnating` (3+ idle turns)

---

## Error Recovery Protocol

Three-stage protocol preventing context pollution from transient errors:

### Stage 1: Withholding (Agent-level)

Auto-recoverable errors are retried internally without model intervention:

| Error Type | Action |
|------------|--------|
| `timeout` | Withhold + retry with backoff |
| `rate_limit` | Withhold + retry with backoff |
| `file_not_found` | Withhold + retry with backoff |
| `lock_conflict` | Withhold + retry with backoff |
| `permission` | Withhold + retry with backoff |
| `syntax_error` | Report to model immediately |
| `logic_error` | Report to model immediately |

Max retries: 2 (configurable via `GOLEM_MAX_RETRY`)
Backoff: 3s, 6s, 9s...

### Stage 2: Delegation

If retry exhausted, delegate to alternative SOUL matched by specialty.

### Stage 3: Escalation

If delegation fails, escalate to Director for task decomposition or user intervention.

---

## Compatibility

### Agent Skills (agentskills.io) Mapping

SOUL Spec is designed to be compatible with the [Agent Skills](https://agentskills.io) open standard.

| Agent Skills Field | SOUL Spec Equivalent |
|--------------------|----------------------|
| `name` | `name` |
| `description` | Generated from `role` + `specialty` + `personality` |
| `allowed-tools` | `tools` |
| `compatibility` | `model` + `isolation` |
| `metadata.rank` | `rank` |
| `metadata.specialty` | `specialty` |
| `metadata.maxTurns` | `maxTurns` |
| `metadata.effort` | `effort` |
| `metadata.created` | `created` |

A SOUL can be exported as an Agent Skill:

```yaml
# SKILL.md (generated from ryn.md)
---
name: golem-soul-ryn
description: >
  Backend developer specializing in spring-boot, mariadb, rest-api, jpa,
  clean-architecture. Rank: junior. Use for backend API development tasks.
allowed-tools: Read Edit Write Bash Grep Glob
compatibility: Requires Claude Code or compatible agent runtime.
metadata:
  golem-soul: "true"
  golem-rank: junior
  golem-role: backend-developer
  golem-specialty: "spring-boot,mariadb,rest-api,jpa,clean-architecture"
  golem-maxTurns: "25"
  golem-effort: medium
  golem-created: "2026-03-30"
---
```

### Platform Adapters

SOUL Spec is runtime-agnostic. Adapters translate SOUL definitions for specific platforms:

| Platform | Adapter Maps |
|----------|-------------|
| **OMC (Claude Code)** | `role` -> OMC agent type, `tools` -> `allowed_tools`, `model` -> agent model |
| **Hermes Agent** | `role` -> skill category, `memory` -> Honcho integration, `rank` -> capability tier |
| **gstack** | `role` -> sprint phase assignment, `chemistry` -> `/pair-agent` optimization |

---

## Design Principles

1. **Earned, not granted** -- Tools and permissions unlock through demonstrated competence, not configuration.
2. **Persona is compass, not cage** -- SOUL personality guides direction without limiting capability.
3. **Growth is data** -- Every task, review, and collaboration produces measurable records.
4. **Platform-agnostic core** -- The spec defines the contract; adapters handle runtime specifics.
5. **Progressive disclosure** -- Frontmatter for identity, body for context, external files for history.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-04-18 | Initial specification |
