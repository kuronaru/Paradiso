from __future__ import annotations

import json
import sys
import threading
import unittest
import urllib.error
import urllib.request
from http import HTTPStatus
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from public_room_service import (  # noqa: E402
    RoomHTTPServer,
    RoomStore,
    ServiceError,
)


class FakeRelayManager:
    def __init__(self) -> None:
        self.ensure_calls: list[str] = []
        self.stopped: list[str] = []

    def ensure(self, room_code: str, owner_token: str) -> tuple[str, int]:
        assert owner_token
        self.ensure_calls.append(room_code)
        return "relay.example.test", 25001

    def stop(self, room_code: str) -> None:
        self.stopped.append(room_code)


class FakeClock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


class RoomStoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.relay = FakeRelayManager()
        self.store = RoomStore(self.relay, ttl_seconds=10, clock=self.clock)

    def create_direct(self) -> dict:
        return self.store.create(
            {
                "host_name": "Host",
                "max_players": 4,
                "direct_available": True,
                "direct_address": "203.0.113.8",
                "direct_port": 24567,
            }
        )

    def test_create_and_join_up_to_four_players(self) -> None:
        created = self.create_direct()
        self.assertEqual(created["status"], "DIRECT")
        self.assertIn("host_token", created)
        self.assertIn("room_token", created)

        code = created["room_code"]
        for expected_count in (2, 3, 4):
            joined = self.store.join(code, {"display_name": f"P{expected_count}"})
            self.assertEqual(joined["player_count"], expected_count)
            self.assertNotIn("host_token", joined)
            self.assertEqual(joined["room_token"], created["room_token"])

        with self.assertRaises(ServiceError) as context:
            self.store.join(code, {"display_name": "P5"})
        self.assertEqual(context.exception.status, HTTPStatus.CONFLICT)

    def test_relay_switch_is_authenticated_and_idempotent(self) -> None:
        created = self.create_direct()
        code = created["room_code"]
        with self.assertRaises(ServiceError) as context:
            self.store.request_relay(code, "wrong")
        self.assertEqual(context.exception.status, HTTPStatus.UNAUTHORIZED)

        first = self.store.request_relay(code, created["room_token"])
        second = self.store.request_relay(code, created["host_token"])
        self.assertEqual(first["status"], "RELAY")
        self.assertEqual(first["transport_generation"], 2)
        self.assertEqual(second["relay_port"], first["relay_port"])
        self.assertEqual(self.relay.ensure_calls, [code])

    def test_no_direct_endpoint_starts_relay_immediately(self) -> None:
        created = self.store.create(
            {
                "host_name": "Host",
                "max_players": 2,
                "direct_available": False,
                "direct_address": "",
                "direct_port": 24567,
            }
        )
        self.assertEqual(created["status"], "RELAY")
        self.assertEqual(created["relay_address"], "relay.example.test")
        self.assertEqual(self.relay.ensure_calls, [created["room_code"]])

    def test_expired_room_is_removed_and_relay_stopped(self) -> None:
        created = self.create_direct()
        code = created["room_code"]
        self.store.request_relay(code, created["host_token"])
        self.clock.now += 11
        with self.assertRaises(ServiceError) as context:
            self.store.get(code)
        self.assertEqual(context.exception.status, HTTPStatus.NOT_FOUND)
        self.assertEqual(self.relay.stopped, [code])

    def test_only_host_can_heartbeat_or_close(self) -> None:
        created = self.create_direct()
        code = created["room_code"]
        with self.assertRaises(ServiceError):
            self.store.heartbeat(code, created["room_token"], {})
        running = self.store.heartbeat(code, created["host_token"], {"status": "RUNNING"})
        self.assertEqual(running["status"], "RUNNING")
        with self.assertRaises(ServiceError):
            self.store.close(code, created["room_token"])
        self.store.close(code, created["host_token"])
        with self.assertRaises(ServiceError):
            self.store.get(code)


class RoomHTTPTest(unittest.TestCase):
    def setUp(self) -> None:
        self.relay = FakeRelayManager()
        self.server = RoomHTTPServer(("127.0.0.1", 0), RoomStore(self.relay, 30))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)

    def request(
        self,
        method: str,
        path: str,
        body: dict | None = None,
        token: str = "",
    ) -> tuple[int, dict]:
        headers = {"Accept": "application/json"}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode()
        if token:
            headers["Authorization"] = f"Bearer {token}"
        request = urllib.request.Request(
            self.base_url + path,
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=2) as response:
                raw = response.read()
                return response.status, json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            return error.code, json.loads(error.read())

    def test_health_and_room_lifecycle_over_http(self) -> None:
        status, health = self.request("GET", "/health")
        self.assertEqual(status, 200)
        self.assertEqual(health, {"status": "ok"})

        status, created = self.request(
            "POST",
            "/v1/rooms",
            {
                "host_name": "Host",
                "max_players": 4,
                "direct_available": True,
                "direct_address": "203.0.113.8",
                "direct_port": 24567,
            },
        )
        self.assertEqual(status, 201)
        code = created["room_code"]

        status, joined = self.request(
            "POST",
            f"/v1/rooms/{code}/join",
            {"display_name": "Guest"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(joined["player_count"], 2)

        status, relay = self.request(
            "POST",
            f"/v1/rooms/{code}/relay",
            {},
            joined["room_token"],
        )
        self.assertEqual(status, 200)
        self.assertEqual(relay["status"], "RELAY")

        status, _ = self.request(
            "DELETE",
            f"/v1/rooms/{code}",
            {},
            created["host_token"],
        )
        self.assertEqual(status, 204)


if __name__ == "__main__":
    unittest.main()
