"""Hermes-compatible event models and stream-json parser.

One raw stream-json line from `claude --output-format=stream-json` can produce
zero, one, or many HermesEvent instances.  The parser is intentionally
defensive: unknown types are logged at DEBUG and skipped; the caller never
crashes on unexpected shapes.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Any, Literal

from pydantic import BaseModel

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# RunContext — tiny value object threaded through the parser
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class RunContext:
    run_id: str
    session_id: str


# ---------------------------------------------------------------------------
# Base event
# ---------------------------------------------------------------------------

class HermesEvent(BaseModel):
    """Common envelope carried by every SSE event."""

    event: str  # discriminator string, e.g. "session.init"
    run_id: str
    session_id: str


# ---------------------------------------------------------------------------
# Concrete event types
# ---------------------------------------------------------------------------

class SessionInitEvent(HermesEvent):
    event: Literal["session.init"] = "session.init"
    model: str
    tools: list[str]
    cwd: str


class MessageDeltaEvent(HermesEvent):
    event: Literal["message.delta"] = "message.delta"
    role: Literal["assistant"] = "assistant"
    text: str


class ToolStartedEvent(HermesEvent):
    event: Literal["tool.started"] = "tool.started"
    tool_use_id: str
    tool_name: str
    input: dict[str, Any]


class ToolCompletedEvent(HermesEvent):
    event: Literal["tool.completed"] = "tool.completed"
    tool_use_id: str
    result: Any
    is_error: bool


class RunCompletedEvent(HermesEvent):
    event: Literal["run.completed"] = "run.completed"
    is_error: bool
    duration_ms: int
    total_cost_usd: float
    usage: dict[str, Any]


class RunFailedEvent(HermesEvent):
    event: Literal["run.failed"] = "run.failed"
    reason: str


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------

def parse_stream_event(raw: dict[str, Any], context: RunContext) -> list[HermesEvent]:
    """Map one stream-json dict to zero or more HermesEvent instances.

    Rules:
    - type=system, subtype=hook_started|hook_response  → ignored (noise)
    - type=system, subtype=init                        → SessionInitEvent
    - type=assistant (message with content blocks)     → MessageDeltaEvent / ToolStartedEvent per block
    - type=user (message with tool_result blocks)      → ToolCompletedEvent per block
    - type=result                                      → RunCompletedEvent
    - anything else                                    → DEBUG log, empty list
    """
    event_type: str = raw.get("type", "")
    subtype: str = raw.get("subtype", "")

    base = {"run_id": context.run_id, "session_id": context.session_id}

    # --- system events ---
    if event_type == "system":
        if subtype in ("hook_started", "hook_response"):
            # Intentionally ignored — these are golem hook lifecycle noise.
            return []

        if subtype == "init":
            return [
                SessionInitEvent(
                    **base,
                    model=str(raw.get("model", "")),
                    tools=_coerce_str_list(raw.get("tools")),
                    cwd=str(raw.get("cwd", "")),
                )
            ]

        logger.debug("parse_stream_event: unknown system subtype %r, skipping", subtype)
        return []

    # --- assistant message ---
    if event_type == "assistant":
        message: dict[str, Any] = raw.get("message") or {}
        content: list[Any] = message.get("content") or []
        events: list[HermesEvent] = []

        for block in content:
            if not isinstance(block, dict):
                continue
            block_type = block.get("type", "")

            if block_type == "text":
                text = str(block.get("text") or "")
                if text:
                    events.append(MessageDeltaEvent(**base, text=text))

            elif block_type == "tool_use":
                events.append(
                    ToolStartedEvent(
                        **base,
                        tool_use_id=str(block.get("id") or ""),
                        tool_name=str(block.get("name") or ""),
                        input=block.get("input") or {},
                    )
                )

            else:
                logger.debug(
                    "parse_stream_event: unknown assistant content block type %r, skipping",
                    block_type,
                )

        return events

    # --- user message (tool results flowing back) ---
    if event_type == "user":
        message = raw.get("message") or {}
        content = message.get("content") or []
        events = []

        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") != "tool_result":
                continue

            raw_content = block.get("content")
            result_text: Any
            if isinstance(raw_content, list):
                # Extract text from content blocks if present
                texts = [
                    b.get("text", "")
                    for b in raw_content
                    if isinstance(b, dict) and b.get("type") == "text"
                ]
                result_text = "\n".join(texts) if texts else raw_content
            else:
                result_text = raw_content

            events.append(
                ToolCompletedEvent(
                    **base,
                    tool_use_id=str(block.get("tool_use_id") or ""),
                    result=result_text,
                    is_error=bool(block.get("is_error", False)),
                )
            )

        return events

    # --- result (terminal event) ---
    if event_type == "result":
        return [
            RunCompletedEvent(
                **base,
                is_error=bool(raw.get("is_error", False)),
                duration_ms=int(raw.get("duration_ms") or 0),
                total_cost_usd=float(raw.get("total_cost_usd") or 0.0),
                usage=raw.get("usage") or {},
            )
        ]

    logger.debug("parse_stream_event: unknown event type %r, skipping", event_type)
    return []


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _coerce_str_list(value: Any) -> list[str]:
    """Coerce an arbitrary value to list[str] defensively."""
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v) for v in value]
    if isinstance(value, str):
        return [value]
    return []
