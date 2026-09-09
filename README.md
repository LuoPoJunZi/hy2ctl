# ⚡ hy2ctl 管理面板

<div align="center">

一个面向 VPS 的 Hysteria2 一键运维脚本。<br>
目标：**让新手 5 分钟部署成功**，也让开发者可以**低成本二次开发**。

[![Bash](https://img.shields.io/badge/Language-Bash-4EAA25?style=flat-square&logo=gnu-bash)](https://www.gnu.org/software/bash/)
[![Hysteria2](https://img.shields.io/badge/Core-Hysteria%20v2-blueviolet?style=flat-square)](https://v2.hysteria.network/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

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
│   ├── panel/                      # 面板更新与主菜单
│   └── main.sh                     # 启动入口
├── hy2.sh                          # 自动生成的单文件发布版，请勿手工编辑
├── install.sh                      # 安装入口，部署单文件 hy2 并自动安装/更新内核
├── scripts/
│   ├── verify.sh                   # 本地/CI 一键检查入口
│   ├── build-panel.sh              # 从 src/ 确定性生成 hy2.sh
│   ├── check-menu-sync.sh          # 菜单与 README 一致性检查
│   ├── check-brand-sync.sh         # 项目名称与仓库地址一致性检查
│   ├── check-version-sync.sh       # 版本号与 README 标识一致性检查
│   └── smoke-e2e.sh                # 无特权端到端冒烟测试
├── tests/
│   ├── e2e/
│   │   ├── config-flow.sh          # CA/自签交互配置与回滚回放
│   │   └── client-render.sh        # 客户端 JSON 解析与导出安全测试
│   └── unit/
│       └── hy2_core.bats           # 核心函数回归测试（bats）
└── .github/workflows/
    ├── lint.yml                    # Ubuntu + Debian 验证矩阵
    └── release.yml                 # 自动发布流程
```

---

## 4. 快速开始（新手照着做）

### 4.1 登录 VPS（root）

```bash
ssh root@你的服务器IP
```

### 4.2 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LuoPoJunZi/hy2ctl/main/install.sh)
```

安装器会依次安装基础依赖、部署管理面板并自动安装或更新 Hysteria2 内核，全部成功后直接进入主菜单。

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

## 5. 菜单说明（逐项解释）

```text
=====================================================
  hy2ctl 管理面板 v26.9.9 |  快捷启动: hy2
=====================================================
  内核版本: v2.12.2    服务状态: 运行中
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

注意：自签节点使用 Xray 时要求 v2rayN `7.17.1+`、Xray-core `26.2.6+`，并应使用修复旧版下载器中间人攻击风险的 v2rayN `7.24.9+`。分享链接同时包含 Hysteria2 官方的 `pinSHA256` 和 Xray 分享规范的 `pcs`；v2rayN 会把 `pcs` 映射为 `pinnedPeerCertSha256`，链接不再输出已移除的 `allowInsecure`。Sing-box 配置则使用独立的公钥 SHA-256 固定字段。任一自签证书校验值读取失败时，脚本都会拒绝生成相应客户端配置，请通过菜单 `1` 重新配置证书。重新生成自签证书后必须重新导入节点。长期使用仍建议优先采用 CA 域名证书模式。

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
- Xray 兼容要求：v2rayN `7.17.1+`、Xray-core `26.2.6+`。安全方面应使用 v2rayN `7.24.9+`；旧版 Xray 不保证支持自签证书固定。

### 7.2 Android / iOS（Sing-box）

- 菜单 `2` 复制 Outbound 片段
- 菜单 `7` 复制完整模板（适合新建配置，使用新版 `rule_set` 规则格式）
- 自签模式要求 Sing-box `1.13.0+`，脚本会自动加入 `certificate_public_key_sha256` 公钥固定
- 完整模板要求 Sing-box `1.14.0+`，远程规则集通过顶层 `http_clients` 和 `route.default_http_client` 使用 `proxy` 出站下载，不再使用已弃用的 `download_detour`

### 7.3 自签模式注意

必须确保客户端配置中：

- `insecure: true`
- `certificate_public_key_sha256` 为脚本从当前服务器证书生成的值

---

## 8. 常见问题与排障

### 8.1 服务起不来

先做：

1. 菜单 `8` 一键诊断
2. 菜单 `9` 查看最近诊断报告
3. 菜单 `4` 查看实时日志

菜单 `8` 会在结果末尾给出结构化排障建议：`结论 + 建议 + 命令`，可直接按命令执行。
诊断还会检查 Hysteria2 内核版本；低于 `v2.12.2` 时会提示通过菜单 `11` 更新，以获得移动端快速重连、IPv6 mimic 和小 MTU 稳定性修复。

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

---

## 9. 诊断与报告文件

诊断菜单会导出：

- `/tmp/hy2-diagnose-YYYYMMDD-HHMMSS.log`
- `/tmp/hy2-diagnose-latest.log`（最近一次快捷路径）

建议提 Issue 时附上：

- 诊断报告
- 最近 20 行 `journalctl` 日志
- 你选择的证书模式（CA/自签）

---

## 10. 二次开发接手指南（重点）

### 10.1 开发前准备

```bash
git clone https://github.com/LuoPoJunZi/hy2ctl.git
cd hy2ctl
```

### 10.2 本地检查（每次改动后执行）

```bash
chmod +x scripts/verify.sh scripts/build-panel.sh
./scripts/verify.sh
```

`verify.sh` 会执行：

- `bash -n` 语法检查
- 模块源码与生成版 `hy2.sh` 一致性检查
- 仓库文本规范检查（LF、文件末尾换行、尾随空白、YAML Tab）
- `shellcheck` 静态检查（error 级）
- 菜单与 README 预览一致性检查
- 项目名称、仓库地址与安装/更新入口一致性检查
- 版本号与 README 标识一致性检查
- 发布包防污染检查（本地记忆文件、临时目录、已撤销模块化文件）
- 无特权端到端冒烟测试（配置生成/元数据解析/SNI 选择/分享片段/重启失败回滚）
- `bats` 核心函数回归测试（`tests/unit`）
- 交互配置流程回放测试（`tests/e2e/config-flow.sh`）
- Sing-box JSON 标准解析与客户端证书固定导出测试（`tests/e2e/client-render.sh`）
- 运行时边界测试（`tests/e2e/runtime-contracts.sh`）：输入中断、元数据状态隔离、实时菜单状态与失败传播

### 10.3 修改源码或新增菜单功能的标准步骤

1. 在 `src/` 中找到对应职责模块，不要直接编辑生成版 `hy2.sh`
2. 新增功能函数时放入最接近的职责模块，避免把业务逻辑写进 `main_menu`
3. 修改菜单时同步更新 `src/panel/menu.sh` 与 README 菜单预览
4. 执行 `bash scripts/build-panel.sh` 重新生成 `hy2.sh`
5. 执行 `./scripts/verify.sh` 完成全部检查

### 10.4 推荐编码约定

- 新功能优先封装成函数，避免把逻辑直接写进 `main_menu`
- 每个源码文件只承担一个清晰职责；不要为了减少文件数重新堆回综合模块
- `hy2.sh` 是构建产物，CI 会拒绝源码与生成文件不一致的提交
- 对外部命令（`systemctl/curl/openssl`）尽量做返回码判断
- 配置写入后统一做权限收敛
- 影响服务可用性的改动，优先考虑回滚路径
- 使用 `.editorconfig` 统一 UTF-8、LF、缩进和文件末尾换行规则
- Shell、Bats、YAML 和 Markdown 文件通过 `.gitattributes` 固定 LF 换行，避免 Windows 编辑后影响 Linux 执行

### 10.5 发布流程说明

- 版本来源：`src/bootstrap.sh` 中 `sh_ver`，构建时同步进入 `hy2.sh`
- 版本号采用 `v年.月.日` 格式，例如 `v26.7.14`
- push 到 `main` 后触发：
  - `Lint`（质量检查）
  - `Auto Release`（自动打包发布）
- VPS 安装和菜单 `11` 的面板更新仍只部署单文件 `hy2.sh`，不会在服务器上动态下载模块
- 发布包会额外校验模块源码和生成脚本，并避免本地记忆文件、临时检查目录或已撤销模块进入正式 Release

### 10.6 模块边界与运行约定

| 层 | 职责与约束 |
| --- | --- |
| `src/core/` | 通用输入、校验、编码、文件与网络操作；不承担菜单业务分派 |
| `src/hysteria/` | 配置草稿 → 备份 → 证书与配置应用 → 激活/回滚；保留动态服务用户权限 |
| `src/clients/` | 客户端模板与展示；证书固定校验失败禁止导出，模板调用失败必须向上传播 |
| `src/operations/` | 诊断与备份恢复；每次使用新状态，不能引用失败解析后的旧节点信息 |
| `src/panel/` | 菜单显示、分派、交互循环与面板更新；每次重绘刷新版本与服务状态 |
| `src/main.sh` | 运行入口；`HY2_LIB_ONLY=1` 仅加载函数，供无特权测试使用 |

- 全局变量只用于启动常量、`HY2_DRAFT_*` 配置草稿、`DIAG_*` 诊断上下文和兼容节点字段；导航选项与解析临时变量必须 `local`。
- `read_input` 区分空行与 EOF：空行可使用默认值，EOF 必须立即返回，不能触发默认部署或菜单忙循环。
- `read_meta_info` 先清空旧节点状态，用局部变量解析并校验，成功后才发布 `ip/port/password/sni/insecure/up_mbps/down_mbps`。未知字段不执行，旧文件缺带宽字段仍兼容。
- 配置写入通过 here-document 直接交给 `write_file_atomic`，避免额外管道；权限收敛与四文件回滚仍由配置流程负责。
- `download_script` 统一面板/内核安装脚本下载：连接超时 8 秒、单次请求最多 120 秒、最多重试 2 次（不是整个操作 120 秒）。调用方负责临时文件清理、语法校验与替换。
- 模板顺序输出以减少子 Shell；组合函数必须逐段检查返回码。证书固定材料在首字节输出前校验。若写文件，调用方只能在渲染成功后发布临时文件，不能使用失败的部分输出。
- 面板不启用全局 `set -e`；关键失败路径显式 `return`。工程脚本使用 `set -euo pipefail`，语法检查逐个遍历文件。
- CI 的 Ubuntu、Debian 和发布任务统一执行 `verify.sh all`，包括品牌同步、运行时边界和真实 Sing-box 校验。

### 10.7 性能检查

```bash
# 不访问网络或真实服务；只测试版本字符串提取与完整模板渲染。
bash scripts/benchmark.sh ./hy2.sh 30
# 在同一机器上比较上一提交（需 Git Bash/Linux Bash）。
bash scripts/benchmark.sh <(git show HEAD:hy2.sh) 30
```

计时为本机累计耗时，不设置跨机器的硬阈值，也不代表代理吞吐量。版本探测不再调用 `grep/head`，模板组合移除六次命令替换，构建用一次 `grep` 和一次 `awk` 批量处理模块。网络带宽、拥塞控制和 Hysteria2 内核参数不在本次优化范围内。

---

## 11. 贡献建议

欢迎 PR 方向：

- 更多客户端配置模板
- 更细粒度诊断项
- 多语言文案
- 更完善的单元化脚本测试

---

## 12. 致谢与来源

本项目实践内容参考了作者博客教程：

- https://blog.luopojunzi.com/p/hysteria/

---

## 13. 开源协议

本项目基于 [MIT License](LICENSE) 协议开源。
