# mihomo-trim

[mihomo](https://github.com/MetaCubeX/mihomo) (Clash.Meta 内核) 的精简裁剪版，基于官方 Meta 分支 `0455d0d`（2026-11-11）裁剪。

## 分支与产物

| 分支 | 说明 |
|---|---|
| `main` | **trim**：删 11 个协议 |
| `lite` | **lite**：trim 基础上再删全部服务端 listener（纯客户端） |
| `alpha-trim` | **alpha-trim**：同样的 trim，基于上游 **Alpha 测试分支** @ 184857ce |
| `alpha-lite` | **alpha-lite**：纯客户端，基于上游 **Alpha 测试分支** |

Actions 自动构建（push 触发，产物挂 Prerelease）：
- linux-amd64 / linux-arm64
- android-arm64-v8 / android-armv7（手机用）
- windows-amd64
- 构建参数与官方 release 同款：`-tags with_gvisor -trimpath -ldflags "-s -w"`

## trim 删了什么

**删除的 11 个协议**（出站 + 对应服务端 + 传输层全链路）：
`ssr` `tuic` `snell` `hysteria(v1)` `mieru` `sudoku` `ssh` `masque` `gost-relay` `trusttunnel` `shadowquic`

**保留**：
- 代理协议：vless / vmess / hysteria2 / ss / trojan / anytls / zerotier
- 组网类：wireguard / openvpn / tailscale / easytier
- 通用代理：socks5 / http；功能出站：dns / rematch / direct / reject
- 传输层插件：xhttp / mkcp / kcptun / gun / shadowtls / restls / jls / tlsmirror / simple-obfs / v2ray-plugin / gost-plugin

**lite 额外删除**：全部对外服务端 listener（ss/vmess/vless/trojan/hy2/realm/anytls server）+ 内嵌 ss/vmess 服务端 + `ss-config`/`vmess-config` API；保留本地入口（socks/http/mixed/tun/redir/tproxy/tunnel/inner）。

## 验证（两台 LXC 对拉实测）

- 31 条路径矩阵（ss 全密码族+全插件、vmess 全传输、vless 全传输+reality+xhttp、trojan+reality、hy2、anytls、wg/ovpn/easytier）：trim / 官方 Meta / 官方 Alpha / lite 四方 **28/31 全过且失败集合逐字节一致**，3 个失败为官方原生缺口（vmess-grpc 服务端不协商 h2 ALPN、hy2-realm 需 realm 控制面、easytier 轮内成网时序）
- 互操作：trim ↔ 官方 Meta 双向 8/8 协议互通
- 被裁 11 协议 100% 报 `unsupport proxy type`
- 性能：延迟 4-10ms、TLS 路径 100-350MB/s（与官方同级）；体积比官方小 ~8-10%；lite 内存最低
- 并发：6 实例并发压测无死亡、无 OOM

## 上游自动同步

`sync_upstream.sh`（仓库外，本地定时任务每天 09:00 跑一次）：
1. fetch 上游 Meta/Alpha 新提交
2. 四分支分别 rebase 重放裁剪提交
3. 构建 linux-amd64 上测试机跑冒烟（五项断言）
4. **冒烟绿 = 自动直推**（CI 自动出新产物）；冲突/冒烟红 = 中止留现场待人工

## CI 冒烟（scripts/smoke.sh）

每次构建断言：二进制平台正确、保留协议可解析、11 个被裁协议全部 unsupport、lite 无服务端 listener、版本含构建标记。
