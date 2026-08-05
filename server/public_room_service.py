"""Paradiso public room directory and on-demand Godot relay launcher.

The service intentionally uses only Python's standard library. Put it behind an
HTTPS reverse proxy for production use; its built-in HTTP server is intended
for development and small controlled deployments.
"""

from __future__ import annotations

import json
import os
import secrets
import shutil
import subprocess
import argparse
import threading
import time
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import unquote, urlparse


ROOM_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"
ROOM_CODE_LENGTH = 6
PUBLIC_ROOM_FIELDS = (
    "room_code",
    "status",
    "transport_generation",
    "direct_address",
    "direct_port",
    "relay_address",
    "relay_port",
    "player_count",
    "max_players",
    "created_at",
    "last_heartbeat_at",
)


class ServiceError(Exception):
    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status
        self.message = message


@dataclass
class RelayHandle:
    room_code: str
    port: int
    process: subprocess.Popen[bytes]


class RelayProcessManager:
    """Allocates one ENet headless Godot process per relayed room."""

    def __init__(
        self,
        *,
        public_host: str | None = None,
        port_start: int | None = None,
        port_end: int | None = None,
        godot_bin: str | None = None,
        project_path: str | None = None,
    ) -> None:
        self.bind_host = os.getenv("PARADISO_BIND_HOST", "127.0.0.1")
        self.public_host = public_host or os.getenv(
            "PARADISO_PUBLIC_RELAY_HOST",
            self.bind_host,
        )
        self.port_start = port_start or int(os.getenv("PARADISO_RELAY_PORT_START", "25000"))
        self.port_end = port_end or int(os.getenv("PARADISO_RELAY_PORT_END", "25100"))
        self.project_path = Path(
            project_path
            or os.getenv(
                "PARADISO_GODOT_PROJECT_PATH",
                str(Path(__file__).resolve().parents[1] / "game"),
            ),
        ).resolve()
        self.godot_bin = (godot_bin or os.getenv("PARADISO_GODOT_SERVER_BIN", "")).strip()
        if not self.godot_bin:
            self.godot_bin = shutil.which("godot4") or shutil.which("godot") or ""
        self.log_dir = Path(
            os.getenv(
                "PARADISO_RELAY_LOG_DIR",
                str(self.project_path / ".godot" / "relay-logs"),
            )
        ).resolve()
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.idle_timeout = int(os.getenv("PARADISO_RELAY_IDLE_TIMEOUT_SECONDS", "120"))
        self._handles: dict[str, RelayHandle] = {}
        self._lock = threading.RLock()

    def ensure(self, room_code: str, owner_token: str) -> tuple[str, int]:
        with self._lock:
            current = self._handles.get(room_code)
            if current and current.process.poll() is None:
                return self.public_host, current.port
            if current:
                self._handles.pop(room_code, None)
            if not self.godot_bin:
                raise ServiceError(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    "未配置 Godot 中继程序；请设置 PARADISO_GODOT_SERVER_BIN。",
                )
            port = self._allocate_port_locked()
            command = [
                self.godot_bin,
                "--headless",
                "--path",
                str(self.project_path),
                "--log-file",
                str(self.log_dir / f"{room_code}.log"),
                "--script",
                "res://scripts/multiplayer/dedicated_room_server.gd",
                "--",
                f"--relay-port={port}",
                f"--room-code={room_code}",
                f"--owner-token={owner_token}",
                f"--idle-timeout={self.idle_timeout}",
            ]
            creation_flags = 0
            if os.name == "nt":
                creation_flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
            try:
                process = subprocess.Popen(
                    command,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    creationflags=creation_flags,
                )
            except OSError as exc:
                raise ServiceError(
                    HTTPStatus.SERVICE_UNAVAILABLE,
                    f"无法启动 Godot 中继：{exc}",
                ) from exc
            self._handles[room_code] = RelayHandle(room_code, port, process)
            return self.public_host, port

    def stop(self, room_code: str) -> None:
        with self._lock:
            handle = self._handles.pop(room_code, None)
        if not handle or handle.process.poll() is not None:
            return
        handle.process.terminate()
        try:
            handle.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            handle.process.kill()

    def stop_all(self) -> None:
        with self._lock:
            room_codes = list(self._handles)
        for room_code in room_codes:
            self.stop(room_code)

    def _allocate_port_locked(self) -> int:
        used = {
            handle.port
            for handle in self._handles.values()
            if handle.process.poll() is None
        }
        for port in range(self.port_start, self.port_end + 1):
            if port not in used:
                return port
        raise ServiceError(
            HTTPStatus.SERVICE_UNAVAILABLE,
            "当前没有可用的中继端口。",
        )


class RoomStore:
    def __init__(
        self,
        relay_manager: RelayProcessManager,
        ttl_seconds: int = 90,
        clock=time.time,
    ) -> None:
        self.relay_manager = relay_manager
        self.ttl_seconds = max(5, ttl_seconds)
        self.clock = clock
        self._rooms: dict[str, dict[str, Any]] = {}
        self._lock = threading.RLock()

    def create(self, payload: dict[str, Any]) -> dict[str, Any]:
        now = float(self.clock())
        max_players = _bounded_int(payload.get("max_players", 4), 2, 4, "max_players")
        direct_available = bool(payload.get("direct_available", False))
        direct_address = str(payload.get("direct_address", "")).strip()
        direct_port = _bounded_int(payload.get("direct_port", 0), 0, 65535, "direct_port")
        if direct_available and (not direct_address or direct_port == 0):
            raise ServiceError(
                HTTPStatus.BAD_REQUEST,
                "直连可用时必须提供 direct_address 和 direct_port。",
            )
        with self._lock:
            self.prune_locked(now)
            room_code = self._new_room_code_locked()
            room = {
                "room_code": room_code,
                "host_name": _bounded_text(payload.get("host_name", "Player"), 32),
                "host_token": secrets.token_urlsafe(32),
                "room_token": secrets.token_urlsafe(24),
                "status": "DIRECT" if direct_available else "RELAY_STARTING",
                "transport_generation": 1,
                "direct_address": direct_address if direct_available else "",
                "direct_port": direct_port if direct_available else 0,
                "relay_address": "",
                "relay_port": 0,
                "player_count": 1,
                "max_players": max_players,
                "created_at": now,
                "last_heartbeat_at": now,
            }
            self._rooms[room_code] = room
        if not direct_available:
            try:
                self._switch_to_relay(room_code)
            except Exception:
                with self._lock:
                    self._rooms.pop(room_code, None)
                raise
        with self._lock:
            return self._view(self._rooms[room_code], include_host_token=True, include_room_token=True)

    def get(self, room_code: str) -> dict[str, Any]:
        with self._lock:
            room = self._get_live_room_locked(room_code)
            return self._view(room)

    def join(self, room_code: str, payload: dict[str, Any]) -> dict[str, Any]:
        del payload  # Display names are authoritative in the ENet lobby.
        with self._lock:
            room = self._get_live_room_locked(room_code)
            if room["status"] in {"RUNNING", "CLOSED"}:
                raise ServiceError(HTTPStatus.CONFLICT, "房间已经开始或关闭。")
            if int(room["player_count"]) >= int(room["max_players"]):
                raise ServiceError(HTTPStatus.CONFLICT, "房间人数已满。")
            room["player_count"] += 1
            return self._view(room, include_room_token=True)

    def request_relay(self, room_code: str, token: str) -> dict[str, Any]:
        with self._lock:
            room = self._get_live_room_locked(room_code)
            self._require_room_token(room, token)
            if room["status"] == "RUNNING":
                raise ServiceError(HTTPStatus.CONFLICT, "开局后不能切换传输方式。")
            if room["status"] in {"RELAY_STARTING", "RELAY"}:
                return self._view(room)
            previous_status = str(room["status"])
            previous_generation = int(room["transport_generation"])
            room["status"] = "RELAY_STARTING"
            room["transport_generation"] += 1
        try:
            self._switch_to_relay(room_code)
        except Exception:
            with self._lock:
                room = self._rooms.get(room_code)
                if room and room["status"] == "RELAY_STARTING":
                    room["status"] = previous_status
                    room["transport_generation"] = previous_generation
            raise
        with self._lock:
            return self._view(self._rooms[room_code])

    def heartbeat(
        self,
        room_code: str,
        token: str,
        payload: dict[str, Any],
    ) -> dict[str, Any]:
        with self._lock:
            room = self._get_live_room_locked(room_code)
            self._require_host_token(room, token)
            room["last_heartbeat_at"] = float(self.clock())
            requested_status = str(payload.get("status", "")).upper()
            if requested_status == "RUNNING" and room["status"] in {"DIRECT", "RELAY"}:
                room["status"] = "RUNNING"
            return self._view(room)

    def close(self, room_code: str, token: str) -> None:
        with self._lock:
            room = self._get_live_room_locked(room_code)
            self._require_host_token(room, token)
            self._rooms.pop(room["room_code"], None)
        self.relay_manager.stop(room["room_code"])

    def prune(self) -> int:
        with self._lock:
            return self.prune_locked(float(self.clock()))

    def prune_locked(self, now: float) -> int:
        expired = [
            code
            for code, room in self._rooms.items()
            if now - float(room["last_heartbeat_at"]) > self.ttl_seconds
        ]
        for code in expired:
            self._rooms.pop(code, None)
            self.relay_manager.stop(code)
        return len(expired)

    def _switch_to_relay(self, room_code: str) -> None:
        with self._lock:
            room = self._rooms.get(room_code)
            if not room:
                raise ServiceError(HTTPStatus.NOT_FOUND, "房间不存在或已过期。")
            owner_token = str(room["host_token"])
        relay_address, relay_port = self.relay_manager.ensure(room_code, owner_token)
        with self._lock:
            room = self._rooms.get(room_code)
            if not room:
                self.relay_manager.stop(room_code)
                raise ServiceError(HTTPStatus.NOT_FOUND, "房间不存在或已过期。")
            room["relay_address"] = relay_address
            room["relay_port"] = relay_port
            room["status"] = "RELAY"

    def _get_live_room_locked(self, room_code: str) -> dict[str, Any]:
        self.prune_locked(float(self.clock()))
        normalized = room_code.strip().upper()
        room = self._rooms.get(normalized)
        if not room:
            raise ServiceError(HTTPStatus.NOT_FOUND, "房间不存在或已过期。")
        return room

    def _new_room_code_locked(self) -> str:
        for _attempt in range(100):
            code = "".join(secrets.choice(ROOM_ALPHABET) for _ in range(ROOM_CODE_LENGTH))
            if code not in self._rooms:
                return code
        raise ServiceError(HTTPStatus.SERVICE_UNAVAILABLE, "暂时无法分配房间码。")

    @staticmethod
    def _view(
        room: dict[str, Any],
        *,
        include_host_token: bool = False,
        include_room_token: bool = False,
    ) -> dict[str, Any]:
        result = {field: room[field] for field in PUBLIC_ROOM_FIELDS}
        if include_host_token:
            result["host_token"] = room["host_token"]
        if include_room_token:
            result["room_token"] = room["room_token"]
        return result

    @staticmethod
    def _require_host_token(room: dict[str, Any], token: str) -> None:
        if not token or not secrets.compare_digest(str(room["host_token"]), token):
            raise ServiceError(HTTPStatus.UNAUTHORIZED, "房主凭证无效。")

    @staticmethod
    def _require_room_token(room: dict[str, Any], token: str) -> None:
        valid_host = bool(token) and secrets.compare_digest(str(room["host_token"]), token)
        valid_room = bool(token) and secrets.compare_digest(str(room["room_token"]), token)
        if not valid_host and not valid_room:
            raise ServiceError(HTTPStatus.UNAUTHORIZED, "房间凭证无效。")


class RoomRequestHandler(BaseHTTPRequestHandler):
    server_version = "ParadisoRoomService/1.0"

    @property
    def store(self) -> RoomStore:
        return self.server.room_store  # type: ignore[attr-defined]

    def do_GET(self) -> None:
        path = self._parts()
        if path == ["health"]:
            self._send(HTTPStatus.OK, {"status": "ok"})
            return
        if len(path) == 3 and path[:2] == ["v1", "rooms"]:
            self._dispatch(lambda: self.store.get(path[2]))
            return
        self._send(HTTPStatus.NOT_FOUND, {"error": "接口不存在。"})

    def do_POST(self) -> None:
        path = self._parts()
        payload = self._read_json()
        if payload is None:
            return
        if path == ["v1", "rooms"]:
            self._dispatch(lambda: self.store.create(payload), HTTPStatus.CREATED)
        elif len(path) == 4 and path[:2] == ["v1", "rooms"] and path[3] == "join":
            self._dispatch(lambda: self.store.join(path[2], payload))
        elif len(path) == 4 and path[:2] == ["v1", "rooms"] and path[3] == "relay":
            self._dispatch(lambda: self.store.request_relay(path[2], self._bearer_token()))
        elif len(path) == 4 and path[:2] == ["v1", "rooms"] and path[3] == "heartbeat":
            self._dispatch(
                lambda: self.store.heartbeat(path[2], self._bearer_token(), payload)
            )
        else:
            self._send(HTTPStatus.NOT_FOUND, {"error": "接口不存在。"})

    def do_DELETE(self) -> None:
        path = self._parts()
        if len(path) == 3 and path[:2] == ["v1", "rooms"]:
            self._dispatch(
                lambda: self.store.close(path[2], self._bearer_token()),
                HTTPStatus.NO_CONTENT,
            )
            return
        self._send(HTTPStatus.NOT_FOUND, {"error": "接口不存在。"})

    def log_message(self, message_format: str, *args: Any) -> None:
        print(
            "%s - - [%s] %s"
            % (self.address_string(), self.log_date_time_string(), message_format % args),
            flush=True,
        )

    def _parts(self) -> list[str]:
        path = urlparse(self.path).path
        return [unquote(part) for part in path.split("/") if part]

    def _read_json(self) -> dict[str, Any] | None:
        try:
            length = min(int(self.headers.get("Content-Length", "0")), 64 * 1024)
            raw = self.rfile.read(length) if length > 0 else b"{}"
            value = json.loads(raw.decode("utf-8"))
            if not isinstance(value, dict):
                raise ValueError
            return value
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
            self._send(HTTPStatus.BAD_REQUEST, {"error": "请求体必须是 JSON 对象。"})
            return None

    def _bearer_token(self) -> str:
        authorization = self.headers.get("Authorization", "")
        prefix = "Bearer "
        return authorization[len(prefix) :].strip() if authorization.startswith(prefix) else ""

    def _dispatch(self, action, success_status: int = HTTPStatus.OK) -> None:
        try:
            result = action()
            self._send(success_status, result)
        except ServiceError as exc:
            self._send(exc.status, {"error": exc.message})
        except Exception as exc:  # Keep implementation details out of client responses.
            print(f"Unhandled room service error: {exc!r}", flush=True)
            self._send(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": "房间服务内部错误。"})

    def _send(self, status: int, payload: Any = None) -> None:
        body = b"" if status == HTTPStatus.NO_CONTENT else json.dumps(
            payload if payload is not None else {},
            ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)


class RoomHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], room_store: RoomStore) -> None:
        super().__init__(address, RoomRequestHandler)
        self.room_store = room_store


def _bounded_int(value: Any, minimum: int, maximum: int, field: str) -> int:
    try:
        result = int(value)
    except (TypeError, ValueError) as exc:
        raise ServiceError(HTTPStatus.BAD_REQUEST, f"{field} 必须是整数。") from exc
    if result < minimum or result > maximum:
        raise ServiceError(
            HTTPStatus.BAD_REQUEST,
            f"{field} 必须位于 {minimum}～{maximum}。",
        )
    return result


def _bounded_text(value: Any, maximum_length: int) -> str:
    text = str(value).strip()
    return (text or "Player")[:maximum_length]


def main() -> None:
    parser = argparse.ArgumentParser(description="Paradiso public room service")
    parser.add_argument(
        "--bind-host",
        default=os.getenv("PARADISO_BIND_HOST", "127.0.0.1"),
    )
    parser.add_argument(
        "--http-port",
        type=int,
        default=int(os.getenv("PARADISO_HTTP_PORT", "8787")),
    )
    parser.add_argument(
        "--room-ttl",
        type=int,
        default=int(os.getenv("PARADISO_ROOM_TTL_SECONDS", "90")),
    )
    parser.add_argument(
        "--public-relay-host",
        default=os.getenv("PARADISO_PUBLIC_RELAY_HOST", ""),
    )
    parser.add_argument(
        "--relay-port-start",
        type=int,
        default=int(os.getenv("PARADISO_RELAY_PORT_START", "25000")),
    )
    parser.add_argument(
        "--relay-port-end",
        type=int,
        default=int(os.getenv("PARADISO_RELAY_PORT_END", "25100")),
    )
    parser.add_argument(
        "--godot-bin",
        default=os.getenv("PARADISO_GODOT_SERVER_BIN", ""),
    )
    parser.add_argument(
        "--project-path",
        default=os.getenv(
            "PARADISO_GODOT_PROJECT_PATH",
            str(Path(__file__).resolve().parents[1] / "game"),
        ),
    )
    arguments = parser.parse_args()
    bind_host = arguments.bind_host
    http_port = arguments.http_port
    ttl_seconds = arguments.room_ttl
    relay_manager = RelayProcessManager(
        public_host=arguments.public_relay_host or bind_host,
        port_start=arguments.relay_port_start,
        port_end=arguments.relay_port_end,
        godot_bin=arguments.godot_bin,
        project_path=arguments.project_path,
    )
    store = RoomStore(relay_manager, ttl_seconds)
    server = RoomHTTPServer((bind_host, http_port), store)
    print(f"Paradiso room service listening on http://{bind_host}:{http_port}", flush=True)
    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.shutdown()
        server.server_close()
        relay_manager.stop_all()


if __name__ == "__main__":
    main()
