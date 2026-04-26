"""Parsers for growth-log, forge-board, budget, and rank data."""

from __future__ import annotations

import json
import logging
import os
import re
from datetime import datetime, timezone
from itertools import combinations
from pathlib import Path
from typing import Optional

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

_VALID_SOUL_ID = re.compile(r"^[A-Za-z0-9_-]+$")

# ---------------------------------------------------------------------------
# Rank progression
# ---------------------------------------------------------------------------

_RANK_ORDER = ["novice", "junior", "senior", "master"]
_RANK_THRESHOLDS: dict[str, int] = {
    "novice": 10,   # tasks needed to reach junior
    "junior": 30,   # tasks needed to reach senior
    "senior": 60,   # tasks needed to reach master
}


def _rank_progress(rank: str, tasks_total: int) -> dict:
    rank_lower = rank.lower()
    idx = _RANK_ORDER.index(rank_lower) if rank_lower in _RANK_ORDER else 0
    if rank_lower == "master":
        return {"current": "master", "next": None, "tasks_to_promote": 0}
    threshold = _RANK_THRESHOLDS.get(rank_lower, 10)
    next_rank = _RANK_ORDER[idx + 1] if idx + 1 < len(_RANK_ORDER) else None
    tasks_to_promote = max(0, threshold - tasks_total)
    return {
        "current": rank_lower,
        "next": next_rank,
        "tasks_to_promote": tasks_to_promote,
    }


# ---------------------------------------------------------------------------
# Growth-log parsing
# ---------------------------------------------------------------------------

class ActivityEntry(BaseModel):
    soul: str
    task: str
    result: str
    ts: str


def _parse_ts(entry: dict) -> str:
    """Normalise date/timestamp field to ISO-8601 string."""
    for key in ("timestamp", "ts", "date"):
        val = entry.get(key)
        if val:
            return str(val)
    return ""


def _load_growth_log(soul_id: str, golem_dir: Path) -> list[dict]:
    """Load all JSONL lines for a given soul. Returns [] if file missing."""
    path = golem_dir / "growth-log" / f"{soul_id}.jsonl"
    if not path.is_file():
        return []
    entries: list[dict] = []
    try:
        for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw_line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                logger.warning("skipping malformed JSONL line in %s: %r", path, line[:80])
    except OSError as exc:
        logger.warning("cannot read growth-log %s: %s", path, exc)
    return entries


# mtime cache: {(resolved_golem_dir, soul_id): (mtime, entries)}
_growth_cache: dict[tuple[Path, str], tuple[float, list[dict]]] = {}


def _cached_load_growth_log(soul_id: str, golem_dir: Path) -> list[dict]:
    resolved = golem_dir.resolve()
    path = resolved / "growth-log" / f"{soul_id}.jsonl"
    try:
        mtime = path.stat().st_mtime if path.is_file() else 0.0
    except OSError:
        mtime = 0.0
    cache_key = (resolved, soul_id)
    cached = _growth_cache.get(cache_key)
    if cached and cached[0] == mtime:
        return cached[1]
    entries = _load_growth_log(soul_id, resolved)
    _growth_cache[cache_key] = (mtime, entries)
    return entries


def _soul_ids_with_logs(golem_dir: Path) -> list[str]:
    log_dir = golem_dir / "growth-log"
    if not log_dir.is_dir():
        return []
    return [
        f.stem
        for f in sorted(log_dir.glob("*.jsonl"))
        if _VALID_SOUL_ID.match(f.stem)
    ]


# ---------------------------------------------------------------------------
# Budget
# ---------------------------------------------------------------------------

def _load_total_cost(golem_dir: Path) -> float:
    budget_path = golem_dir / "budget-state.json"
    if not budget_path.is_file():
        return 0.0
    try:
        data = json.loads(budget_path.read_text(encoding="utf-8", errors="replace"))
        return float(data.get("dollars_spent", 0.0))
    except (json.JSONDecodeError, ValueError, OSError) as exc:
        logger.warning("cannot read budget-state.json: %s", exc)
        return 0.0


# ---------------------------------------------------------------------------
# Overview
# ---------------------------------------------------------------------------

class ActiveSoul(BaseModel):
    id: str
    name: str
    rank: str


class OverviewResponse(BaseModel):
    project_id: str
    name: str
    souls_count: int
    active_souls: list[ActiveSoul]
    recent_activity: list[ActivityEntry]
    total_tasks: int
    success_rate: float
    total_cost_usd: float
    last_activity_ts: Optional[str]


def build_overview(project_id: str, project_name: str, project_path: Path) -> OverviewResponse:
    golem_dir = project_path / ".golem"
    soul_ids = _soul_ids_with_logs(golem_dir)

    # Collect all entries across all souls
    all_entries: list[dict] = []
    for sid in soul_ids:
        for entry in _cached_load_growth_log(sid, golem_dir):
            entry = dict(entry)
            entry.setdefault("soul", sid)
            all_entries.append(entry)

    # Sort by ts descending (fall back to empty string so they sort last)
    all_entries.sort(key=lambda e: _parse_ts(e), reverse=True)

    # Totals
    total_tasks = len(all_entries)
    success_count = sum(
        1 for e in all_entries
        if str(e.get("result", "")).lower() in ("success", "pass")
    )
    success_rate = round(success_count / total_tasks, 4) if total_tasks else 0.0

    # Recent activity (last 8)
    recent_activity = [
        ActivityEntry(
            soul=str(e.get("soul", "")),
            task=str(e.get("task", "")),
            result=str(e.get("result", "")),
            ts=_parse_ts(e),
        )
        for e in all_entries[:8]
    ]

    # Active souls: top 3-4 by count of entries in last 7 days
    now_date = datetime.now(tz=timezone.utc).date()
    soul_recent_counts: dict[str, int] = {}
    for e in all_entries:
        ts_val = _parse_ts(e)
        try:
            entry_date = datetime.fromisoformat(ts_val.replace("Z", "+00:00")).date()
            days_ago = (now_date - entry_date).days
        except (ValueError, AttributeError):
            # If date-only format like "2026-04-06"
            try:
                entry_date = datetime.strptime(ts_val[:10], "%Y-%m-%d").date()
                days_ago = (now_date - entry_date).days
            except (ValueError, AttributeError):
                days_ago = 999
        if days_ago <= 7:
            sid = str(e.get("soul", ""))
            soul_recent_counts[sid] = soul_recent_counts.get(sid, 0) + 1

    top_active_ids = sorted(
        soul_recent_counts, key=lambda s: soul_recent_counts[s], reverse=True
    )[:4]

    # F1: resolve each active soul to {id, name, rank} so the UI can render rank badges.
    # Local import to avoid circular import with souls.py.
    from golem_gateway.souls import get_soul_by_id  # noqa: WPS433

    active_souls: list[ActiveSoul] = []
    for sid in top_active_ids:
        soul = get_soul_by_id(project_path, sid)
        if soul is None:
            # Orphan growth-log entry — keep something sane so the UI doesn't crash.
            active_souls.append(ActiveSoul(id=sid, name=sid.capitalize(), rank="unknown"))
        else:
            active_souls.append(ActiveSoul(id=sid, name=soul.name, rank=soul.rank))

    last_activity_ts = _parse_ts(all_entries[0]) if all_entries else None
    total_cost_usd = _load_total_cost(golem_dir)

    return OverviewResponse(
        project_id=project_id,
        name=project_name,
        souls_count=len(soul_ids),
        active_souls=active_souls,
        recent_activity=recent_activity,
        total_tasks=total_tasks,
        success_rate=success_rate,
        total_cost_usd=total_cost_usd,
        last_activity_ts=last_activity_ts,
    )


# ---------------------------------------------------------------------------
# Soul activity
# ---------------------------------------------------------------------------

class RankProgress(BaseModel):
    current: str
    next: Optional[str]
    tasks_to_promote: int


class TaskEntry(BaseModel):
    task: str
    result: str
    ts: str


class SoulActivityResponse(BaseModel):
    soul_id: str
    rank: str
    tasks_total: int
    tasks_success: int
    streak: int
    last_task_ts: Optional[str]
    recent_tasks: list[TaskEntry]
    rank_progress: RankProgress


def _calc_streak(entries: list[dict]) -> int:
    """Count consecutive successes from the most-recent entry backwards."""
    streak = 0
    for e in entries:
        if str(e.get("result", "")).lower() in ("success", "pass"):
            streak += 1
        else:
            break
    return streak


def build_soul_activity(soul_id: str, rank: str, project_path: Path) -> SoulActivityResponse:
    golem_dir = project_path / ".golem"
    entries = _cached_load_growth_log(soul_id, golem_dir)
    entries_sorted = sorted(entries, key=lambda e: _parse_ts(e), reverse=True)

    tasks_total = len(entries_sorted)
    tasks_success = sum(
        1 for e in entries_sorted
        if str(e.get("result", "")).lower() in ("success", "pass")
    )
    streak = _calc_streak(entries_sorted)
    last_task_ts = _parse_ts(entries_sorted[0]) if entries_sorted else None

    recent_tasks = [
        TaskEntry(
            task=str(e.get("task", "")),
            result=str(e.get("result", "")),
            ts=_parse_ts(e),
        )
        for e in entries_sorted[:10]
    ]

    rp = _rank_progress(rank, tasks_total)
    rank_progress = RankProgress(
        current=rp["current"],
        next=rp["next"],
        tasks_to_promote=rp["tasks_to_promote"],
    )

    return SoulActivityResponse(
        soul_id=soul_id,
        rank=rank,
        tasks_total=tasks_total,
        tasks_success=tasks_success,
        streak=streak,
        last_task_ts=last_task_ts,
        recent_tasks=recent_tasks,
        rank_progress=rank_progress,
    )


# ---------------------------------------------------------------------------
# Forge board
# ---------------------------------------------------------------------------

class TeamMember(BaseModel):
    soul: str
    name: str
    role: str
    agent: str
    model: str
    rank: str
    status: str


class TechDebtItem(BaseModel):
    text: str
    resolved: bool


class HistoryEntry(BaseModel):
    date: str
    task: str
    soul: str
    result: str


class BoardResponse(BaseModel):
    raw_md: str
    team: list[TeamMember]
    tech_debt: list[TechDebtItem]
    history: list[HistoryEntry]


_EMPTY_BOARD = BoardResponse(raw_md="", team=[], tech_debt=[], history=[])


def _parse_md_table_rows(lines: list[str]) -> list[list[str]]:
    """Extract data rows from a markdown table (skip header separator)."""
    rows: list[list[str]] = []
    for line in lines:
        stripped = line.strip()
        if not stripped.startswith("|"):
            break
        # Skip separator lines like |---|---|
        if re.match(r"^\|[\s\-:|]+\|", stripped):
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        rows.append(cells)
    return rows


def _section_lines(md: str, header: str) -> list[str]:
    """Return lines belonging to the section that starts with `## header`.

    F6: exact `## <header>` match (with optional trailing whitespace) so that
    "팀 구성" does not accidentally match "## 팀 구성 요약".
    """
    target = f"## {header}"
    inside = False
    result: list[str] = []
    for line in md.splitlines():
        if line.strip() == target:
            inside = True
            continue
        if inside:
            if line.strip().startswith("## "):
                break
            result.append(line)
    return result


def build_board(project_path: Path) -> BoardResponse:
    board_path = project_path / ".golem" / "forge-board.md"
    if not board_path.is_file():
        return _EMPTY_BOARD

    try:
        raw_md = board_path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        logger.warning("cannot read forge-board.md: %s", exc)
        return _EMPTY_BOARD

    # --- Team table (## 팀 구성) ---
    team_lines = _section_lines(raw_md, "팀 구성")
    table_lines = [l for l in team_lines if l.strip().startswith("|")]
    # F7: `_parse_md_table_rows` already strips the `|---|---|` separator, so the
    # first surviving row is always the markdown table header — skip it
    # unconditionally instead of fragile content-based detection.
    data_rows = _parse_md_table_rows(table_lines)
    if data_rows:
        data_rows = data_rows[1:]

    team: list[TeamMember] = []
    for row in data_rows:
        if len(row) < 6:
            continue
        soul_cell = row[0].strip()
        team.append(TeamMember(
            soul=soul_cell,
            name=soul_cell,  # F2: same value, surfaced under expected UI key
            role=row[1],
            agent=row[2],
            model=row[3],
            rank=row[4],
            status=row[5],
        ))

    # --- Tech debt (## 기술 부채) ---
    debt_lines = _section_lines(raw_md, "기술 부채")
    tech_debt: list[TechDebtItem] = []
    for line in debt_lines:
        stripped = line.strip()
        # Match numbered list: "1. text" or bullet "- text"
        m = re.match(r"^(\d+\.|[-*])\s+(.+)$", stripped)
        if m:
            text = m.group(2).strip()
            resolved = "~~" in text
            # Clean strikethrough markers for display
            text_clean = re.sub(r"~~(.+?)~~", r"\1", text)
            tech_debt.append(TechDebtItem(text=text_clean, resolved=resolved))

    # --- History table (## 태스크 히스토리) ---
    history_lines = _section_lines(raw_md, "태스크 히스토리")
    history_table = [l for l in history_lines if l.strip().startswith("|")]
    hist_rows = _parse_md_table_rows(history_table)
    # F7: separator already stripped by parser; first row is always the header.
    if hist_rows:
        hist_rows = hist_rows[1:]

    history: list[HistoryEntry] = []
    for row in hist_rows:
        if len(row) < 4:
            continue
        history.append(HistoryEntry(
            date=row[0],
            task=row[1],
            soul=row[2],
            result=row[3],
        ))

    return BoardResponse(raw_md=raw_md, team=team, tech_debt=tech_debt, history=history)


# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------

class SessionSummary(BaseModel):
    session_id: str
    task: str
    souls: list[str]
    status: str
    created_at: str
    ended_at: Optional[str]


def _parse_session_meta(meta_path: Path) -> Optional[dict]:
    """Parse a .meta file (single-line JSON). Returns None on error."""
    try:
        text = meta_path.read_text(encoding="utf-8", errors="replace").strip()
        if not text:
            return None
        return json.loads(text)
    except (json.JSONDecodeError, OSError) as exc:
        logger.warning("skipping malformed session meta %s: %s", meta_path, exc)
        return None


def _mtime_iso(path: Path) -> str:
    """Return mtime of path as ISO-8601 UTC string, or empty string."""
    try:
        mtime = path.stat().st_mtime
        return datetime.fromtimestamp(mtime, tz=timezone.utc).isoformat()
    except OSError:
        return ""


def scan_sessions(project_path: Path) -> list[SessionSummary]:
    """Parse .golem/sessions/ and return list[SessionSummary] sorted by created_at desc."""
    sessions_dir = project_path / ".golem" / "sessions"
    if not sessions_dir.is_dir():
        return []

    results: list[SessionSummary] = []

    # Layout A: <name>.meta sibling files
    for meta_path in sessions_dir.glob("*.meta"):
        stem = meta_path.stem
        data = _parse_session_meta(meta_path)
        if data is None:
            data = {}

        # Fallback created_at from meta mtime
        created_at = (
            str(data.get("started") or data.get("created_at") or "")
            or _mtime_iso(meta_path)
        )
        ended_at = str(data.get("ended") or data.get("ended_at") or "") or None
        if ended_at == "":
            ended_at = None

        status = str(data.get("status") or "")
        if not status:
            status = "completed" if ended_at else "active"

        souls_raw = data.get("souls", [])
        if not isinstance(souls_raw, list):
            souls_raw = []

        results.append(SessionSummary(
            session_id=str(data.get("id") or stem),
            task=str(data.get("task") or stem),
            souls=[str(s) for s in souls_raw],
            status=status,
            created_at=created_at,
            ended_at=ended_at,
        ))

    # Layout B: subdirectory with meta.json
    for child in sessions_dir.iterdir():
        if not child.is_dir():
            continue
        meta_path = child / "meta.json"
        if not meta_path.exists():
            data = {}
        else:
            data = _parse_session_meta(meta_path) or {}

        created_at = (
            str(data.get("created_at") or data.get("started") or "")
            or _mtime_iso(child)
        )
        ended_at = str(data.get("ended_at") or data.get("ended") or "") or None
        if ended_at == "":
            ended_at = None

        status = str(data.get("status") or "")
        if not status:
            status = "completed" if ended_at else "active"

        souls_raw = data.get("souls", [])
        if not isinstance(souls_raw, list):
            souls_raw = []

        results.append(SessionSummary(
            session_id=str(data.get("id") or child.name),
            task=str(data.get("task") or child.name),
            souls=[str(s) for s in souls_raw],
            status=status,
            created_at=created_at,
            ended_at=ended_at,
        ))

    results.sort(key=lambda s: s.created_at, reverse=True)
    return results


# ---------------------------------------------------------------------------
# Mailbox
# ---------------------------------------------------------------------------

class MailboxEntry(BaseModel):
    from_soul: str = Field(serialization_alias="from")
    to: str
    type: str
    content: str
    ts: str

    model_config = {"populate_by_name": True, "serialize_by_alias": True}

    @classmethod
    def from_dict(cls, d: dict) -> "MailboxEntry":
        return cls(
            from_soul=str(d.get("from") or ""),
            to=str(d.get("to") or ""),
            type=str(d.get("type") or "info"),
            content=str(d.get("content") or ""),
            ts=str(d.get("ts") or ""),
        )


# mtime cache: {resolved_path: (mtime, entries)}
_mailbox_cache: dict[Path, tuple[float, list[dict]]] = {}


def _load_mailbox_file(path: Path) -> list[dict]:
    resolved = path.resolve()
    try:
        mtime = resolved.stat().st_mtime if resolved.is_file() else 0.0
    except OSError:
        mtime = 0.0
    cached = _mailbox_cache.get(resolved)
    if cached and cached[0] == mtime:
        return cached[1]

    entries: list[dict] = []
    try:
        for raw_line in resolved.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw_line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                logger.warning("skipping malformed JSONL line in %s: %r", resolved, line[:80])
    except OSError as exc:
        logger.warning("cannot read mailbox %s: %s", resolved, exc)

    _mailbox_cache[resolved] = (mtime, entries)
    return entries


def scan_mailbox(project_path: Path, limit: int = 50) -> list[MailboxEntry]:
    """Read all *.jsonl files in .golem/mailbox/, merge, sort by ts desc, take limit."""
    mailbox_dir = project_path / ".golem" / "mailbox"
    if not mailbox_dir.is_dir():
        return []

    all_entries: list[dict] = []
    for jsonl_path in sorted(mailbox_dir.glob("*.jsonl")):
        if not _VALID_SOUL_ID.match(jsonl_path.stem):
            continue
        all_entries.extend(_load_mailbox_file(jsonl_path))

    all_entries.sort(key=lambda e: str(e.get("ts") or ""), reverse=True)
    return [MailboxEntry.from_dict(e) for e in all_entries[:limit]]


# ---------------------------------------------------------------------------
# Timeline
# ---------------------------------------------------------------------------

class TimelineEvent(BaseModel):
    type: str
    soul: str
    ts: str
    summary: str
    details: dict


def _growth_to_timeline(project_path: Path) -> list[TimelineEvent]:
    """Convert growth-log entries into TimelineEvent(type='task')."""
    golem_dir = project_path / ".golem"
    soul_ids = _soul_ids_with_logs(golem_dir)
    events: list[TimelineEvent] = []
    for sid in soul_ids:
        for entry in _cached_load_growth_log(sid, golem_dir):
            ts = _parse_ts(entry)
            result = str(entry.get("result") or "")
            events.append(TimelineEvent(
                type="task",
                soul=str(entry.get("soul") or sid),
                ts=ts,
                summary=str(entry.get("task") or ""),
                details={
                    "result": result,
                    "files_changed": entry.get("files_changed"),
                    "tests_passed": entry.get("tests_passed"),
                },
            ))
    return events


def _sessions_to_timeline(project_path: Path) -> list[TimelineEvent]:
    """Convert session lifecycle data into TimelineEvent(type='session_start'|'session_end')."""
    sessions_dir = project_path / ".golem" / "sessions"
    if not sessions_dir.is_dir():
        return []

    events: list[TimelineEvent] = []

    # Layout A: *.jsonl session transcript files
    for jsonl_path in sessions_dir.glob("*.jsonl"):
        if not jsonl_path.is_file():
            continue
        try:
            for raw_line in jsonl_path.read_text(encoding="utf-8", errors="replace").splitlines():
                line = raw_line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    logger.warning("skipping malformed session JSONL line in %s: %r", jsonl_path, line[:80])
                    continue
                action = str(entry.get("action") or "")
                if action not in ("session_start", "session_end"):
                    continue
                ts = str(entry.get("ts") or "")
                soul = str(entry.get("soul") or "system")
                detail = str(entry.get("detail") or "")
                events.append(TimelineEvent(
                    type=action,
                    soul=soul,
                    ts=ts,
                    summary=detail,
                    details={"action": action},
                ))
        except OSError as exc:
            logger.warning("cannot read session transcript %s: %s", jsonl_path, exc)

    # Layout B: subdirectory/transcript.jsonl
    for child in sessions_dir.iterdir():
        if not child.is_dir():
            continue
        for transcript in (child / "transcript.jsonl", child / "transcript.md"):
            if transcript.suffix == ".jsonl" and transcript.is_file():
                try:
                    for raw_line in transcript.read_text(encoding="utf-8", errors="replace").splitlines():
                        line = raw_line.strip()
                        if not line:
                            continue
                        try:
                            entry = json.loads(line)
                        except json.JSONDecodeError:
                            continue
                        action = str(entry.get("action") or "")
                        if action not in ("session_start", "session_end"):
                            continue
                        events.append(TimelineEvent(
                            type=action,
                            soul=str(entry.get("soul") or "system"),
                            ts=str(entry.get("ts") or ""),
                            summary=str(entry.get("detail") or ""),
                            details={"action": action},
                        ))
                except OSError as exc:
                    logger.warning("cannot read transcript %s: %s", transcript, exc)

    return events


def _mailbox_to_timeline(project_path: Path) -> list[TimelineEvent]:
    """Convert mailbox entries into TimelineEvent(type='mailbox')."""
    mailbox_dir = project_path / ".golem" / "mailbox"
    if not mailbox_dir.is_dir():
        return []

    events: list[TimelineEvent] = []
    for jsonl_path in sorted(mailbox_dir.glob("*.jsonl")):
        if not _VALID_SOUL_ID.match(jsonl_path.stem):
            continue
        for entry in _load_mailbox_file(jsonl_path):
            sender = str(entry.get("from") or "")
            to = str(entry.get("to") or "")
            content = str(entry.get("content") or "")
            msg_type = str(entry.get("type") or "info")
            events.append(TimelineEvent(
                type="mailbox",
                soul=sender,
                ts=str(entry.get("ts") or ""),
                summary=f"{sender} → {to}: {content[:80]}",
                details={"to": to, "msg_type": msg_type, "content": content},
            ))
    return events


def build_timeline(project_path: Path, limit: int = 50) -> list[TimelineEvent]:
    """Merge growth-log + sessions + mailbox into a single feed sorted by ts desc."""
    events: list[TimelineEvent] = []
    events.extend(_growth_to_timeline(project_path))
    events.extend(_sessions_to_timeline(project_path))
    events.extend(_mailbox_to_timeline(project_path))

    events.sort(key=lambda e: e.ts, reverse=True)
    return events[:limit]


# ---------------------------------------------------------------------------
# Achievements
# ---------------------------------------------------------------------------

class AchievementEntry(BaseModel):
    id: str
    soul: str
    badge: str
    description: str
    earned_at: str


def build_achievements(project_path: Path) -> list[AchievementEntry]:
    """Parse .golem/achievements.jsonl, return sorted by earned_at desc."""
    path = (project_path / ".golem" / "achievements.jsonl").resolve()
    if not path.is_file():
        return []

    entries: list[AchievementEntry] = []
    try:
        for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw_line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                logger.warning("skipping malformed achievements line: %r", line[:80])
                continue
            # Real shape: {"date":"2026-04-18","soul":"ryn","id":"first_blood","name":"First Blood","desc":"첫 태스크 성공"}
            entries.append(AchievementEntry(
                id=str(d.get("id") or ""),
                soul=str(d.get("soul") or ""),
                badge=str(d.get("name") or d.get("badge") or ""),
                description=str(d.get("desc") or d.get("description") or ""),
                earned_at=str(d.get("date") or d.get("earned_at") or ""),
            ))
    except OSError as exc:
        logger.warning("cannot read achievements.jsonl: %s", exc)

    entries.sort(key=lambda a: a.earned_at, reverse=True)
    return entries


# ---------------------------------------------------------------------------
# Chemistry
# ---------------------------------------------------------------------------

class ChemistryPair(BaseModel):
    souls: list[str]
    score: Optional[float]
    interactions: int


class ChemistryResponse(BaseModel):
    pairs: list[ChemistryPair]
    raw_events: list[dict]


def build_chemistry(project_path: Path) -> ChemistryResponse:
    """Parse .golem/chemistry.jsonl — aggregate pair scores + expose last 30 raw events."""
    path = (project_path / ".golem" / "chemistry.jsonl").resolve()
    if not path.is_file():
        return ChemistryResponse(pairs=[], raw_events=[])

    raw_events: list[dict] = []
    try:
        for raw_line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw_line.strip()
            if not line:
                continue
            try:
                raw_events.append(json.loads(line))
            except json.JSONDecodeError:
                logger.warning("skipping malformed chemistry line: %r", line[:80])
    except OSError as exc:
        logger.warning("cannot read chemistry.jsonl: %s", exc)

    # Aggregate per (soul_a, soul_b) pair — canonicalise by sorting the two soul names
    pair_total: dict[tuple[str, str], int] = {}
    pair_positive: dict[tuple[str, str], int] = {}

    for event in raw_events:
        souls_raw = event.get("souls") or []
        if not isinstance(souls_raw, list) or len(souls_raw) < 2:
            # Try from/to fields
            s1 = str(event.get("from") or event.get("soul") or "")
            s2 = str(event.get("to") or event.get("partner") or "")
            if not s1 or not s2:
                continue
            souls_raw = [s1, s2]

        # F8: triad-aware. A {souls:[a,b,c]} event yields pairs (a,b),(a,c),(b,c).
        # Each pair gets 1 interaction credit per event; raw_events keeps the
        # full soul list intact for downstream transparency.
        soul_strs = [str(s) for s in souls_raw if s]
        result = str(event.get("result") or event.get("type") or "")
        is_positive = result.lower() in (
            "success", "pass", "positive", "collaborate", "collab"
        )
        for a, b in combinations(soul_strs, 2):
            key = tuple(sorted([a, b]))  # type: ignore[arg-type]
            pair_total[key] = pair_total.get(key, 0) + 1
            if is_positive:
                pair_positive[key] = pair_positive.get(key, 0) + 1

    pairs: list[ChemistryPair] = []
    for key, total in pair_total.items():
        positive = pair_positive.get(key, 0)
        score: Optional[float] = round(positive / total, 2) if total > 0 else None
        pairs.append(ChemistryPair(
            souls=list(key),
            score=score,
            interactions=total,
        ))

    pairs.sort(key=lambda p: p.interactions, reverse=True)

    raw_events_sorted = sorted(raw_events, key=lambda e: str(e.get("ts") or e.get("date") or ""), reverse=True)
    return ChemistryResponse(pairs=pairs, raw_events=raw_events_sorted[:30])


# ---------------------------------------------------------------------------
# Budget
# ---------------------------------------------------------------------------

class BudgetSoul(BaseModel):
    soul: str
    cost_usd: float
    tasks: int


class BudgetDaily(BaseModel):
    date: str
    cost_usd: float


class BudgetResponse(BaseModel):
    total_cost_usd: float
    by_soul: list[BudgetSoul]
    daily: list[BudgetDaily]
    budget_limit_usd: Optional[float]
    warning: Optional[str]


def build_budget(project_path: Path) -> BudgetResponse:
    """Aggregate cost from growth-log + budget-state.json."""
    golem_dir = project_path / ".golem"
    soul_ids = _soul_ids_with_logs(golem_dir)

    soul_cost: dict[str, float] = {}
    soul_tasks: dict[str, int] = {}
    daily_cost: dict[str, float] = {}

    for sid in soul_ids:
        for entry in _cached_load_growth_log(sid, golem_dir):
            cost = 0.0
            raw_cost = entry.get("cost_usd")
            if raw_cost is not None:
                try:
                    cost = float(raw_cost)
                except (TypeError, ValueError):
                    pass
            soul_cost[sid] = soul_cost.get(sid, 0.0) + cost
            soul_tasks[sid] = soul_tasks.get(sid, 0) + 1

            # Daily aggregation — use "date" field or first 10 chars of ts
            date_str = str(entry.get("date") or _parse_ts(entry) or "")[:10]
            if date_str:
                daily_cost[date_str] = daily_cost.get(date_str, 0.0) + cost

    # Total from growth-log aggregation
    total_from_log = sum(soul_cost.values())

    # Budget-state fallback / limit
    budget_limit_usd: Optional[float] = None
    total_from_state: Optional[float] = None
    budget_path = golem_dir / "budget-state.json"
    if budget_path.is_file():
        try:
            bdata = json.loads(budget_path.read_text(encoding="utf-8", errors="replace"))
            dollar_budget = bdata.get("dollar_budget")
            if dollar_budget is not None:
                try:
                    budget_limit_usd = float(dollar_budget)
                except (TypeError, ValueError):
                    pass
            dollars_spent = bdata.get("dollars_spent")
            if dollars_spent is not None:
                try:
                    total_from_state = float(dollars_spent)
                except (TypeError, ValueError):
                    pass
        except (json.JSONDecodeError, OSError) as exc:
            logger.warning("cannot read budget-state.json: %s", exc)

    # Prefer budget-state total if log total is 0 (not all entries have cost_usd)
    total_cost_usd = total_from_log if total_from_log > 0.0 else (total_from_state or 0.0)

    # Warning threshold: 80 % of limit
    warning: Optional[str] = None
    if budget_limit_usd and budget_limit_usd > 0:
        pct = total_cost_usd / budget_limit_usd
        if pct >= 1.0:
            warning = f"Budget exceeded: ${total_cost_usd:.3f} / ${budget_limit_usd:.2f}"
        elif pct >= 0.8:
            warning = f"Approaching budget limit: ${total_cost_usd:.3f} / ${budget_limit_usd:.2f} ({pct*100:.0f}%)"

    by_soul = [
        BudgetSoul(soul=sid, cost_usd=round(soul_cost.get(sid, 0.0), 4), tasks=soul_tasks.get(sid, 0))
        for sid in sorted(soul_cost, key=lambda s: soul_cost[s], reverse=True)
    ]

    # Sort daily desc, cap at 30
    daily = [
        BudgetDaily(date=d, cost_usd=round(v, 4))
        for d, v in sorted(daily_cost.items(), reverse=True)
    ][:30]

    return BudgetResponse(
        total_cost_usd=round(total_cost_usd, 4),
        by_soul=by_soul,
        daily=daily,
        budget_limit_usd=budget_limit_usd,
        warning=warning,
    )


# ---------------------------------------------------------------------------
# Skill-tree
# ---------------------------------------------------------------------------

import math as _math


class SkillBranch(BaseModel):
    name: str
    level: int
    demonstrated_count: int
    evidence: list[str]


class SkillTreeResponse(BaseModel):
    soul_id: str
    rank: str
    branches: list[SkillBranch]


def build_skill_tree(soul_id: str, rank: str, project_path: Path) -> SkillTreeResponse:
    """Derive skill branches from SOUL specialty + growth-log keyword matching."""
    from golem_gateway.souls import get_soul_by_id  # local import to avoid circular

    soul = get_soul_by_id(project_path, soul_id)
    specialties: list[str] = []
    if soul is not None:
        raw_spec = soul.specialty  # type: ignore[attr-defined]
        if isinstance(raw_spec, list):
            specialties = [str(s) for s in raw_spec]
        elif isinstance(raw_spec, str):
            # comma-separated string fallback
            specialties = [s.strip() for s in raw_spec.split(",") if s.strip()]

    golem_dir = project_path / ".golem"
    entries = _cached_load_growth_log(soul_id, golem_dir)
    entries_sorted = sorted(entries, key=lambda e: _parse_ts(e), reverse=True)

    branches: list[SkillBranch] = []
    for keyword in specialties:
        kw_lower = keyword.lower()
        matches = [
            str(e.get("task") or "")
            for e in entries_sorted
            if kw_lower in str(e.get("task") or "").lower()
        ]
        count = len(matches)
        level = min(5, int(_math.floor(_math.log2(count + 1))))
        branches.append(SkillBranch(
            name=keyword,
            level=level,
            demonstrated_count=count,
            evidence=matches[:3],
        ))

    return SkillTreeResponse(soul_id=soul_id, rank=rank, branches=branches)
