"""Contract tests: stream-json thinking blocks → ThinkingDeltaEvent.

Sample shapes verified against a live `claude --print --output-format
stream-json --verbose --model sonnet` run (2026-06-12):

    {"type":"assistant","message":{"model":"claude-sonnet-4-6","id":"msg_...",
     "type":"message","role":"assistant","content":[
        {"type":"thinking","thinking":"The user is asking ...","signature":"..."}
     ]}, ...}
"""

from __future__ import annotations

import json

from golem_gateway.events import (
    MessageDeltaEvent,
    RunContext,
    ThinkingDeltaEvent,
    parse_stream_event,
)

CTX = RunContext(run_id="run-1", session_id="sess-1")


def _assistant_line(content: list[dict]) -> dict:
    """Wrap content blocks in the real stream-json assistant envelope."""
    return {
        "type": "assistant",
        "message": {
            "model": "claude-sonnet-4-6",
            "id": "msg_01BnMQ3pP6frD9fXPkLvWifp",
            "type": "message",
            "role": "assistant",
            "content": content,
        },
    }


def test_thinking_block_produces_thinking_event() -> None:
    raw = _assistant_line(
        [
            {
                "type": "thinking",
                "thinking": "The user is asking me to think deeply about 1+1.",
                "signature": "EqMBCkYIChABGAI=",
            }
        ]
    )

    events = parse_stream_event(raw, context=CTX)

    assert len(events) == 1
    ev = events[0]
    assert isinstance(ev, ThinkingDeltaEvent)
    assert ev.event == "message.thinking"
    assert ev.run_id == "run-1"
    assert ev.session_id == "sess-1"
    assert ev.text == "The user is asking me to think deeply about 1+1."


def test_thinking_event_sse_payload_shape() -> None:
    """model_dump_json must carry event/run_id/session_id/text — the SSE contract."""
    raw = _assistant_line([{"type": "thinking", "thinking": "deep thought"}])

    events = parse_stream_event(raw, context=CTX)
    payload = json.loads(events[0].model_dump_json())

    assert payload == {
        "event": "message.thinking",
        "run_id": "run-1",
        "session_id": "sess-1",
        "text": "deep thought",
    }


def test_mixed_thinking_then_text_blocks_keep_order() -> None:
    raw = _assistant_line(
        [
            {"type": "thinking", "thinking": "let me reason", "signature": "x"},
            {"type": "text", "text": "the answer is 2"},
        ]
    )

    events = parse_stream_event(raw, context=CTX)

    assert len(events) == 2
    assert isinstance(events[0], ThinkingDeltaEvent)
    assert isinstance(events[1], MessageDeltaEvent)
    assert events[0].text == "let me reason"
    assert events[1].text == "the answer is 2"


def test_empty_thinking_block_is_skipped() -> None:
    raw = _assistant_line([{"type": "thinking", "thinking": ""}])
    assert parse_stream_event(raw, context=CTX) == []


def test_thinking_block_missing_field_is_skipped() -> None:
    raw = _assistant_line([{"type": "thinking", "signature": "only-sig"}])
    assert parse_stream_event(raw, context=CTX) == []
