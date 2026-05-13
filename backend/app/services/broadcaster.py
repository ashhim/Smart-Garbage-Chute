import asyncio
from collections import defaultdict
from typing import Any

class EventBroadcaster:
    def __init__(self) -> None:
        self._rooms: dict[str, set[asyncio.Queue]] = defaultdict(set)

    async def subscribe(self, channel: str) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=200)
        self._rooms[channel].add(q)
        return q

    async def unsubscribe(self, channel: str, q: asyncio.Queue) -> None:
        self._rooms[channel].discard(q)

    async def publish(self, channel: str, payload: dict[str, Any]) -> None:
        for q in list(self._rooms.get(channel, [])):
            if not q.full():
                await q.put(payload)

broadcaster = EventBroadcaster()
