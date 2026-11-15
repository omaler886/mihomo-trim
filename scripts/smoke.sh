#!/bin/bash
# mihomo-trim 冒烟 CI: 踩坑固化
# 用法: bash scripts/smoke.sh <二进制路径> <trim|lite>
# 断言:
#  1. 二进制是目标平台 ELF (GOOS 忘带会产出错平台二进制)
#  2. 版本号带 trim/lite 标记
#  3. 保留协议配置解析通过
#  4. 被裁协议全部报 unsupport proxy type (裁剪零残留)
#  5. lite 无服务端 listener / trim 保留服务端
set -u
BIN=$1
VARIANT=${2:-trim}
[[ "$BIN" != */* ]] && BIN="./$BIN"   # 相对路径必须带 ./ 否则 bash 按 PATH 找命令
TMP=$(mktemp -d)
trap 'rm -rf $TMP' EXIT
fail() { echo "SMOKE-FAIL: $1"; exit 1; }

# 1. 平台检查
ELF_SIG=$(head -c 4 "$BIN" | od -An -tx1 | tr -d ' ')
echo "$ELF_SIG" | grep -q "^7f454c46" || fail "不是 ELF (GOOS 忘带?)"

# 2. 版本含构建标记 (CI 版本形如 trim-<sha> / lite-<sha>)
VER=$("$BIN" -v)
echo "version: $VER"
case "$VER" in
  *trim*|*lite*) ;;
  *) fail "版本缺 trim/lite 标记: $VER" ;;
esac

# 3. 保留协议解析通过
cat > "$TMP/kept.yaml" <<'EOF'
proxies:
  - {name: ss1, type: ss, server: 1.2.3.4, port: 443, cipher: aes-128-gcm, password: x}
  - {name: vm1, type: vmess, server: 1.2.3.4, port: 443, uuid: 946eeac3-9038-4621-933e-6c389224db65, alterId: 0, cipher: auto}
  - {name: vl1, type: vless, server: 1.2.3.4, port: 443, uuid: 946eeac3-9038-4621-933e-6c389224db65, tls: true}
  - {name: tr1, type: trojan, server: 1.2.3.4, port: 443, password: x}
  - {name: hy1, type: hysteria2, server: 1.2.3.4, port: 443, password: x}
  - {name: at1, type: anytls, server: 1.2.3.4, port: 443, password: x}
  - {name: sk1, type: socks5, server: 1.2.3.4, port: 1080}
  - {name: ht1, type: http, server: 1.2.3.4, port: 8080}
  - {name: wg1, type: wireguard, server: 1.2.3.4, port: 51820, ip: 172.16.0.2, private-key: QKEFimFo7UtMY/3UOjxQpTBVVobLQOMr3Y8mjNOua38=, public-key: zu7ZStRpHHQkD0DvdQQOtJKTiGLoRjJtSjqJigDUgCo=, allowed-ips: ['0.0.0.0/0']}
  - {name: zt1, type: zerotier, network: "1234567890abcdef"}
rules:
  - MATCH,DIRECT
EOF
"$BIN" -t -d "$TMP" -f "$TMP/kept.yaml" > "$TMP/kept.log" 2>&1
grep -q "test is successful" "$TMP/kept.log" || { cat "$TMP/kept.log"; fail "保留协议配置解析失败"; }
echo "kept-protocols: PASS"

# 4. 被裁协议逐个断言 unsupport
for p in ssr tuic snell hysteria mieru sudoku shadowquic masque trusttunnel gost-relay ssh; do
  printf 'proxies:\n  - {name: bad, type: %s, server: 1.2.3.4, port: 443}\nrules:\n  - MATCH,DIRECT\n' "$p" > "$TMP/rm.yaml"
  if "$BIN" -t -d "$TMP" -f "$TMP/rm.yaml" > "$TMP/rm.log" 2>&1 && grep -q "test is successful" "$TMP/rm.log"; then
    fail "被裁协议 $p 仍可解析 (裁剪残留!)"
  fi
  grep -q "unsupport proxy type: $p" "$TMP/rm.log" || fail "$p 报错不是 unsupport: $(tail -1 $TMP/rm.log)"
done
echo "removed-protocols: 11/11 unsupport PASS"

# 5. lite 专属: 服务端 listener 必须全部拒绝; trim 必须保留
printf 'listeners:\n  - {name: s, type: shadowsocks, port: "31901", password: x, cipher: aes-128-gcm}\n' > "$TMP/ls.yaml"
"$BIN" -t -d "$TMP" -f "$TMP/ls.yaml" > "$TMP/ls.log" 2>&1
if [ "$VARIANT" = "lite" ]; then
  grep -q "unsupport proxy type: shadowsocks" "$TMP/ls.log" || fail "lite 服务端 shadowsocks listener 未被移除"
  echo "lite-no-server-listener: PASS"
else
  grep -q "test is successful" "$TMP/ls.log" || { cat "$TMP/ls.log"; fail "trim 服务端 shadowsocks listener 被误删"; }
  echo "trim-has-server-listener: PASS"
fi

echo "SMOKE-PASS ($VARIANT)"
