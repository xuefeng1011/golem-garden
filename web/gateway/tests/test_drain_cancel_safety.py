"""Drain finally의 cancellation-safety 회귀 테스트 (Phase A 라이브 발견 버그).

SSE 제너레이터는 정상 종료/disconnect 시 terminate_run 으로 drain task 를
cancel 한다. 수정 전에는 finally 안의 `await proc.wait()` 에서 CancelledError
가 재발생해 on_terminal/persist_run/done.set 이 통째로 스킵됐다 — 구독자가
있는 모든 런에서 growth-log·트래젝토리가 누락된 원인.

이 테스트는 terminal 이벤트 직후 drain task 를 cancel 해 그 경합을 재현하고,
부기(트래젝토리 영속화 + done.set)가 그래도 완료됨을 단언한다.
"""

from __future__ import annotations

import asyncio
import time
from pathlib import Path

import pytest

from golem_gateway.session_manager import Run, SessionManager


_RESULT_LINE = (
    b'{"type":"result","subtype":"success","duration_ms":5,"is_error":false,'
    b'"usage":{"input_tokens":1,"output_tokens":2}}\n'
)


class _FakeStdout:
    """결과 라인 1줄 내고 EOF — 실제 claude stdout 의 최소 미러."""

    def __init__(self) -> None:
        self._lines = [_RESULT_LINE]

    def __aiter__(self):
        return self

    async def __anext__(self) -> bytes:
        if self._lines:
            return self._lines.pop(0)
        raise StopAsyncIteration


class _FakeProc:
    """wait() 가 cancel 될 때까지 행 — terminate_run 의 cancel 경합 재현용."""

    def __init__(self) -> None:
        self.stdout = _FakeStdout()
        self.returncode: int | None = 0
        self._never = asyncio.Event()

    async def wait(self) -> int:
        # drain finally 가 여기서 대기하는 동안 테스트가 task.cancel() 한다.
        await self._never.wait()
        return 0  # pragma: no cover — cancel 로만 빠져나감


@pytest.mark.asyncio
async def test_cancel_during_finally_still_persists(tmp_path: Path) -> None:
    runs_dir = tmp_path / ".golem" / "runs"

    run = Run(
        run_id="11111111-2222-4333-8444-555555555555",
        session_id="aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        soul_id="zen",
        project_id="proj-test",
        proc=_FakeProc(),  # type: ignore[arg-type]
        queue=asyncio.Queue(maxsize=10),
        done=asyncio.Event(),
        started_at=time.monotonic(),
        ts_start_iso="2026-06-12T00:00:00+00:00",
        project_path=tmp_path,
    )

    mgr = SessionManager()
    drain = asyncio.create_task(mgr._drain_stdout(run))

    # terminal 이벤트가 큐에 들어올 때까지 대기 (drain 은 이후 finally 의
    # proc.wait() 에서 행 상태) → SSE 제너레이터의 terminate_run 타이밍 재현
    ev = await asyncio.wait_for(run.queue.get(), timeout=5)
    assert ev.event == "run.completed"

    drain.cancel()
    # 수정 후: cancel 을 흡수하고 부기를 끝까지 수행한 뒤 정상 종료해야 한다
    await asyncio.wait_for(drain, timeout=5)

    assert run.done.is_set(), "done.set() 미실행 — 부기 스킵 회귀"
    jsonl = runs_dir / f"{run.run_id}.jsonl"
    meta = runs_dir / f"{run.run_id}.meta.json"
    assert jsonl.exists(), "트래젝토리 jsonl 미보존 — cancel 경합 회귀"
    assert meta.exists(), "meta 사이드카 미보존 — cancel 경합 회귀"
