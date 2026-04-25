"""SQLite-backed session store.

One SessionStore per project_path.  Use get_session_store() to obtain a cached
instance — do not instantiate directly in endpoint code.

Concurrency model: each public method opens and closes its own sqlite3
connection (open-per-call).  This avoids cross-thread / cross-async-task
sharing issues with FastAPI's thread pool.  sqlite3 WAL mode is not set here
because the default journal mode is sufficient for the low write volume of an
MVP.
"""

from __future__ import annotations

import sqlite3
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator

from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------


class SessionSummary(BaseModel):
    id: str
    soul_id: str | None
    title: str
    created_at: str
    updated_at: str
    message_count: int


class SessionMessage(BaseModel):
    id: int
    role: str
    content: str
    soul_id: str | None = None
    tool_name: str | None = None
    created_at: str


class SessionDetail(SessionSummary):
    messages: list[SessionMessage]


# ---------------------------------------------------------------------------
# Module-level cache: Path -> SessionStore
# ---------------------------------------------------------------------------

_store_cache: dict[Path, "SessionStore"] = {}
_cache_lock = threading.Lock()


def get_session_store(project_path: Path) -> "SessionStore":
    """Return a cached SessionStore for the given project path.

    Thread-safe via a module-level lock.  The resolved path is used as the
    cache key so that relative-path aliases collapse to the same entry.
    """
    key = project_path.resolve()
    with _cache_lock:
        if key not in _store_cache:
            _store_cache[key] = SessionStore(key)
        return _store_cache[key]


def evict_session_store(project_path: Path) -> None:
    """Drop the cached SessionStore for the given project, if any.

    Zen M3: must be called when a project is deleted so the cache does not
    pin a now-orphaned ``sessions.db`` connection (and so a re-registered
    project at the same path gets a fresh store).
    """
    try:
        canonical = project_path.resolve()
    except OSError:
        return
    with _cache_lock:
        _store_cache.pop(canonical, None)


# ---------------------------------------------------------------------------
# DDL
# ---------------------------------------------------------------------------

_SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS sessions (
    id              TEXT PRIMARY KEY,
    soul_id         TEXT,
    title           TEXT NOT NULL DEFAULT '',
    created_at      TEXT NOT NULL,
    updated_at      TEXT NOT NULL,
    message_count   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS messages (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT NOT NULL,
    role        TEXT NOT NULL,
    content     TEXT NOT NULL,
    soul_id     TEXT,
    tool_name   TEXT,
    created_at  TEXT NOT NULL,
    FOREIGN KEY (session_id) REFERENCES sessions(id)
);

CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY
);

CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id, id);
CREATE INDEX IF NOT EXISTS idx_sessions_updated ON sessions(updated_at DESC);
"""

# Bumped on every schema migration. Existing DBs are not migrated automatically
# yet; future migrations will compare CURRENT_SCHEMA_VERSION to the row in
# schema_version and apply the necessary ALTERs.
# TODO(v0.5): introduce ON DELETE CASCADE for messages.session_id (requires
# table redefine + migration). For now delete_session() does the cascade
# manually.
CURRENT_SCHEMA_VERSION: int = 1


# ---------------------------------------------------------------------------
# SessionStore
# ---------------------------------------------------------------------------


class SessionStore:
    """Project-scoped SQLite session store.  One instance per project_path."""

    def __init__(self, project_path: Path) -> None:
        self.db_path = project_path / ".golem" / "sessions.db"
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @contextmanager
    def _connect(self) -> Iterator[sqlite3.Connection]:
        """Open a connection, yield it, then always close it.

        Uses sqlite3's own context manager for commit/rollback, then closes
        explicitly so the file handle is released (important on Windows).

        Zen F2: enable foreign-key enforcement and WAL journal mode on every
        connection.  PRAGMA foreign_keys is a per-connection setting; PRAGMA
        journal_mode persists in the DB file but is harmless to re-set.
        """
        conn = sqlite3.connect(str(self.db_path))
        conn.text_factory = str
        conn.row_factory = sqlite3.Row
        # Per-connection FK enforcement (sqlite3 default is OFF).
        conn.execute("PRAGMA foreign_keys = ON")
        # WAL improves read concurrency; persisted in the DB file once set.
        conn.execute("PRAGMA journal_mode = WAL")
        try:
            with conn:
                yield conn
        finally:
            conn.close()

    def _init_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript(_SCHEMA_SQL)
            # Seed schema_version on a brand-new DB.  Once seeded the row is
            # left alone here; future migrations will UPDATE it explicitly.
            row = conn.execute(
                "SELECT version FROM schema_version LIMIT 1"
            ).fetchone()
            if row is None:
                conn.execute(
                    "INSERT INTO schema_version (version) VALUES (?)",
                    (CURRENT_SCHEMA_VERSION,),
                )

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat(timespec="seconds")

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def upsert_session(self, *, session_id: str, soul_id: str | None) -> None:
        """Create the session row if new; otherwise touch updated_at + soul_id."""
        now = self._now()
        with self._connect() as conn:
            # Try insert first (new session).
            conn.execute(
                """
                INSERT INTO sessions (id, soul_id, title, created_at, updated_at, message_count)
                VALUES (?, ?, '', ?, ?, 0)
                ON CONFLICT(id) DO UPDATE SET
                    soul_id   = excluded.soul_id,
                    updated_at = excluded.updated_at
                """,
                (session_id, soul_id, now, now),
            )

    def add_message(
        self,
        *,
        session_id: str,
        role: str,
        content: str,
        soul_id: str | None = None,
        tool_name: str | None = None,
    ) -> None:
        """Append a message row and update session.message_count + updated_at.

        If this is the first user message, also sets session.title to the
        first 60 chars of content.
        """
        now = self._now()
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO messages (session_id, role, content, soul_id, tool_name, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (session_id, role, content, soul_id, tool_name, now),
            )
            conn.execute(
                """
                UPDATE sessions
                SET message_count = message_count + 1,
                    updated_at    = ?
                WHERE id = ?
                """,
                (now, session_id),
            )
            # Set title from first user message (only when title is still empty).
            if role == "user":
                title = content.strip()[:60]
                conn.execute(
                    """
                    UPDATE sessions
                    SET title = ?
                    WHERE id = ? AND title = ''
                    """,
                    (title, session_id),
                )

    def add_messages_batch(
        self,
        *,
        session_id: str,
        messages: list[dict],
    ) -> None:
        """Append multiple messages in a single transaction.

        Each dict must have keys: role, content; optional: soul_id, tool_name.
        Updates session.message_count + updated_at exactly once at the end.
        Title behaviour matches add_message(): set from the first user message
        whose session.title is still empty.

        Zen M2: avoid N round-trips per assistant turn (assistant + tool log).
        """
        if not messages:
            return
        now = self._now()
        with self._connect() as conn:
            for msg in messages:
                conn.execute(
                    """
                    INSERT INTO messages (session_id, role, content, soul_id, tool_name, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (
                        session_id,
                        msg["role"],
                        msg["content"],
                        msg.get("soul_id"),
                        msg.get("tool_name"),
                        now,
                    ),
                )
                if msg["role"] == "user":
                    title = str(msg["content"]).strip()[:60]
                    conn.execute(
                        """
                        UPDATE sessions
                        SET title = ?
                        WHERE id = ? AND title = ''
                        """,
                        (title, session_id),
                    )
            conn.execute(
                """
                UPDATE sessions
                SET message_count = message_count + ?,
                    updated_at    = ?
                WHERE id = ?
                """,
                (len(messages), now, session_id),
            )

    def get_message_count(self, session_id: str) -> int:
        """Return the persisted message_count for a session, or 0 if unknown.

        Used by the API and UI for display purposes (badge counts, etc.).
        Includes all rows regardless of role.
        """
        with self._connect() as conn:
            cur = conn.execute(
                "SELECT message_count FROM sessions WHERE id = ?",
                (session_id,),
            )
            row = cur.fetchone()
            return int(row[0]) if row else 0

    def get_user_assistant_count(self, session_id: str) -> int:
        """Count only user+assistant messages for a session, or 0 if unknown.

        System markers (e.g. spawn-failure rows from F3) and tool messages
        are NOT counted, because they don't represent turns claude has actually
        seen. This prevents a poisoned --resume against a non-existent session
        when a prior spawn failure wrote a role="system" marker row.
        """
        with self._connect() as conn:
            cur = conn.execute(
                """
                SELECT COUNT(*) FROM messages
                WHERE session_id = ? AND role IN ('user', 'assistant')
                """,
                (session_id,),
            )
            row = cur.fetchone()
            return int(row[0]) if row else 0

    def list_all_session_ids(self) -> set[str]:
        """Return ALL session ids (no pagination cap). Used by GC.

        Avoids the trap where `list_sessions(limit=N)` quietly truncates
        when total exceeds N — which would cause GC to delete real sessions.
        """
        with self._connect() as conn:
            rows = conn.execute("SELECT id FROM sessions").fetchall()
        return {row["id"] for row in rows}

    def list_sessions(self, limit: int = 100) -> list[SessionSummary]:
        """Return sessions sorted by updated_at DESC."""
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id, soul_id, title, created_at, updated_at, message_count
                FROM sessions
                ORDER BY updated_at DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        return [
            SessionSummary(
                id=row["id"],
                soul_id=row["soul_id"],
                title=row["title"],
                created_at=row["created_at"],
                updated_at=row["updated_at"],
                message_count=row["message_count"],
            )
            for row in rows
        ]

    def get_session(self, session_id: str) -> SessionDetail | None:
        """Return full session detail with messages, or None if not found."""
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT id, soul_id, title, created_at, updated_at, message_count
                FROM sessions
                WHERE id = ?
                """,
                (session_id,),
            ).fetchone()
            if row is None:
                return None

            msg_rows = conn.execute(
                """
                SELECT id, role, content, soul_id, tool_name, created_at
                FROM messages
                WHERE session_id = ?
                ORDER BY id
                """,
                (session_id,),
            ).fetchall()

        messages = [
            SessionMessage(
                id=m["id"],
                role=m["role"],
                content=m["content"],
                soul_id=m["soul_id"],
                tool_name=m["tool_name"],
                created_at=m["created_at"],
            )
            for m in msg_rows
        ]
        return SessionDetail(
            id=row["id"],
            soul_id=row["soul_id"],
            title=row["title"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            message_count=row["message_count"],
            messages=messages,
        )

    def delete_session(self, session_id: str) -> bool:
        """Delete session and its messages.  Returns True if a row was deleted."""
        with self._connect() as conn:
            conn.execute("DELETE FROM messages WHERE session_id = ?", (session_id,))
            result = conn.execute(
                "DELETE FROM sessions WHERE id = ?", (session_id,)
            )
            return result.rowcount > 0
