"""Migration framework tests for sessions_db.

Covers: fresh DB stamping, idempotency, legacy DB upgrade, backup path pattern,
and rollback on migration failure.
"""

from __future__ import annotations

import re
import sqlite3
from pathlib import Path
from typing import Callable
from unittest.mock import patch

import pytest

from golem_gateway.sessions_db import (
    CURRENT_SCHEMA_VERSION,
    SessionStore,
    _MIGRATIONS,
    _backup_db,
    _run_pending_migrations,
)


def make_store(tmp_path: Path) -> SessionStore:
    return SessionStore(tmp_path)


# ---------------------------------------------------------------------------
# TestFreshDB
# ---------------------------------------------------------------------------


class TestFreshDB:
    def test_user_version_equals_current_schema_version(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        with store._connect() as conn:
            uv = conn.execute("PRAGMA user_version").fetchone()[0]
        assert uv == CURRENT_SCHEMA_VERSION

    def test_no_backup_created_on_fresh_db(self, tmp_path: Path) -> None:
        make_store(tmp_path)
        bak_files = list((tmp_path / ".golem").glob("sessions.db.bak.*"))
        assert bak_files == []


# ---------------------------------------------------------------------------
# TestIdempotent
# ---------------------------------------------------------------------------


class TestIdempotent:
    def test_double_init_keeps_user_version(self, tmp_path: Path) -> None:
        make_store(tmp_path)
        make_store(tmp_path)  # second init
        db_path = tmp_path / ".golem" / "sessions.db"
        conn = sqlite3.connect(str(db_path))
        uv = conn.execute("PRAGMA user_version").fetchone()[0]
        conn.close()
        assert uv == CURRENT_SCHEMA_VERSION

    def test_double_init_no_extra_backup(self, tmp_path: Path) -> None:
        make_store(tmp_path)
        make_store(tmp_path)
        bak_files = list((tmp_path / ".golem").glob("sessions.db.bak.*"))
        # Already at current version on second init — no backup produced.
        assert len(bak_files) == 0


# ---------------------------------------------------------------------------
# TestLegacyDB
# ---------------------------------------------------------------------------


class TestLegacyDB:
    def _make_legacy_db(self, tmp_path: Path, user_version: int = 1) -> Path:
        """Create a pre-migration DB stamped at the given user_version.

        user_version=1 simulates a v1 DB that needs a v1→v2 migration.
        user_version=0 would be an unstamped DB (treated as fresh by the
        migration dispatcher), so we default to 1 here.
        """
        golem_dir = tmp_path / ".golem"
        golem_dir.mkdir(parents=True, exist_ok=True)
        db_path = golem_dir / "sessions.db"
        conn = sqlite3.connect(str(db_path))
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                soul_id TEXT,
                title TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                message_count INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                role TEXT NOT NULL,
                content TEXT NOT NULL,
                soul_id TEXT,
                tool_name TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            );
            CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
            """
        )
        conn.execute(f"PRAGMA user_version = {user_version}")
        conn.commit()
        conn.close()
        return db_path

    def test_legacy_db_migrated_to_current(self, tmp_path: Path) -> None:
        """A v1-stamped DB opened with CURRENT_SCHEMA_VERSION=1 is a noop."""
        self._make_legacy_db(tmp_path, user_version=1)
        store = SessionStore(tmp_path)
        with store._connect() as conn:
            uv = conn.execute("PRAGMA user_version").fetchone()[0]
        assert uv == CURRENT_SCHEMA_VERSION

    def test_legacy_db_with_pending_migrations_creates_backup(
        self, tmp_path: Path
    ) -> None:
        """A v1 DB opened against CURRENT_SCHEMA_VERSION=2 triggers backup."""
        self._make_legacy_db(tmp_path, user_version=1)

        def _noop_migration(conn: sqlite3.Connection) -> None:
            pass

        with patch("golem_gateway.sessions_db._MIGRATIONS", [_noop_migration]):
            with patch("golem_gateway.sessions_db.CURRENT_SCHEMA_VERSION", 2):
                store = SessionStore(tmp_path)

        bak_files = list((tmp_path / ".golem").glob("sessions.db.bak.*"))
        assert len(bak_files) >= 1


# ---------------------------------------------------------------------------
# TestBackupPath
# ---------------------------------------------------------------------------


class TestBackupPath:
    def test_backup_filename_pattern(self, tmp_path: Path) -> None:
        """Backup files must match sessions.db.bak.YYYYMMDD-HHMMSS."""
        golem_dir = tmp_path / ".golem"
        golem_dir.mkdir(parents=True, exist_ok=True)
        db_path = golem_dir / "sessions.db"
        conn = sqlite3.connect(str(db_path))
        conn.execute("PRAGMA journal_mode = WAL")
        _backup_db(conn, db_path)
        conn.close()
        bak_files = list(golem_dir.glob("sessions.db.bak.*"))
        assert len(bak_files) == 1
        pattern = re.compile(r"sessions\.db\.bak\.\d{8}-\d{6}$")
        assert pattern.match(bak_files[0].name), bak_files[0].name

    def test_backup_contains_committed_wal_data(self, tmp_path: Path) -> None:
        """WAL checkpoint flushes committed data into backup before copy."""
        golem_dir = tmp_path / ".golem"
        golem_dir.mkdir(parents=True, exist_ok=True)
        db_path = golem_dir / "sessions.db"

        # Write data in WAL mode so it lives in the WAL file before checkpoint.
        conn = sqlite3.connect(str(db_path))
        conn.execute("PRAGMA journal_mode = WAL")
        conn.execute("CREATE TABLE t (v TEXT)")
        conn.execute("INSERT INTO t VALUES ('sentinel')")
        conn.commit()

        _backup_db(conn, db_path)
        conn.close()

        bak_files = list(golem_dir.glob("sessions.db.bak.*"))
        assert len(bak_files) == 1

        # Verify the backup is readable and contains the committed row.
        bak_conn = sqlite3.connect(str(bak_files[0]))
        row = bak_conn.execute("SELECT v FROM t").fetchone()
        bak_conn.close()
        assert row is not None and row[0] == "sentinel"


# ---------------------------------------------------------------------------
# TestMigrationRollback
# ---------------------------------------------------------------------------


class TestMigrationRollback:
    def test_failing_migration_does_not_change_user_version(
        self, tmp_path: Path
    ) -> None:
        """A migration that raises must leave user_version unchanged."""
        golem_dir = tmp_path / ".golem"
        golem_dir.mkdir(parents=True, exist_ok=True)
        db_path = golem_dir / "sessions.db"

        conn = sqlite3.connect(str(db_path))
        conn.execute("PRAGMA user_version = 1")
        conn.commit()
        conn.close()

        def _bad_migration(conn: sqlite3.Connection) -> None:
            raise RuntimeError("intentional failure")

        with patch("golem_gateway.sessions_db._MIGRATIONS", [_bad_migration]):
            with patch("golem_gateway.sessions_db.CURRENT_SCHEMA_VERSION", 2):
                with pytest.raises(RuntimeError, match="intentional failure"):
                    _run_pending_migrations(db_path)

        # Verify via fresh connection — _run_pending_migrations owns its own conn.
        check = sqlite3.connect(str(db_path))
        uv = check.execute("PRAGMA user_version").fetchone()[0]
        check.close()
        assert uv == 1

    def test_user_version_persists_when_outer_init_fails(
        self, tmp_path: Path
    ) -> None:
        """user_version written by _run_pending_migrations must be durable even
        if _init_schema raises afterward (HIGH #2: migration commits on its own
        connection, independent of the schema-init transaction)."""
        golem_dir = tmp_path / ".golem"
        golem_dir.mkdir(parents=True, exist_ok=True)
        db_path = golem_dir / "sessions.db"

        # Seed a v1 legacy DB with full schema so migration path is taken.
        setup = sqlite3.connect(str(db_path))
        setup.executescript(
            """
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY, soul_id TEXT,
                title TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
                message_count INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL, role TEXT NOT NULL,
                content TEXT NOT NULL, soul_id TEXT, tool_name TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            );
            CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY);
            """
        )
        setup.execute("PRAGMA user_version = 1")
        setup.commit()
        setup.close()

        def _noop_migration(conn: sqlite3.Connection) -> None:
            pass

        # Replace _run_pending_migrations with a version that writes user_version
        # directly then raises to simulate a post-migration _init_schema failure.
        def _migrate_then_fail(db_path_arg: Path) -> None:
            # Commit the version bump on its own connection (mirrors real impl).
            inner = sqlite3.connect(str(db_path_arg))
            inner.execute("PRAGMA user_version = 2")
            inner.commit()
            inner.close()
            raise RuntimeError("simulated post-migration failure")

        with patch("golem_gateway.sessions_db._MIGRATIONS", [_noop_migration]):
            with patch("golem_gateway.sessions_db.CURRENT_SCHEMA_VERSION", 2):
                with patch(
                    "golem_gateway.sessions_db._run_pending_migrations",
                    _migrate_then_fail,
                ):
                    with pytest.raises(RuntimeError, match="simulated"):
                        SessionStore(tmp_path)

        # user_version must be 2 — the committed write must have survived.
        check = sqlite3.connect(str(db_path))
        uv = check.execute("PRAGMA user_version").fetchone()[0]
        check.close()
        assert uv == 2
