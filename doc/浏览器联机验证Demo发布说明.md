# 浏览器联机验证 Demo 发布说明

## 已落地架构

验证版使用 Godot 4.5 单线程 Web 导出、itch.io Restricted HTML5 页面和 Heroic Cloud Validation 环境中的 Nakama。浏览器客户端通过设备匿名认证连接 HTTPS/WSS，使用 6 位房间码加入命名的 Client Relayed Match，再由 `NakamaMultiplayerBridge` 承载现有 Godot 高层 RPC。

原生构建仍保留 LAN、ENet 公网直连及专用中继入口。Web 构建会隐藏 IP、端口和 ENet 操作，只显示创建房间和房间码加入。

命名 Match 格式为：

```text
paradiso-{multiplayer_protocol_version}-{ROOM_CODE}
```

当前协议版本来自 `MultiplayerRunManager.PROTOCOL_VERSION`。不同协议版本不会进入同一个 Nakama Match。

## Heroic Cloud 配置

1. 在 Heroic Cloud 创建独立的 `Validation` 环境。
2. 只暴露 HTTPS/WSS 端点，不把数据库或管理控制台密钥写入客户端。
3. 把客户端可用的 Nakama 地址与 Server Key 写入 `game/data/config.json`：

```json
{
  "nakama_host": "your-validation-host.example.com",
  "nakama_port": 443,
  "nakama_scheme": "https",
  "nakama_server_key": "client-server-key",
  "web_build_version": "0.1.0-validation.1",
  "web_publish_url": "https://account.itch.io/paradiso-validation",
  "web_feedback_url": "https://your-feedback-form.example.com"
}
```

Server Key 会随 Web 客户端分发，只能视为客户端接入标识，不能当作管理密钥。Validation 环境应与正式数据完全隔离。

项目固定提交官方 Nakama Godot SDK `3.4.0`，版本记录位于 `game/addons/com.heroiclabs.nakama/VERSION`。

## itch.io 首次设置

1. 新建 HTML 项目并选择“在浏览器中运行”。
2. 将页面设为 Restricted，以密码或 Download key/邀请链接限制测试者。
3. 首轮只声明支持桌面版 Chrome、Edge 和 Firefox，不承诺 Safari 与移动端。
4. 页面填写反馈表链接，并说明房间码、构建版本和诊断编号需要随问题一并提交。
5. 首次使用 butler 登录：`butler login`。

## 导出与重复发布

Web 包内置了 `NotoSansSC-ProjectSubset.ttf`，避免浏览器无法调用系统中文字体时出现乱码。字体来源为 Google Fonts 的 Noto Sans SC，按 SIL Open Font License 发布；项目提交的子集覆盖现有文本和 GB2312 常用简体中文。需要重新生成子集时，先安装 `tools/release/requirements-font.txt`，再运行 `tools/release/build_font_subset.py`。

只验证本地 Web 产物：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\release\publish_web_demo.ps1 -SkipUpload
```

发布到固定测试频道：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\release\publish_web_demo.ps1 -ItchTarget "account/paradiso-validation"
```

也可以设置环境变量 `PARADISO_ITCH_TARGET=account/paradiso-validation`。脚本始终更新 `html5-validation` 频道，因此不会产生新的邀请地址。发布前会检查 `index.html`、`index.wasm` 与 `index.pck`。

## 验证行为与边界

- 2～4 人可创建、加入、准备并由房主开局；第 5 人会收到“房间已满”。
- 开局后加入者会被拒绝；房主离开或关闭页面后，其余玩家返回大厅。
- Nakama 仅做认证、WebSocket 和消息中继，战果屏障、联合防守、来源玩家扣血仍由房主客户端协调。
- 当前不提供防作弊、公开匹配、观战、房主迁移和战斗中重连。
- 隐私模式或浏览器拒绝持久存储时仍可游玩，但匿名身份和本地存档可能不会保留。
- 客户端记录页面启动、认证、建房/进房、开局、回合完成、主动离开、异常断线及诊断编号。事件会输出到客户端日志，并在可用时通过 Nakama Events 上报。

## 验收清单

- Chrome、Edge、Firefox 均可加载同一 itch.io 页面。
- 分别用 2、3、4 个独立浏览器会话完成房间码组队与开局。
- 验证第 5 人、错误版本、开局后加入的拒绝提示。
- 完成一轮本地漏怪、两段联合防守和来源玩家扣血，结果与 ENet 版一致。
- 房主关闭标签页后，其他玩家收到断线/房间结束提示。
- 20 个并发会话、至少 5 个房间持续 30 分钟，无串房、重复扣血或屏障永久等待。
- 每次测试记录构建版本、房间码、浏览器、结果和诊断编号。

## 参考资料

- [Godot Web 导出限制](https://docs.godotengine.org/en/4.5/tutorials/export/exporting_for_web.html)
- [Nakama Godot 4 SDK](https://github.com/heroiclabs/nakama-godot)
- [Nakama Client Relayed Multiplayer](https://heroiclabs.com/docs/nakama/concepts/multiplayer/relayed/)
- [itch.io HTML5 发布](https://itch.io/docs/creators/html5)
- [itch.io 访问控制](https://itch.io/docs/creators/access-control.amp)
- [butler 推送](https://itch.io/docs/butler/pushing.html)
