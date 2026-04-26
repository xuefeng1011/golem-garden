"""Smoke test for sessions_db.SessionStore — no subprocess required.

Run with:
    cd web/gateway && python -m uv run python samples/p7-sessions-smoke.py
"""

import os
from pathlib import Path
import tempfile

from golem_gateway.sessions_db import (
    CURRENT_SCHEMA_VERSION,
    SessionStore,
    evict_session_store,
)


def main() -> None:
    with tempfile.TemporaryDirectory() as t:
        store = SessionStore(Path(t))

        # --- upsert + messages ---
        store.upsert_session(session_id="s1", soul_id="ryn")
        store.add_message(session_id="s1", role="user", content="hello world")
        store.add_message(session_id="s1", role="assistant", content="hi there", soul_id="ryn")

        # list_sessions
        sessions = store.list_sessions()
        assert len(sessions) == 1, f"expected 1 session, got {sessions}"
        s = sessions[0]
        assert s.id == "s1"
        assert s.soul_id == "ryn"
        assert s.title == "hello world", f"unexpected title: {s.title!r}"
        assert s.message_count == 2, f"expected 2 messages, got {s.message_count}"

        # get_session (detail)
        detail = store.get_session("s1")
        assert detail is not None
        assert len(detail.messages) == 2, f"expected 2 messages, got {len(detail.messages)}"
        assert detail.messages[0].role == "user"
        assert detail.messages[1].role == "assistant"
        assert detail.messages[1].soul_id == "ryn"

        # get_session missing
        assert store.get_session("nonexistent") is None

        # delete
        assert store.delete_session("s1") is True
        assert store.delete_session("s1") is False  # already gone
        assert store.list_sessions() == []

        # title truncation: first 60 chars of a long user message
        store.upsert_session(session_id="s2", soul_id=None)
        long_msg = "x" * 100
        store.add_message(session_id="s2", role="user", content=long_msg)
        detail2 = store.get_session("s2")
        assert detail2 is not None
        assert len(detail2.title) == 60, f"title not truncated: {len(detail2.title)}"

        # title not overwritten by second user message
        store.add_message(session_id="s2", role="user", content="second message")
        detail3 = store.get_session("s2")
        assert detail3 is not None
        assert detail3.title == "x" * 60, f"title was overwritten: {detail3.title!r}"

        # upsert again touches updated_at without resetting title
        store.upsert_session(session_id="s2", soul_id="zen")
        detail4 = store.get_session("s2")
        assert detail4 is not None
        assert detail4.soul_id == "zen"
        assert detail4.title == "x" * 60

        # ------------------------------------------------------------------
        # Zen F2: FK + WAL + schema_version
        # ------------------------------------------------------------------
        with store._connect() as conn:
            fk = conn.execute("PRAGMA foreign_keys").fetchone()[0]
            assert fk == 1, f"expected foreign_keys=1, got {fk}"
            jm = conn.execute("PRAGMA journal_mode").fetchone()[0]
            assert str(jm).lower() == "wal", f"expected journal_mode=wal, got {jm}"
            ver = conn.execute("SELECT version FROM schema_version").fetchone()[0]
            assert ver == CURRENT_SCHEMA_VERSION, (
                f"expected schema_version={CURRENT_SCHEMA_VERSION}, got {ver}"
            )

        # Zen M3: cache eviction is callable + idempotent (no-op for unknown).
        evict_session_store(Path(t))
        evict_session_store(Path(t) / "does-not-exist")

        # Zen M2: batch insert in one transaction.
        store.upsert_session(session_id="s3", soul_id="ryn")
        store.add_messages_batch(
            session_id="s3",
            messages=[
                {"role": "user", "content": "ping"},
                {"role": "assistant", "content": "pong", "soul_id": "ryn"},
                {"role": "tool", "content": "Bash", "soul_id": "ryn"},
            ],
        )
        d3 = store.get_session("s3")
        assert d3 is not None
        assert d3.message_count == 3, f"expected 3, got {d3.message_count}"
        assert d3.title == "ping", f"unexpected title: {d3.title!r}"
        assert [m.role for m in d3.messages] == ["user", "assistant", "tool"]

    # ------------------------------------------------------------------
    # Zen F1: registry path validation (lazy import — avoids module load
    # cost when the user only wants the SessionStore smoke).
    # ------------------------------------------------------------------
    os.environ.pop("GOLEM_EXTRA_PROJECT_ROOTS", None)
    from golem_gateway.registry import _validate_project_path

    # Always-rejected: non-existent path.
    try:
        _validate_project_path("Z:/definitely/does/not/exist")
        raise AssertionError("F1: should have rejected non-existent path")
    except ValueError:
        pass

    # System path is rejected when not in home and no allowlist.
    sys_root = "C:/Windows" if os.name == "nt" else "/etc"
    if Path(sys_root).is_dir():
        try:
            home_resolved = Path.home().resolve()
            sys_resolved = Path(sys_root).resolve()
            try:
                sys_resolved.relative_to(home_resolved)
                in_home = True
            except ValueError:
                in_home = False
            if not in_home:
                try:
                    _validate_project_path(sys_root)
                    raise AssertionError(
                        f"F1: should have rejected {sys_root} without allowlist"
                    )
                except ValueError:
                    pass  # expected
        except OSError:
            pass

    # Home directory itself is always accepted.
    home_path = str(Path.home())
    resolved = _validate_project_path(home_path)
    assert resolved == Path.home().resolve()

    # Allowlist escape hatch lets a non-home root through.
    if Path(sys_root).is_dir():
        os.environ["GOLEM_EXTRA_PROJECT_ROOTS"] = sys_root
        try:
            r = _validate_project_path(sys_root)
            assert r == Path(sys_root).resolve()
        finally:
            os.environ.pop("GOLEM_EXTRA_PROJECT_ROOTS", None)

    print("OK")


if __name__ == "__main__":
    main()
