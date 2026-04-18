# SOUL Spec <-> Agent Skills Compatibility Mapping

> How GolemGarden SOULs map to the [agentskills.io](https://agentskills.io) open standard.

## Overview

A SOUL can be exported as an Agent Skill for use in any compatible agent runtime
(Claude Code, Gemini CLI, Cursor, VS Code Copilot, OpenCode, Junie, Roo Code, etc.).

The mapping is **lossy in one direction**: Agent Skills lack growth, chemistry, and memory
concepts, so those are preserved as `metadata` fields with a `golem-` prefix.

## Field Mapping

### SOUL -> Agent Skill

| SOUL Field | Agent Skill Field | Transformation |
|------------|-------------------|----------------|
| `name` | `name` | Prefix with `golem-soul-` (e.g., `golem-soul-ryn`) |
| `role` + `specialty` + `personality` | `description` | Generate natural language description |
| `tools` | `allowed-tools` | Join with spaces (e.g., `Read Edit Write Bash`) |
| `model` + `isolation` | `compatibility` | Generate requirements string |
| `role` | `metadata.golem-role` | Direct copy |
| `rank` | `metadata.golem-rank` | Direct copy |
| `specialty` | `metadata.golem-specialty` | Join with commas |
| `maxTurns` | `metadata.golem-maxTurns` | String conversion |
| `effort` | `metadata.golem-effort` | Direct copy |
| `created` | `metadata.golem-created` | Direct copy |
| -- | `metadata.golem-soul` | Always `"true"` (marker) |

### Agent Skill -> SOUL

| Agent Skill Field | SOUL Field | Transformation |
|-------------------|------------|----------------|
| `name` | `name` | Strip `golem-soul-` prefix |
| `description` | `personality` | Use as personality (lossy) |
| `allowed-tools` | `tools` | Split by spaces into array |
| `metadata.golem-role` | `role` | Direct copy |
| `metadata.golem-rank` | `rank` | Direct copy, default `novice` |
| `metadata.golem-specialty` | `specialty` | Split by commas into array |
| `metadata.golem-maxTurns` | `maxTurns` | Parse integer |
| `metadata.golem-effort` | `effort` | Direct copy |
| `metadata.golem-created` | `created` | Direct copy |

## What is NOT portable

These GolemGarden concepts have no Agent Skills equivalent:

| Concept | Reason | Preservation Strategy |
|---------|--------|----------------------|
| **Growth Log** | Agent Skills are stateless | Export as `references/growth-log.md` |
| **Chemistry** | No inter-skill relationships | Not exported (team-level data, not per-SOUL) |
| **Achievements** | No badge/gamification concept | Export as `references/achievements.md` |
| **Skill Tree** | No specialization branching | Store branch in `metadata.golem-branch` |
| **Memory** | No episodic memory | Export as `references/memory.md` |
| **Mailbox** | No inter-skill messaging | Not portable |
| **Budget** | No cost tracking | Not portable |
| **Error Recovery** | No retry/delegation protocol | Encode in SKILL.md body instructions |

## Export Example

### Input: `souls/ryn.md`

```yaml
---
name: ryn
role: backend-developer
rank: junior
specialty: [spring-boot, mariadb, rest-api, jpa, clean-architecture]
personality: "꼼꼼하고 신중한 백엔드 개발자"
model: sonnet
tools: [Read, Edit, Write, Bash, Grep, Glob]
maxTurns: 25
isolation: none
effort: medium
created: 2026-03-30
---
```

### Output: `golem-soul-ryn/SKILL.md`

```markdown
---
name: golem-soul-ryn
description: >
  Backend developer specializing in spring-boot, mariadb, rest-api, jpa, and
  clean-architecture. Junior rank with proven track record. Use for backend API
  development, database design, and REST endpoint implementation.
allowed-tools: Read Edit Write Bash Grep Glob
compatibility: Requires Claude Code (sonnet model recommended) or compatible agent runtime.
metadata:
  golem-soul: "true"
  golem-role: backend-developer
  golem-rank: junior
  golem-specialty: "spring-boot,mariadb,rest-api,jpa,clean-architecture"
  golem-maxTurns: "25"
  golem-effort: medium
  golem-created: "2026-03-30"
---

## Project Context

Backend API developer with focus on clean architecture patterns.

## Domain Knowledge

- Spring Boot 3 + JPA best practices
- MariaDB query optimization
- RESTful API design principles
- Connection pooling with HikariCP

## Behavioral Principles

- Write tests before implementation (TDD)
- Prefer composition over inheritance
- Never expose internal exceptions to API consumers

## Growth Status

Rank: junior (promoted from novice after 10 successful tasks)
```

### Output directory structure:

```
golem-soul-ryn/
├── SKILL.md              # Core skill definition
└── references/
    ├── growth-log.md     # Task history summary
    ├── achievements.md   # Earned badges
    └── memory.md         # Learned lessons
```

## Platform-Specific Adapters

### Hermes Agent Integration

```python
# Hermes skill registration from SOUL
from golem_core import SoulSpec

soul = SoulSpec.load("souls/ryn.md")
hermes_skill = soul.to_hermes_skill()
# -> registers as Hermes skill with:
#    - capability tier from rank
#    - tool restrictions from tools
#    - memory integration via Honcho
```

### gstack Integration

```bash
# gstack pipeline with SOUL-based team assignment
# chemistry_team_recommend returns optimal SOUL pairs
# for gstack's /pair-agent coordination
gstack_team=$(forge chemistry recommend "$task_keywords")
```

### OMC Integration (Current)

```bash
# Direct mapping (already implemented)
source lib/soul-parser.sh
soul_parse "souls/ryn.md"
omc_agent=$(soul_to_omc_agent "$SOUL_ROLE")
# -> "executor" with SOUL_TOOLS as allowed_tools
```
