"""Check chronological pagination against the package's disposable PostgreSQL."""

import asyncio
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

from app.database import async_session_maker, engine  # ty: ignore[unresolved-import]
from app.models.outfit import Outfit, OutfitSource, OutfitStatus  # ty: ignore[unresolved-import]
from app.models.user import User  # ty: ignore[unresolved-import]
from app.services.outfit_service import OutfitListFilters, OutfitService  # ty: ignore[unresolved-import]
from sqlalchemy.engine import make_url


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


async def main():
    require(
        make_url(str(engine.url)).database == "wardrowbe_planning_test",
        "Disposable database required",
    )
    async with async_session_maker() as db:
        user_id, other_id = uuid4(), uuid4()
        db.add_all([
            User(
                id=uid,
                external_id=f"pagination-{uid}",
                email=f"{uid}@example.test",
                display_name="Pagination fixture",
                timezone="UTC",
                is_active=True,
            )
            for uid in [user_id, other_id]
        ])
        await db.flush()
        timestamp = datetime(2026, 1, 1, 12, tzinfo=UTC)
        prefix = uuid4().int & ~255
        ids = [UUID(int=prefix + value) for value in [2, 8, 1, 6, 3, 7, 4, 5]]
        newest = UUID(int=prefix)
        for uid, owner, created in [
            *[(uid, user_id, timestamp) for uid in ids],
            (newest, user_id, timestamp + timedelta(seconds=1)),
            (uuid4(), other_id, timestamp + timedelta(seconds=2)),
        ]:
            db.add(
                Outfit(
                    id=uid,
                    user_id=owner,
                    name="Pagination fixture",
                    occasion="casual",
                    scheduled_for=None,
                    source=OutfitSource.manual,
                    status=OutfitStatus.pending,
                    created_at=created,
                )
            )
        await db.flush()
        service = OutfitService(db)
        filters = OutfitListFilters(user_id=user_id, is_lookbook=True)
        expected = [newest, *sorted(ids)]
        for _ in range(2):
            actual = []
            for page in range(1, 4):
                outfits, total = await service.list_with_filters(filters, page, 3)
                require(
                    total == len(expected), "Count includes another owner's records"
                )
                actual.extend(outfit.id for outfit in outfits)
            require(
                actual == expected, "Page boundaries omit, repeat or reorder outfits"
            )
            require(len(set(actual)) == total, "Pages contain duplicate outfits")
        # Fixtures do not survive the test, even in the disposable database.
        await db.rollback()
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
