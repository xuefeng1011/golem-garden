"""Phase 4 registry smoke tests — 5 checks, backup/restore real registry."""

from __future__ import annotations

import asyncio
import json
import sys
import tempfile
from pathlib import Path

# ---------------------------------------------------------------------------
# Backup / restore helpers
# ---------------------------------------------------------------------------

REAL_REGISTRY = Path.home() / ".golem" / "projects.json"


def _backup() -> bytes | None:
    """Read and return current registry bytes, or None if missing."""
    if REAL_REGISTRY.is_file():
        return REAL_REGISTRY.read_bytes()
    return None


def _restore(backup: bytes | None) -> None:
    if backup is None:
        # Remove test file if it was created
        if REAL_REGISTRY.is_file():
            REAL_REGISTRY.unlink()
    else:
        REAL_REGISTRY.parent.mkdir(parents=True, exist_ok=True)
        REAL_REGISTRY.write_bytes(backup)


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------

PASS = "PASS"
FAIL = "FAIL"
results: list[tuple[str, str, str]] = []  # (check_name, status, detail)


def record(name: str, status: str, detail: str = "") -> None:
    results.append((name, status, detail))
    tag = "[PASS]" if status == PASS else "[FAIL]"
    print(f"  {tag} {name}" + (f": {detail}" if detail else ""))


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

REPO_ROOT = Path("C:/01_xuefeng/08_ai/golem-garden")


async def check_missing_file_graceful() -> None:
    """Check 1: Registry loads missing file gracefully -> returns []."""
    import golem_gateway.registry as reg_mod

    # Monkey-patch _registry_path to point at a guaranteed nonexistent file
    with tempfile.TemporaryDirectory() as tmpdir:
        fake_path = Path(tmpdir) / "nonexistent" / "projects.json"

        original_fn = reg_mod._registry_path
        reg_mod._registry_path = lambda: fake_path  # type: ignore[assignment]
        try:
            registry = reg_mod.ProjectRegistry()
            await registry.load()
            projects = await registry.list()
            if projects == []:
                record("missing-file-graceful", PASS)
            else:
                record("missing-file-graceful", FAIL, f"expected [], got {projects!r}")
        finally:
            reg_mod._registry_path = original_fn  # type: ignore[assignment]


async def check_create_list_delete_roundtrip() -> None:
    """Check 2: Create + list + delete roundtrip using real registry path."""
    import golem_gateway.registry as reg_mod

    registry = reg_mod.ProjectRegistry()
    await registry.load()

    # Remember pre-existing IDs so we don't delete them
    existing = {p.id for p in await registry.list()}

    # Create
    project = await registry.create(name="smoke-test-project", path=str(REPO_ROOT))
    new_id = project.id

    # List — should contain the new project
    all_projects = await registry.list()
    ids = {p.id for p in all_projects}
    if new_id not in ids:
        record("roundtrip", FAIL, f"created project {new_id!r} not found in list")
        return

    # Delete
    deleted = await registry.delete(new_id)
    if not deleted:
        record("roundtrip", FAIL, "delete returned False for known id")
        return

    # List again — should be gone
    after = {p.id for p in await registry.list()}
    if new_id in after:
        record("roundtrip", FAIL, f"project {new_id!r} still present after delete")
        return

    record("roundtrip", PASS)


async def check_duplicate_path_rejected() -> None:
    """Check 3: Second create with same path raises ValueError."""
    import golem_gateway.registry as reg_mod

    registry = reg_mod.ProjectRegistry()
    await registry.load()

    p1 = await registry.create(name="dup-check-A", path=str(REPO_ROOT))
    try:
        raised = False
        try:
            await registry.create(name="dup-check-B", path=str(REPO_ROOT))
        except ValueError:
            raised = True

        if raised:
            record("duplicate-path-rejected", PASS)
        else:
            record("duplicate-path-rejected", FAIL, "no ValueError raised for duplicate path")
    finally:
        # Clean up both (second may not have been created)
        await registry.delete(p1.id)


async def check_nonexistent_path_rejected() -> None:
    """Check 4: Non-existent path raises ValueError."""
    import golem_gateway.registry as reg_mod

    registry = reg_mod.ProjectRegistry()
    await registry.load()

    bad_path = "C:/definitely-does-not-exist-12345"
    try:
        await registry.create(name="bad-path-test", path=bad_path)
        record("nonexistent-path-rejected", FAIL, "no ValueError raised for missing dir")
    except ValueError as exc:
        record("nonexistent-path-rejected", PASS, str(exc)[:80])


async def check_malformed_id_returns_none() -> None:
    """Check 5: get() with traversal-style id returns None."""
    import golem_gateway.registry as reg_mod

    registry = reg_mod.ProjectRegistry()
    await registry.load()

    result = await registry.get("../etc/passwd")
    if result is None:
        record("malformed-id-returns-none", PASS)
    else:
        record("malformed-id-returns-none", FAIL, f"expected None, got {result!r}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main() -> int:
    backup = _backup()
    print(f"Registry backup: {'found' if backup else 'not found (clean slate)'}")
    print()

    # Clear registry for clean test state (restore at end)
    if REAL_REGISTRY.is_file():
        REAL_REGISTRY.unlink()

    try:
        print("Running 5 checks...")
        await check_missing_file_graceful()
        await check_create_list_delete_roundtrip()
        await check_duplicate_path_rejected()
        await check_nonexistent_path_rejected()
        await check_malformed_id_returns_none()
    finally:
        _restore(backup)
        print()
        print(f"Registry restored: {'yes (original content)' if backup else 'yes (removed test file)'}")

    print()
    passed = sum(1 for _, s, _ in results if s == PASS)
    failed = sum(1 for _, s, _ in results if s == FAIL)
    print(f"Results: {passed} passed, {failed} failed out of {len(results)} checks")

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
