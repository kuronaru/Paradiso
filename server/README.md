# Paradiso 公网房间服务

该目录提供中央房间目录和按需启动的 Godot ENet 中继。详细协议和设计边界见
`../doc/公网联机与中继服务方案.md`。

## 本地运行

在仓库根目录执行：

```powershell
$env:PARADISO_GODOT_SERVER_BIN = "C:\path\to\Godot_v4.5.1-stable_win64_console.exe"
$env:PARADISO_PUBLIC_RELAY_HOST = "127.0.0.1"
python server/public_room_service.py
```

也可以用命令行参数覆盖 HTTP 监听配置：

```powershell
python server/public_room_service.py --bind-host 127.0.0.1 --http-port 8787 --room-ttl 90
```

环境变量也都有对应的命令行参数；例如
`--public-relay-host`、`--relay-port-start`、`--relay-port-end`、
`--godot-bin` 和 `--project-path`。

客户端默认访问 `http://127.0.0.1:8787`。服务健康检查：

```powershell
Invoke-RestMethod http://127.0.0.1:8787/health
```

## 配置

| 环境变量 | 默认值 | 说明 |
| --- | --- | --- |
| `PARADISO_BIND_HOST` | `127.0.0.1` | HTTP 监听地址 |
| `PARADISO_HTTP_PORT` | `8787` | HTTP 端口 |
| `PARADISO_PUBLIC_RELAY_HOST` | 同监听地址 | 返回给客户端的中继域名或公网 IP |
| `PARADISO_RELAY_PORT_START` | `25000` | 中继 UDP 端口池起点 |
| `PARADISO_RELAY_PORT_END` | `25100` | 中继 UDP 端口池终点 |
| `PARADISO_GODOT_SERVER_BIN` | 自动查找 `godot4`/`godot` | Godot 控制台或服务器程序 |
| `PARADISO_GODOT_PROJECT_PATH` | 仓库内 `game` | Godot 项目目录 |
| `PARADISO_RELAY_LOG_DIR` | `game/.godot/relay-logs` | 每个中继进程的日志目录 |
| `PARADISO_ROOM_TTL_SECONDS` | `90` | 无房主心跳后的房间过期时间 |
| `PARADISO_RELAY_IDLE_TIMEOUT_SECONDS` | `120` | 中继无玩家后的退出时间 |

公网部署还需要：

- 由 Nginx、Caddy 或云负载均衡器终止 HTTPS；
- 放通 HTTP 反向代理端口和中继 UDP 端口池；
- 将 `PARADISO_PUBLIC_RELAY_HOST` 设置为客户端可访问的公网域名；
- 以受限系统账号运行，不授予中继进程访问游戏存档或管理凭证的权限。

## 测试

```powershell
python -m unittest discover -s server/tests -v
```
