"""Tests for golem_gateway.sessions_db — schema, message counts, batch, delete."""

from __future__ import annotations

from pathlib import Path

import pytest

from golem_gateway.sessions_db import SessionStore, evict_session_store, get_session_store


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def make_store(tmp_path: Path) -> SessionStore:
    return SessionStore(tmp_path)


# ---------------------------------------------------------------------------
# TestSchema
# ---------------------------------------------------------------------------


class TestSchema:
    def test_init_creates_tables_and_version(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        with store._connect() as conn:
            tables = {
                row[0]
                for row in conn.execute(
                    "SELECT name FROM sqlite_master WHERE type='table'"
                ).fetchall()
            }
        assert "sessions" in tables
        assert "messages" in tables
        assert "schema_version" in tables

    def test_schema_version_seeded(self, tmp_path: Path) -> None:
        from golem_gateway.sessions_db import CURRENT_SCHEMA_VERSION
        store = make_store(tmp_path)
        with store._connect() as conn:
            row = conn.execute("SELECT version FROM schema_version LIMIT 1").fetchone()
        assert row is not None
        assert row[0] == CURRENT_SCHEMA_VERSION

    def test_pragma_foreign_keys_enabled(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        with store._connect() as conn:
            cur = conn.execute("PRAGMA foreign_keys")
            assert cur.fetchone()[0] == 1

    def test_pragma_journal_mode_wal(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        with store._connect() as conn:
            cur = conn.execute("PRAGMA journal_mode")
            assert cur.fetchone()[0].lower() == "wal"


# ---------------------------------------------------------------------------
# TestMessageCount
# ---------------------------------------------------------------------------


class TestMessageCount:
    def test_total_count_includes_system_marker(self, tmp_path: Path) -> None:
        """get_message_count must include system role rows (F1)."""
        store = make_store(tmp_path)
        sid = "sess-count-1"
        store.upsert_session(session_id=sid, soul_id=None)
        store.add_message(session_id=sid, role="user", content="hello")
        store.add_message(session_id=sid, role="system", content="spawn-failure-marker")
        assert store.get_message_count(sid) == 2

    def test_user_assistant_count_excludes_system(self, tmp_path: Path) -> None:
        """get_user_assistant_count must NOT count system rows."""
        store = make_store(tmp_path)
        sid = "sess-count-2"
        store.upsert_session(session_id=sid, soul_id=None)
        store.add_message(session_id=sid, role="user", content="hello")
        store.add_message(session_id=sid, role="system", content="marker")
        assert store.get_user_assistant_count(sid) == 1
        assert store.get_message_count(sid) == 2

    def test_user_assistant_count_excludes_tool(self, tmp_path: Path) -> None:
        """tool role must not appear in get_user_assistant_count."""
        store = make_store(tmp_path)
        sid = "sess-count-3"
        store.upsert_session(session_id=sid, soul_id=None)
        store.add_message(session_id=sid, role="user", content="q")
        store.add_message(session_id=sid, role="assistant", content="a")
        store.add_message(session_id=sid, role="tool", content="tool-log")
        assert store.get_user_assistant_count(sid) == 2
        assert store.get_message_count(sid) == 3

    def test_count_returns_zero_for_unknown_session(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        assert store.get_message_count("unknown") == 0
        assert store.get_user_assistant_count("unknown") == 0


# ---------------------------------------------------------------------------
# TestBatchInsert
# ---------------------------------------------------------------------------


class TestBatchInsert:
    def test_add_messages_batch_atomic(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        sid = "sess-batch-1"
        store.upsert_session(session_id=sid, soul_id="ryn")
        msgs = [
            {"role": "user", "content": "msg1"},
            {"role": "assistant", "content": "reply1"},
            {"role": "tool", "content": "tool-log"},
        ]
        store.add_messages_batch(session_id=sid, messages=msgs)
        assert store.get_message_count(sid) == 3
        assert store.get_user_assistant_count(sid) == 2

    def test_batch_updates_updated_at(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        sid = "sess-batch-2"
        store.upsert_session(session_id=sid, soul_id=None)
        detail_before = store.get_session(sid)
        assert detail_before is not None
        updated_before = detail_before.updated_at

        store.add_messages_batch(
            session_id=sid,
            messages=[{"role": "user", "content": "x"}],
        )
        detail_after = store.get_session(sid)
        assert detail_after is not None
        # updated_at should be >= the original value (same second is acceptable)
        assert detail_after.updated_at >= updated_before

    def test_batch_empty_is_noop(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        sid = "sess-batch-3"
        store.upsert_session(session_id=sid, soul_id=None)
        store.add_messages_batch(session_id=sid, messages=[])
        assert store.get_message_count(sid) == 0

    def test_batch_sets_title_from_first_user_message(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        sid = "sess-batch-title"
        store.upsert_session(session_id=sid, soul_id=None)
        store.add_messages_batch(
            session_id=sid,
            messages=[
                {"role": "user", "content": "What is the capital of France?"},
                {"role": "assistant", "content": "Paris."},
            ],
        )
        detail = store.get_session(sid)
        assert detail is not None
        assert detail.title == "What is the capital of France?"


# ---------------------------------------------------------------------------
# TestDeleteSession
# ---------------------------------------------------------------------------


class TestDeleteSession:
    def test_delete_cascades_messages(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        sid = "sess-del-1"
        store.upsert_session(session_id=sid, soul_id=None)
        store.add_message(session_id=sid, role="user", content="bye")
        store.add_message(session_id=sid, role="assistant", content="goodbye")

        deleted = store.delete_session(sid)
        assert deleted is True

        # Session gone
        assert store.get_session(sid) is None
        # Messages gone too
        with store._connect() as conn:
            count = conn.execute(
                "SELECT COUNT(*) FROM messages WHERE session_id = ?", (sid,)
            ).fetchone()[0]
        assert count == 0

    def test_delete_returns_false_for_unknown(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        assert store.delete_session("no-such-session") is False

    def test_evict_session_store_clears_cache(self, tmp_path: Path) -> None:
        """evict_session_store must remove the cached instance for the path."""
        key = tmp_path.resolve()
        s1 = get_session_store(tmp_path)
        # Same path → same cached instance
        s2 = get_session_store(tmp_path)
        assert s1 is s2

        evict_session_store(tmp_path)
        # After eviction, a new instance is returned
        s3 = get_session_store(tmp_path)
        assert s3 is not s1


# ---------------------------------------------------------------------------
# TestUpsertSession
# ---------------------------------------------------------------------------


class TestUpsertSession:
    def test_upsert_creates_new_row(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        sid = "sess-upsert-1"
        store.upsert_session(session_id=sid, soul_id="ryn")
        detail = store.get_session(sid)
        assert detail is not None
        assert detail.soul_id == "ryn"

    def test_upsert_is_idempotent(self, tmp_path: Path) -> None:
        store = make_store(tmp_path)
        sid = "sess-upsert-2"
        store.upsert_session(session_id=sid, soul_id="ryn")
        store.add_message(session_id=sid, role="user", content="hello")
        # Second upsert should not lose the message_count
        store.upsert_session(session_id=sid, soul_id="kai")
        assert store.get_message_count(sid) == 1
