# sock5

gost 代理一键部署脚本集。跑一条命令，自动生成 **随机用户名 / 随机密码 / 未被占用的随机端口**，直接给出可用连接串。

提供三个独立单文件脚本，按需选一个：

| 脚本 | 协议 | 一键命令 |
|---|---|---|
| `socks5-install.sh` | SOCKS5 + HTTP | `curl -fsSL https://raw.githubusercontent.com/76hvc/sock5/main/socks5-install.sh \| bash` |
| `socks5-only.sh` | 仅 SOCKS5 | `curl -fsSL https://raw.githubusercontent.com/76hvc/sock5/main/socks5-only.sh \| bash` |
| `http-only.sh` | 仅 HTTP | `curl -fsSL https://raw.githubusercontent.com/76hvc/sock5/main/http-only.sh \| bash` |
| `install.sh` | 交互菜单 | `curl -fsSL https://raw.githubusercontent.com/76hvc/sock5/main/install.sh \| bash` |

三个脚本都是**自包含单文件**，不依赖彼此，`curl | bash` 直接跑。支持 Debian / Ubuntu / CentOS / RHEL / Rocky / Alma / Fedora / Arch，架构 `amd64 / arm64 / armv7 / armv6 / 386`。

---

## 交互菜单

```bash
curl -fsSL https://raw.githubusercontent.com/76hvc/sock5/main/install.sh | bash
```

```
代理一键部署
--------------------------------------------------------------
  1) SOCKS5 + HTTP  两个一起装（推荐）
  2) 仅 SOCKS5
  3) 仅 HTTP
  4) 查看当前状态
  5) 打印连接串
  6) 卸载
  0) 退出
--------------------------------------------------------------
请选择 [1]:
```

也可以非交互：

```bash
bash install.sh both        # SOCKS5 + HTTP
bash install.sh socks5      # 仅 SOCKS5
bash install.sh http        # 仅 HTTP
bash install.sh status
bash install.sh url
bash install.sh uninstall
```

---

## 输出长这样

**双协议（`socks5-install.sh`）**

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
--------------------------------------------------------------
```

**仅 SOCKS5（`socks5-only.sh`）**

```
--------------------------------------------------------------
  SOCKS5 部署完成
--------------------------------------------------------------
  主机 (Host)   : 3.148.165.194
  用户 (User)   : s5q1xvdnjk
  密码 (Pass)   : r68ieI9feqbnJ5QSTNAo

  ── SOCKS5 ──────────────────────────────────
  端口 (Port)   : 47321
  连接串 (推荐) : socks5h://s5q1xvdnjk:r68ieI9feqbnJ5QSTNAo@3.148.165.194:47321
--------------------------------------------------------------
```

**仅 HTTP（`http-only.sh`）**

```
--------------------------------------------------------------
  HTTP 代理部署完成
--------------------------------------------------------------
  主机 (Host)   : 3.148.165.194
  用户 (User)   : s5q1xvdnjk
  密码 (Pass)   : r68ieI9feqbnJ5QSTNAo

  ── HTTP ────────────────────────────────────
  端口 (Port)   : 58104
  连接串        : http://s5q1xvdnjk:r68ieI9feqbnJ5QSTNAo@3.148.165.194:58104
--------------------------------------------------------------
```

---

## 参数

所有脚本共用同一套参数：

| 参数 | 说明 |
|---|---|
| `--port N` | 指定端口。双协议脚本指 SOCKS5 端口；`http-only.sh` 指 HTTP 端口 |
| `--http-port N` | 指定 HTTP 代理端口（双协议脚本） |
| `--proto socks5\|http\|both` | 只开某个协议或两个都开（`socks5-install.sh` 用） |
| `--no-http` | 等价于 `--proto socks5` |
| `--user U --pass P` | 指定账号密码，两协议共用 |
| `--status` | 查看服务状态、监听、活跃连接、连接串 |
| `--url` | 只打印连接串（纯文本，可直接管道） |
| `--uninstall` | 卸载服务 + 二进制 + 凭据 |
| `--help` | 帮助 |

环境变量：

```bash
GITHUB_MIRROR=https://ghfast.top/ bash socks5-install.sh   # 自定义 gost 下载加速
SOCK5_BASE_URL=... bash install.sh                          # 自定义 install.sh 的下载源
```

`--url` 输出示例：

```bash
$ bash socks5-install.sh --url
socks5h://s5q1xvdnjk:r68ieI9feqbnJ5QSTNAo@3.148.165.194:47321
http://s5q1xvdnjk:r68ieI9feqbnJ5QSTNAo@3.148.165.194:58104
```

---

## 它做了什么

1. 检测架构，从 GitHub Releases 下载最新 `gost` 到 `/usr/local/bin/gost`（直连失败自动切 3 个加速镜像）
2. 用 `python3` 真实 `bind()` 探测空闲端口（TCP + IPv4/IPv6 双栈），范围 `20000-65000`
   - 双协议时 SOCKS5 端口先挑，HTTP 端口再挑并**排除已选的 SOCKS5 端口**（此时两者都还没监听，靠监听表检测不到冲突）
   - 无 python3 时退回 `ss` / `netstat` / `lsof` / `/dev/tcp` 四层兜底
3. 用 `openssl rand` 生成 8 位随机用户名、20 位随机密码，只含 `[A-Za-z0-9]`，保证能直接拼进 URL 不用转义
4. 写入 `/etc/systemd/system/gost-proxy.service`：

```ini
# 双协议
ExecStart=/usr/local/bin/gost -L socks5://<user>:<pass>@:<socks_port> -L http://<user>:<pass>@:<http_port>

# 仅 SOCKS5
ExecStart=/usr/local/bin/gost -L socks5://<user>:<pass>@:<socks_port>

# 仅 HTTP
ExecStart=/usr/local/bin/gost -L http://<user>:<pass>@:<http_port>
```

`Restart=always` + 开机自启 + `LimitNOFILE=1048576`

5. 自动放行 `ufw` / `firewalld` / `iptables`（几个端口就放几个）
6. 探测公网 IP（ipify → ifconfig.me → ipinfo → EC2 metadata 兜底）
7. 本地自检：通过刚起的代理请求 `api.ipify.org`，确认出口真的通
8. 凭据落盘到 `/etc/gost-proxy.env`（`chmod 600`，仅 root 可读）

```ini
S5_PROTO=both
S5_USER=s5q1xvdnjk
S5_PASS=r68ieI9feqbnJ5QSTNAo
S5_SOCKS_PORT=47321
S5_HTTP_PORT=58104
S5_PORT=47321
```

自动兼容旧版 `gost-socks5.service` / `/etc/gost-socks5.env`：安装时先停掉旧服务再接管，`--status` 也能读旧状态文件。

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

支持 `CONNECT` 隧道，HTTPS 站点也能过。

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
git config --global http.proxy socks5h://USER:PASS@HOST:SOCKS_PORT
git config --global http.proxy http://USER:PASS@HOST:HTTP_PORT   # 或用 HTTP
git config --global --unset http.proxy                            # 撤销
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

云厂商安全组 / 面板防火墙要先放行端口，**几个端口就放几个**。脚本只处理系统内的 `ufw` / `firewalld`，管不到 AWS / 阿里云 / 腾讯云的控制台安全组。

**连接被拒**

```bash
bash socks5-install.sh --status        # 看服务和监听
journalctl -u gost-proxy -n 50         # 看日志
```

**验证端口和协议**

```bash
nc -vz HOST PORT                                        # 端口
printf '\x05\x01\x00' | nc HOST SOCKS_PORT | xxd        # SOCKS5 握手，05 02 = 需要认证
curl -x http://USER:PASS@HOST:HTTP_PORT -I https://www.google.com   # HTTP 代理
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
- 需要更强隐蔽性可以把 SOCKS5 换成 `socks5+tls`：

```
-L socks5+tls://user:pass@:port
```

客户端勾选 TLS 即可（自签证书需允许不安全连接）。

---

## 项目结构

```
.
├── src/core.sh              # 唯一维护点：全部逻辑
├── tools/build.sh           # 从 core.sh 生成三个单文件脚本
├── socks5-install.sh        # 生成物（勿手改）
├── socks5-only.sh           # 生成物（勿手改）
├── http-only.sh             # 生成物（勿手改）
├── install.sh               # 交互菜单入口
├── tests/
│   ├── selftest.sh          # 纯函数逻辑测试
│   ├── dryrun.sh            # stub systemd 后验证生成的 unit
│   └── syntax.sh            # 全量 bash -n
└── .github/workflows/ci.yml # 语法 / CRLF / shellcheck / 构建一致性 / 测试
```

改逻辑只改 `src/core.sh`，然后：

```bash
bash tools/build.sh
bash tests/selftest.sh
bash tests/dryrun.sh
```

CI 会校验生成物与 `src/core.sh` 一致，忘了重新构建会直接失败。

---

## 卸载

```bash
bash socks5-install.sh --uninstall
```

清理 `gost-proxy.service`、`/usr/local/bin/gost`、`/etc/gost-proxy.env`，同时清理旧版 `gost-socks5` 的残留。
