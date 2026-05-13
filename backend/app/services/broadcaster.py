import asyncio
import json
from collections import defaultdict
from typing import Any
from fastapi import WebSocket

class EventBroadcaster:
    def __init__(self) -> None:
        self._channels: dict[str, set[WebSocket | asyncio.Queue]] = defaultdict(set)
        self._connected = False

    async def connect(self):
        """Initialize broadcaster on startup."""
        self._connected = True

    async def disconnect(self):
        """Cleanup on shutdown."""
        self._connected = False

    async def subscribe(self, websocket: WebSocket | None, channel: str) -> asyncio.Queue | None:
        """
        Subscribe to a channel.
        If websocket is provided, messages are sent directly to it.
        Otherwise, returns a Queue for polling.
        """
        if websocket:
            self._channels[channel].add(websocket)
            return None
        else:
            q: asyncio.Queue = asyncio.Queue(maxsize=200)
            self._channels[channel].add(q)
            return q

    async def unsubscribe(self, websocket: WebSocket | None, channel: str, q: asyncio.Queue | None = None) -> None:
        """Unsubscribe from a channel."""
        if websocket:
            self._channels[channel].discard(websocket)
        elif q:
            self._channels[channel].discard(q)

    async def publish(self, channel: str, payload: dict[str, Any] | str) -> None:
        """Publish a message to all subscribers on a channel."""
        if isinstance(payload, str):
            try:
                payload_dict = json.loads(payload)
            except:
                payload_dict = {"message": payload}
        else:
            payload_dict = payload
        
        for subscriber in list(self._channels.get(channel, [])):
            try:
                if isinstance(subscriber, WebSocket):
                    # Send to WebSocket
                    await subscriber.send_json(payload_dict)
                elif isinstance(subscriber, asyncio.Queue):
                    # Send to Queue
                    if not subscriber.full():
                        await subscriber.put(payload_dict)
            except Exception as e:
                print(f"Broadcast error to {subscriber}: {e}")
                # Remove dead subscribers
                self._channels[channel].discard(subscriber)

broadcaster = EventBroadcaster()
