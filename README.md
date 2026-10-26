# sock5

gost **SOCKS5 + HTTP** 双协议代理一键部署脚本。跑一条命令，自动生成 **随机用户名 / 随机密码 / 未被占用的随机端口**，直接给出两条可用连接串。

适用于 Debian / Ubuntu / CentOS / RHEL / Rocky / Alma / Fedora / Arch，支持 `amd64 / arm64 / armv7 / armv6 / 386`。

---

## 一键运行

```bash
curl -fsSL https://raw.githubusercontent.com/76hvc/sock5/main/socks5-install.sh | bash
```

或者先下载再执行（推荐，能看内容）：

```bash
git clone https://github.com/76hvc/sock5.git
cd sock5
sudo bash socks5-install.sh
```

跑完直接输出：

```
--------------------------------------------------------------
  代理部署完成（SOCKS5 + HTTP）
--------------------------------------------------------------
  主机 (Host)   : 3.148.165.194
  用户 (User)   : s5q1xvdnjk
  密码 (Pass)   : r68ieI9feqbnJ5QSTNAo

  ── SOCKS5 ──────────────────────────────────
  端口 (Port)   : 47321
  连接串 (推荐) : socks5h://s5q1xvdnjk:r68ieI9feqbnJ5QSTNAo@3.148.165.194:47321
  连接串 (兼容) : socks5://s5q1xvdnjk:r68ieI9feqbnJ5QSTNAo@3.148.165.194:47321

  ── HTTP ────────────────────────────────────
  端口 (Port)   : 58104
  连接串        : http://s5q1xvdnjk:r68ieI9feqbnJ5QSTNAo@3.148.165.194:58104

  本地测试      : curl -x socks5h://... https://ipinfo.io/ip
                : curl -x http://... https://ipinfo.io/ip
  查看状态      : bash socks5-install.sh --status
  卸载          : bash socks5-install.sh --uninstall
--------------------------------------------------------------
```

---

## 用法

| 命令 | 说明 |
|---|---|
| `bash socks5-install.sh` | 全自动：随机账号 + 两个随机空闲端口（SOCKS5 + HTTP） |
| `bash socks5-install.sh --port 1080` | 指定 SOCKS5 端口，HTTP 端口仍随机 |
| `bash socks5-install.sh --http-port 8080` | 指定 HTTP 代理端口 |
| `bash socks5-install.sh --no-http` | 只开 SOCKS5，不开 HTTP |
| `bash socks5-install.sh --user u --pass p` | 指定账号密码（两协议共用） |
| `bash socks5-install.sh --status` | 查看服务状态、监听、活跃连接、两条连接串 |
| `bash socks5-install.sh --url` | 只打印连接串（方便脚本调用） |
| `bash socks5-install.sh --uninstall` | 卸载服务 + 二进制 + 凭据文件 |
| `bash socks5-install.sh --help` | 帮助 |

环境变量：

```bash
GITHUB_MIRROR=https://ghfast.top/ bash socks5-install.sh   # 自定义下载加速
```

---

## 它做了什么

1. 检测架构，从 GitHub Releases 下载最新 `gost` 到 `/usr/local/bin/gost`（直连失败自动切 3 个加速镜像）
2. 用 `python3` 真实 `bind()` 探测空闲端口（TCP + IPv4/IPv6 双栈），范围 `20000-65000`
   - SOCKS5 端口先挑，HTTP 端口再挑并**排除已选的 SOCKS5 端口**（此时两者都还没监听，靠监听表检测不到冲突）
   - 无 python3 时退回 `ss` / `netstat` / `lsof` / `/dev/tcp` 四层兜底
3. 用 `openssl rand` 生成 8 位随机用户名、20 位随机密码，只含 `[A-Za-z0-9]`，保证能直接拼进 URL 不用转义
4. 写入 `/etc/systemd/system/gost-socks5.service`，一条 `ExecStart` 同时挂两个 listener：

```ini
ExecStart=/usr/local/bin/gost \
  -L socks5://<user>:<pass>@:<socks_port> \
  -L http://<user>:<pass>@:<http_port>
Restart=always
RestartSec=3
LimitNOFILE=1048576
```

5. 自动放行 `ufw` / `firewalld` / `iptables`（两个端口都放）
6. 探测公网 IP（ipify → ifconfig.me → ipinfo → EC2 metadata 兜底）
7. 本地自检：分别通过刚起的 SOCKS5 和 HTTP 端口请求 `api.ipify.org`，确认两条出口都通
8. 凭据落盘到 `/etc/gost-socks5.env`（`chmod 600`，仅 root 可读），格式：

```ini
S5_USER=s5q1xvdnjk
S5_PASS=r68ieI9feqbnJ5QSTNAo
S5_PORT=47321
S5_HTTP_PORT=58104
```

---

## 客户端接入

### SOCKS5

```bash
curl -x socks5h://USER:PASS@HOST:PORT https://ipinfo.io/ip
```

浏览器（SwitchyOmega）：协议 `SOCKS5` · 服务器填主机 · 端口填 SOCKS5 端口 · **勾选「使用代理进行 DNS 查询」** · 填用户名密码。

### HTTP / HTTPS

```bash
curl -x http://USER:PASS@HOST:PORT https://ipinfo.io/ip
```

支持 `CONNECT` 隧道，所以 HTTPS 站点也能过。

### Python

```python
import requests

# SOCKS5
proxies = {
    "http":  "socks5h://USER:PASS@HOST:SOCKS_PORT",
    "https": "socks5h://USER:PASS@HOST:SOCKS_PORT",
}

# HTTP
proxies = {
    "http":  "http://USER:PASS@HOST:HTTP_PORT",
    "https": "http://USER:PASS@HOST:HTTP_PORT",
}

print(requests.get("https://ipinfo.io/ip", proxies=proxies, timeout=10).text)
```

SOCKS5 需要 `pip install requests[socks]`。

### Git

```bash
# SOCKS5
git config --global http.proxy socks5h://USER:PASS@HOST:SOCKS_PORT
# HTTP
git config --global http.proxy http://USER:PASS@HOST:HTTP_PORT
# 撤销
git config --global --unset http.proxy
```

### 环境变量

```bash
export ALL_PROXY=socks5h://USER:PASS@HOST:SOCKS_PORT
export http_proxy=http://USER:PASS@HOST:HTTP_PORT
export https_proxy=http://USER:PASS@HOST:HTTP_PORT
```

> `socks5h` 的 `h` 表示 **DNS 也在远端解析**，避免本地 DNS 污染；`socks5` 则在本地解析域名。

---

## 排查

**连不上，超时**

云厂商安全组 / 面板防火墙要先放行端口，**两个端口都要放**。脚本只处理系统内的 `ufw` / `firewalld`，管不到 AWS / 阿里云 / 腾讯云的控制台安全组。

**连接被拒**

```bash
bash socks5-install.sh --status        # 看服务和监听
journalctl -u gost-socks5 -n 50        # 看日志
```

**验证端口和协议**

```bash
# 端口
nc -vz HOST PORT

# SOCKS5 握手：返回 05 02 表示需要用户名密码
printf '\x05\x01\x00' | nc HOST SOCKS_PORT | xxd

# HTTP 代理：直接拿首页
curl -x http://USER:PASS@HOST:HTTP_PORT -I https://www.google.com
```

**换密码 / 换端口**

```bash
bash socks5-install.sh --user 新用户 --pass 新密码 --port 端口 --http-port 端口
```

重跑会覆盖服务配置并重启。

---

## 安全建议

- 随机端口比 1080 / 8080 安全，能挡掉大部分无脑扫描
- 密码 20 位随机，不要改成弱口令
- 云安全组建议只放行你自己的出口 IP，而不是 `0.0.0.0/0`
- 需要更强隐蔽性可以把 SOCKS5 换成 `socks5+tls`，把 unit 里的 `-L` 改成：

```
-L socks5+tls://user:pass@:port
```

客户端勾选 TLS 即可（自签证书需允许不安全连接）。

---

## 卸载

```bash
bash socks5-install.sh --uninstall
```

清理 `gost-socks5.service`、`/usr/local/bin/gost`、`/etc/gost-socks5.env`。
