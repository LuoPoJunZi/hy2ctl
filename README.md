<div align="center">

<h1>hy2ctl</h1>

<p><strong>Hysteria2 一键部署与管理面板</strong></p>

<p>纯 Bash · 面向 Linux VPS · 配置、分享、诊断与备份</p>

<p>
  <a href="https://www.gnu.org/software/bash/"><img src="https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&amp;logo=gnu-bash" alt="Bash"></a>
  <a href="https://v2.hysteria.network/"><img src="https://img.shields.io/badge/Core-Hysteria%20v2-blueviolet?style=flat-square" alt="Hysteria2"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square" alt="MIT License"></a>
</p>

<p>
  <a href="#quick-start">快速开始</a> ·
  <a href="#menu">菜单说明</a> ·
  <a href="#troubleshooting">常见问题</a> ·
  <a href="docs/development.md">开发文档</a> ·
  <a href="CHANGELOG.md">更新记录</a> ·
  <a href="https://github.com/LuoPoJunZi/hy2ctl">GitHub 仓库</a>
</p>

</div>

---

## 1. 这是什么？适合谁用？

`hy2ctl` 是一个纯 Bash 的终端管理面板，帮你把 Hysteria2 的常见操作做成菜单化流程：

- 安装/更新内核
- 生成配置（CA/自签）
- 导出客户端配置
- 诊断与日志排障
- 备份与恢复

适合人群：

- 新手：不熟悉 YAML 与 systemd，希望“能跑起来优先”
- 运维：希望快速重复部署，减少手工失误
- 开发者：需要在现有脚本基础上继续扩展功能

---

## 2. 项目能力总览

- 一键安装面板与 Hysteria2 内核
- 双证书模式：CA / 自签
- 自签 SNI 预设域名（含手动输入）
- 带宽参数可配（`up_mbps` / `down_mbps`）
- 客户端配置导出：
  - `hysteria2://` 分享链接
  - Sing-box Outbound JSON
  - v2rayN / NekoRay YAML 片段
  - 完整 Sing-box 模板
- 一键环境诊断（并导出日志）
- 最近诊断报告回看
- 手动备份与一键恢复
- 启动失败自动回滚（降低改坏配置风险）

---

## 3. 仓库结构（接手开发先看这里）

```text
.
├── src/                            # 可维护的模块化源码
│   ├── bootstrap.sh                # 版本、路径与默认值
│   ├── core/                       # 输出、校验、编码、文件和元数据
│   ├── hysteria/                   # 安装、证书、配置、权限、服务和回滚
│   ├── clients/                    # Hysteria2、Sing-box、v2rayN 配置输出
│   ├── operations/                 # 诊断、备份与恢复
│   ├── panel/                      # 主菜单、服务/备份子菜单与面板更新
│   └── main.sh                     # 启动入口
├── hy2.sh                          # 自动生成的单文件发布版，请勿手工编辑
├── install.sh                      # 安装入口，部署单文件 hy2 并自动安装/更新内核
├── scripts/
│   ├── panel-modules.list          # 有序源码清单，构建与发布检查共用
│   ├── lib/                        # 工程辅助库，不进入 VPS 单文件
│   ├── verify.sh                   # 本地/CI 统一检查入口
│   ├── build-panel.sh              # 确定性生成 hy2.sh
│   └── benchmark.sh                # 无网络面板性能对比
├── tests/
│   ├── helpers/                    # 公共断言、临时环境与模拟命令
│   ├── fixtures/                   # 示例配置、异常元数据与日志
│   ├── unit/                       # 按职责划分的 Bats 单元测试
│   ├── e2e/                        # 冒烟、配置/导出回放与边界检查
│   └── acceptance/                 # 独立 Linux VPS 验收清单
├── docs/
│   ├── architecture.md             # 模块职责与运行约定
│   ├── development.md              # 开发、测试和性能检查
│   └── release.md                  # 发布流程与验收要求
└── .github/workflows/
    ├── lint.yml                    # Ubuntu + Debian 验证矩阵
    └── release.yml                 # 自动发布流程
```

---

<a id="quick-start"></a>

## 4. 快速开始（新手照着做）

### 4.1 登录 VPS（root）

```bash
ssh root@你的服务器IP
```

### 4.2 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LuoPoJunZi/hy2ctl/main/install.sh)
```

安装器会检查 `curl` / `openssl`，仅安装缺失的基础依赖；`wget` 只是可选下载回退，不强制安装。依赖齐全时不会刷新软件包索引，因此不会被无关的坏软件源拦住；缺少依赖时保留包管理器原始错误，不绕过签名验证。随后部署管理面板并自动安装或更新 Hysteria2 内核，全部成功后直接进入主菜单。

### 4.3 打开面板

```bash
hy2
```

### 4.4 推荐最短流程

一键安装脚本会自动安装或更新 Hysteria2 内核，无需再进入菜单单独安装。以后如需更新内核，可进入菜单 `11` 操作。

1. 菜单 `1`：配置节点（直接回车默认使用自签证书）
2. 菜单 `2`：复制客户端配置
3. 菜单 `8`：执行一键诊断

---

<a id="menu"></a>

## 5. 菜单说明（逐项解释）

```text
=====================================================
  hy2ctl 管理面板 v26.11.10 |  快捷启动: hy2
=====================================================
  内核版本: v2.13.0    服务状态: 运行中
-----------------------------------------------------
  节点核心管理
    (1)  节点配置（CA / 自签）
    (2)  客户端配置与分享

  服务运行控制
    (3)  服务启动与控制
    (4)  实时运行日志
    (5)  完全卸载清理
    (6)  常用指令速查
    (7)  Sing-box 完整模板
    (8)  一键环境诊断
    (9)  最近诊断报告
    (10) 配置备份与恢复
    (11) 面板与内核更新
    (0)  退出面板
=====================================================
➡️ 请选择操作 [0-11]:
```

- `1`：生成并写入 `/etc/hysteria/config.yaml`，自动重启服务
- `2`：展示连接参数与客户端片段
- `3`：服务启停和状态查看
- `4`：跟踪服务日志（实时）
- `5`：卸载清理（高风险操作）
- `6`：排障常用命令速查
- `7`：完整 Sing-box 模板输出（兼容 sing-box 1.14+，自签模式包含公钥固定）
- `8`：环境健康检查 + 报告导出
- `9`：查看最近一次诊断报告
- `10`：手动备份/恢复配置
- `11`：安装/更新 Hysteria2 内核，或更新 `/usr/local/bin/hy2` 管理面板脚本

菜单 `11` 的二级菜单：

```text
    (1) 安装/更新 Hysteria2 内核
    (2) 更新 hy2ctl 管理面板
    (0) 返回主菜单
```

---

## 6. CA 与自签怎么选？

### CA 模式（选项 1）

适合：有域名、希望证书链标准化。  
要求：域名已解析到 VPS，80/443 网络环境允许证书申请流程。

### 自签模式（选项 2）

适合：没有域名，想快速用 IP 连通。  
要求：原生 Hysteria2 客户端必须开启 `insecure=true`，并使用脚本导出的 `pinSHA256` 固定证书；Sing-box 1.13+ 使用 `certificate_public_key_sha256` 固定证书公钥。

注意：自签节点使用 Xray 的功能最低要求为 v2rayN `7.17.1+`、Xray-core `26.2.6+`，不代表当前安全推荐；另需修复旧版下载器风险的 v2rayN `7.24.9+`，并按第 7.4 节核对客户端内核的证书信任修复。分享链接同时包含 Hysteria2 官方的 `pinSHA256` 和 Xray 分享规范的 `pcs`；v2rayN 会把 `pcs` 映射为 `pinnedPeerCertSha256`，链接不再输出已移除的 `allowInsecure`。Sing-box 配置则使用独立的公钥 SHA-256 固定字段。任一自签证书校验值读取失败时，脚本都会拒绝生成相应客户端配置，请通过菜单 `1` 重新配置证书。重新生成自签证书后必须重新导入节点。长期使用仍建议优先采用 CA 域名证书模式。

自签模式支持 SNI 预设：

- `bing.com`
- `www.cloudflare.com`
- `www.apple.com`
- `www.microsoft.com`
- `www.amazon.com`
- 或手动输入

---

## 7. 客户端接入指南

### 7.1 Windows（v2rayN / NekoRay）

- 在面板菜单 `2` 复制 `hysteria2://` 链接导入
- 或复制 YAML 片段做手动配置
- 自签模式按 Hysteria2 官方 URI 规范使用 `insecure=1` 和 `pinSHA256`；CA 证书模式省略 `insecure`
- 自签链接额外包含 `pcs`，供 v2rayN/Xray 映射为 `pinnedPeerCertSha256`，不再输出 `allowInsecure`
- Xray 自签功能最低兼容要求：v2rayN `7.17.1+`、Xray-core `26.2.6+`，不是当前安全推荐版本。v2rayN 至少使用修复旧版下载器风险的 `7.24.9+`，建议 `7.25.6` 或更新稳定版；Xray 证书信任修复请同时按下方安全说明检查。
- 通过 v2rayN 使用 Sing-box `1.14` 内核时建议 v2rayN `7.25.4+`，避免旧版客户端生成不兼容的内核配置；参见[官方更新说明](https://github.com/2dust/v2rayN/releases/tag/7.25.4)。

### 7.2 Android / iOS（Sing-box）

- 菜单 `2` 复制 Outbound 片段
- 菜单 `7` 复制完整模板（适合新建配置，使用新版 `rule_set` 规则格式）
- 自签模式要求 Sing-box `1.13.0+`，脚本会自动加入 `certificate_public_key_sha256` 公钥固定
- 完整模板要求 Sing-box `1.14.0+`，远程规则集通过顶层 `http_clients` 和 `route.default_http_client` 使用 `proxy` 出站下载，不再使用已弃用的 `download_detour`
- 建议使用 Sing-box `1.14.4` 或更新稳定版，稳定版验证目标同步为 `1.14.4`；`1.13.0` / `1.14.0` 仅表示对应配置的最低功能兼容要求，不是当前安全建议。CI 保留 `1.14.0` 语法兼容验证。`1.15` alpha 仍处于测试阶段，不作为默认依赖，不在现有模板中替换 `certificate_public_key_sha256`；参见[官方更新说明](https://github.com/SagerNet/sing-box/releases/tag/v1.14.4)和[测试版日志](https://sing-box.sagernet.org/changelog/)。

### 7.3 自签模式注意

必须确保客户端配置中：

- `insecure: true`
- `certificate_public_key_sha256` 为脚本从当前服务器证书生成的值

### 7.4 客户端与证书信任库安全更新（2026-11-10 核对）

- Xray-core 官方因证书信任问题撤回了 `26.10.10` / `26.10.17`，证书修复始于 `26.10.21`。后续的 `26.10.29` 又因 Linux MPTCP 风险被撤回，`26.10.31` 起默认关闭 MPTCP 以降低攻击面；当前建议使用 `26.11.9` 或更新稳定版。关闭 MPTCP 仅为缓解措施，相关 Linux / Android 系统仍需核对系统内核补丁。参见[证书安全公告](https://github.com/XTLS/Xray-core/releases/tag/v26.10.21)、[MPTCP 缓解说明](https://github.com/XTLS/Xray-core/releases/tag/v26.10.31)和[当前稳定版](https://github.com/XTLS/Xray-core/releases/tag/v26.11.9)。
- Sing-box `1.14.4` 使用 Go `1.26.10` 构建并更新了内置 CA 库，建议升级到该版或更新稳定版；参见[上游变更记录](https://github.com/SagerNet/sing-box/compare/v1.14.3...v1.14.4)。最低功能兼容验证不代表旧版满足当前证书安全建议。
- CA / 自签用户均应核对客户端实际运行的 Xray-core / Sing-box 内核。v2rayN `7.25.6` 的[发布说明](https://github.com/2dust/v2rayN/releases/tag/7.25.6)仍引用已撤回的 Xray `26.10.10`，仅更新 v2rayN 不代表内核已修复。客户端内核需在客户端更新；VPS 菜单 `11` 不会更新电脑上的客户端内核。
- Ubuntu [USN-8944-1](https://ubuntu.com/security/notices/USN-8944-1) 移除了涉及中间 CA 证书被攻破的根证书。Ubuntu 26.04 的 `ca-certificates` 修复版本为 `20260816ubuntu0.26.04.1`；22.04 / 24.04 / 26.10 使用各自公告版本，不能跨发行版套用版本号。系统更新后按发行版说明重启仍使用旧信任库的进程。
- Go [CVE-2026-111943](https://go.dev/issue/82345) 的工具链修复分别位于 `1.26.10`、`1.27.3`；`1.27.0` 至 `1.27.2` 不能因为大于 `1.26.10` 就判为已修复。**仅升级系统 Go 不会修复现有二进制**，需使用上游包含修复的构建，厂商回移修复另行核实。
- 软件包版本与 Go 构建版本只是分别核对该公告的依据，不证明所有 TLS 路径安全，也不涵盖自定义或内置 CA 库。不要通过 `curl -k`、关闭证书校验、移除证书固定或重新导入问题根证书来规避错误；现有节点不会因此自动重签证书或改写配置。

### 7.5 Linux 系统内核与 MPTCP 安全检查

[CVE-2026-98432](https://ubuntu.com/security/CVE-2026-98432) 涉及 Linux IPv4 TCP 连接处理，可导致远程代码执行。[Go 安全团队](https://www.openwall.com/lists/oss-security/2026/10/30/1)说明：Go 1.24 起 Linux 监听套接字默认启用 MPTCP，但漏洞并不限于 MPTCP，关闭它不能代替系统内核补丁。Hysteria2 节点使用 UDP，也不能据此推断整台 VPS 上的 IPv4 TCP 服务不受影响。

菜单 `8` 只读收集正在运行的 Linux 内核版本、发行版、对应映像软件包和 MPTCP 内核开关，并写入菜单 `9` 的诊断报告。Debian/Ubuntu 查询与 `uname -r` 匹配的映像包，RPM 系统查询对应 `/boot/vmlinuz-*` 文件的所属包；只安装了新内核包并不代表当前运行内核已更新。

补丁修复状态统一提示 `WARN` / 需人工核验，不根据通用内核版本号、Hysteria2/Go 版本或 MPTCP 已关闭就判为已修复。MPTCP 开关为 `1` 不代表实际存在监听或公网暴露；接口缺失、读取失败或异常内容也不能证明安全。容器、自编译内核或缺少查询工具时，运行内核包可能显示未知。

按发行版及实际内核分支核对正式安全公告，Ubuntu 的 generic / oracle 等分支需要分别确认。2026-11-09 更新的 Ubuntu 状态页仍将 26.04 的 `linux` / `linux-oracle` 列为修复处理中，不能将 `-proposed` 测试源中的版本当成已正式交付。诊断不会刷新索引、安装内核、启用测试源、设置 `GODEBUG`、修改 MPTCP 或防火墙；完成系统补丁更新后，按官方说明重启并核验生效状态。菜单 `11` 更新面板与 Hysteria2，不更新 Linux 系统内核。

---

<a id="troubleshooting"></a>

## 8. 常见问题与排障

### 8.1 服务起不来

先做：

1. 菜单 `8` 一键诊断
2. 菜单 `9` 查看最近诊断报告
3. 菜单 `4` 查看实时日志

菜单 `8` 会在结果末尾给出结构化排障建议：`结论 + 建议 + 命令`，可直接按命令执行。
诊断还会分级检查 Hysteria2 内核版本：低于 `v2.9.2` 时标记为高危安全风险并提示立即通过菜单 `11` 更新；达到安全基线但低于 `v2.13.0` 时提示兼容性与稳定性更新。低于 `v2.12.3` 的旧内核还会提示 HTTP 代理传输 10 秒断开、Linux 端口跳跃误重定向出站 UDP 修复；`v2.12.3` 则提示 `v2.13.0` 的分包 QUIC 嗅探与域名 ACL 兼容修复、Chrome QUIC 指纹模仿更新，不误报已修复的问题。安全基线依据 Hysteria 官方[安全公告](https://github.com/HyNetworks/hysteria/security/advisories)，兼容性建议依据 [v2.12.3 更新说明](https://github.com/HyNetworks/hysteria/releases/tag/app/v2.12.3)和 [v2.13.0 更新说明](https://github.com/HyNetworks/hysteria/releases/tag/app/v2.13.0)。

推荐版本只是诊断建议，不是安装版本锁定，也不代表该范围内所有版本都存在同一种漏洞。面板仍调用官方安装器安装或更新内核；默认服务端配置不启用 sniff/ACL，不会因为提升推荐版本而改写现有配置。

菜单 `8` 还会独立记录 Hysteria2 `Toolchain` 中的 Go 构建版本和本机 `ca-certificates` 包版本，检查上述证书安全公告。Go 开发版/厂商后缀、命令失败、缺少工具、无法读取或未覆盖的发行版均提示 `WARN` / 状态未知，不以当前内核版本或 HTTPS 偶然可连通代替修复核验。Ubuntu 使用 `dpkg --compare-versions` 按对应发行版比较包版本；其他发行版只报告可读取的包版本并提示人工核对。检查不联网刷新索引、不安装软件包、不修改源或 TLS 设置；报告中的更新命令仅供用户确认后手动执行。自定义/内置 CA 库仍需单独检查。

Hysteria2 2.12.2 增加了 `quic.disableStatelessReset` 作为兼容性开关。面板不会默认写入该选项，保持 Stateless Reset 启用，以保留移动端休眠后的快速重连能力；只有确认特定网络环境与 Stateless Reset 冲突时，才建议手动设为 `true` 进行排障。

### 8.2 常见错误：`config.yaml: permission denied`

脚本已做动态权限修复（按 systemd 实际运行用户设置目录与文件权限）。  
如果仍有异常，可手动检查：

```bash
systemctl show -p User,Group hysteria-server.service
namei -l /etc/hysteria/config.yaml
```

### 8.3 配置改坏了怎么办

- 菜单 `10` -> 恢复最近手动备份
- 或重新走菜单 `1` 生成新配置

配置变更前会先生成完整四文件快照，成功后才替换当前快照记录；备份失败不会破坏上一份自动快照。配置启用和手动恢复会在重启后等待两秒再确认服务状态；若进程立即退出，尝试恢复操作前的配置、元数据、证书和私钥。回滚后的服务状态也会检查，失败时显示排障提示和日志。该短时检查不代替实际客户端连通性验收。

### 8.4 公网 IP 探测失败

脚本先通过外部服务探测 IPv4，再探测 IPv6，只接受格式合法的公网候选地址；错误页面、保留地址及请求失败时的部分响应不会写入节点元数据。外部探测失败时仍可回退到格式合法的本机地址，以兼容 NAT/内网部署，但菜单 `8` 会明确警告“本机地址不代表公网可达”。如果使用了私网分享地址，应先确认公网 IP、云安全组和 UDP 端口映射，不能把面板配置成功等同于外网可连接。

### 8.5 Windows Sing-box TUN 高 CPU / Winsock 10055

2026-10-03 的[上游用户报告 #4602](https://github.com/SagerNet/sing-box/issues/4602)描述了 Windows/SFW `1.14.2` 在 TUN 模式下出现大量 IPv6 UDP 连接和 Winsock `10055` 的现象；报告者关闭 Teredo 后现象停止。截至 2026-10-31，该报告仍未关闭，根因和影响范围尚未确认。`1.14.4` 虽有 TUN 和连接清理改进，但没有确认解决此报告，不能据此断言面板模板有问题或该故障已修复。

- 先记录客户端/内核版本、是否使用 TUN、最近日志及资源占用；同一节点临时改用非 TUN 系统代理，对比问题是否只在 TUN 下出现。
- 可只读检查 Teredo 状态：`netsh interface teredo show state`。仅当症状与报告一致时，在维护窗口由用户决定是否做可恢复的 Teredo 对照测试；先记录原配置，测试后恢复，不直接关闭系统 IPv6。
- 面板运行在 Linux VPS，不会修改 Windows 网络配置；VPS 服务运行正常也不能排除客户端路由问题。分享日志或配置前请隐藏认证密码、节点地址及证书固定值。

### 8.6 一键安装提示“基础依赖准备失败”（含甲骨文云 Ubuntu）

这一步发生在生成节点配置之前，不是 Hysteria2 YAML 配置错误。先确认必要命令和软件源：

```bash
command -v curl openssl
sudo apt-get update
grep -RnsE '^[[:space:]]*(deb(-src)?[[:space:]]|URIs:|Suites:)' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null
```

甲骨文云 Ubuntu 26.04 ARM64 的一次实际故障是安全源写成 `URIs: https:///ubuntu-ports/`，缺少主机名，APT 报 `https:/ubuntu-ports ... does not have a Release file`。该问题来自软件源配置，不是甲骨文云专属限制。应先备份实际源文件，仅修正错误 URI；Ubuntu Ports 的正确基础地址是 `https://ports.ubuntu.com/ubuntu-ports/`，保留对应系统的 suite、组件和 `Signed-By`。不要套用 ARM64 地址到 amd64，也不要删除 Docker 等其他源或关闭 APT 签名验证。参见[官方仓库的 resolute-security 元数据](https://ports.ubuntu.com/ubuntu-ports/dists/resolute-security/Release)。

安装器仅在必要命令缺失时使用 APT；安装阶段为 dpkg 锁设置 60 秒等待，并限制下载重试和 HTTP/HTTPS 超时。索引锁不一定受 dpkg 等待选项影响，失败时以原始错误为准；不要删除锁文件或终止系统更新进程。依赖齐全时跳过 APT 不代表软件源已修好，仍需单独修复软件源以恢复系统安全更新。

---

## 9. 诊断与报告文件

诊断菜单会导出：

- `/tmp/hy2-diagnose-YYYYMMDD-HHMMSS.XXXXXX.log`（随机后缀避免同秒覆盖）
- `/tmp/hy2-diagnose-latest.log`（最近一次快捷路径）

报告以仅当前运行用户可读写的权限创建；最新报告使用原子替换，不跟随预置符号链接。快捷路径更新失败时会提示使用本次独立报告。

建议提 Issue 时附上：

- 诊断报告
- 最近 20 行 `journalctl` 日志
- 你选择的证书模式（CA/自签）

---

## 10. 开发与维护

开发请修改 `src/`，不要手工编辑生成版 `hy2.sh`。完整指南已分离：

- [架构与模块边界](docs/architecture.md)
- [开发、测试与性能检查](docs/development.md)
- [发布流程与验收](docs/release.md)
- [真实 Linux VPS 验收清单](tests/acceptance/README.md)

```bash
bash scripts/build-panel.sh
bash scripts/verify.sh all
```

---

## 11. 贡献建议

欢迎 PR 方向：

- 更多客户端配置模板
- 更细粒度诊断项
- 多语言文案
- 更完善的单元化脚本测试

---

## 12. 开源协议

本项目基于 [MIT License](LICENSE) 协议开源。
