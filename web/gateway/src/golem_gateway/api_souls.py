"""APIRouter for /v1/souls endpoints."""

from __future__ import annotations

from fastapi import APIRouter, HTTPException

from golem_gateway.souls import SoulDetail, SoulSummary, get_soul_by_id, scan_souls

router = APIRouter(prefix="/v1/souls", tags=["souls"])


@router.get("", response_model=list[SoulSummary])
def list_souls() -> list[SoulSummary]:
    """Return all SOULs (lean payload — no content field)."""
    souls = scan_souls()
    return [
        SoulSummary(
            id=s.id,
            name=s.name,
            rank=s.rank,
            specialty=s.specialty,
            description=s.description,
        )
        for s in souls
    ]


@router.get("/{soul_id}", response_model=SoulDetail)
def get_soul(soul_id: str) -> SoulDetail:
    """Return a single SOUL including full markdown body."""
    soul = get_soul_by_id(soul_id)
    if soul is None:
        raise HTTPException(status_code=404, detail=f"SOUL '{soul_id}' not found")
    return soul
