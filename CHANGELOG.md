# Changelog

## Unreleased

## v26.10.1 - 2026-10-01

- 自动快照先写入私有独立目录，完整校验后原子切换 `runtime.current`；复制或发布失败保留旧快照，兼容恢复旧版平铺 `.bak` / `.bak.absent`，不清理手动备份。
- 配置启用和手动恢复共用重启后的两秒服务状态检查；服务立即退出会恢复四文件，回滚后服务仍退出时不再提示回滚成功，并显示故障建议与日志。
- 公网 IP 探测增加纯 Bash IPv4/IPv6 校验、特殊用途地址筛选和有界请求；拒绝错误页面/失败请求的部分响应，本机地址回退优先选择公网候选并明确提示未确认公网可达。
- 自动快照恢复先检查四文件状态完整且互斥，拒绝损坏快照，避免未检查完就部分覆盖当前配置。
- 诊断报告改为独占随机文件、仅运行用户可读写；最新报告原子替换并正确提示导出失败。通用原子写入拒绝目录目标，避免误报成功。
- Hysteria2 推荐版本更新到 `2.12.3`，补充 HTTP 代理 10 秒断开与 Linux 端口跳跃 UDP 修复提醒；补充 v2rayN `7.25.4+` 与 Sing-box `1.14` 的兼容说明。
- Sing-box CI 同时验证最低版本 `1.14.0` 与稳定版本 `1.14.2`，固定审核过的 SHA-256；限制下载超时、Lint 权限与运行时长，并取消过期检查。
- Hysteria2 内核诊断增加安全基线分级：低于 v2.9.2 明确提示高危安全风险并要求立即更新，较新但低于推荐版本的内核继续显示兼容性与稳定性建议。
- 整理仓库职责：四文件快照迁入 Hysteria 模块，服务和备份菜单归入 panel，保留单文件安装与旧冒烟检查入口。
- 按职责拆分 Bats 测试，共用断言、临时环境、模拟命令与测试样例；增加独立 VPS 验收清单。
- 构建和发布共用有序模块清单，Shell/Bats 检查递归发现文件，发布检查覆盖工程辅助文件。
- README 保留用户入口，架构、开发测试和发布指南分离到 docs。

## v26.9.9 - 2026-09-09

- 标准化运行时边界：主菜单分离显示、分派与循环；统一交互输入，EOF 取消操作，导航状态局部化。
- 元数据改为局部解析、完整校验后发布，失败清空旧节点信息，兼容末行无换行和旧带宽默认值。
- 减少版本探测、配置写入、Sing-box 模板组合及模块构建的重复子进程；新增无网络性能对比入口。
- JSON 编码覆盖所有 Bash 可保存的控制字符，模板组合显式传播各段失败，脚本下载统一超时与重试。
- 修复多文件语法检查只检查首文件的问题；所有 CI 任务统一完整验证，新增输入中断、状态隔离、失败传播回归测试。

## v26.9.7 - 2026-09-07

- v2rayN 安全建议更新到 `7.24.9+`，提醒用户规避旧版内置下载器的中间人攻击风险。
- Sing-box 完整模板升级到 `1.14+`，远程规则集改用 `http_clients` 与 `route.default_http_client`，移除已弃用的 `download_detour`。
- Release 发布依赖更新到 `softprops/action-gh-release v3.0.3`；Linux CI 固定下载并校验 Sing-box `1.14.0`，使用真实内核检查 CA 与自签完整模板。

## v26.9.1 - 2026-09-01

- 一键安装器会自动安装或更新 Hysteria2 内核，减少首次部署步骤；后续面板和内核更新统一收纳到菜单 `(11)`。
- 节点默认端口调整为 `8443`，默认上下行带宽调整为 `50/200 Mbps`，证书模式直接回车时默认使用自签证书。
- 主菜单重新编号为 `1-11` 并统一精简名称，相关提示、README、生成版和回归测试同步更新。

## v26.8.31 - 2026-08-31

- 项目与 GitHub 仓库统一更名为 `hy2ctl`，同步更新主界面、安装器、诊断报告和客户端节点备注。
- 安装、自更新、速查与开发文档全部切换到 `LuoPoJunZi/hy2ctl`，避免继续依赖旧仓库地址。
- 保留 `hy2.sh` 发布文件和 `hy2` 快捷命令，确保现有 VPS 安装与升级方式继续兼容。

## v26.8.30 - 2026-08-30

- 引入 38 个职责清晰的模块化源码文件，通过确定性构建继续发布单文件 `hy2.sh`，现有安装和更新方式不变。
- 配置、证书、诊断、备份恢复、Sing-box 模板和客户端导出已按职责拆分，便于独立维护和回归。
- GitHub Actions 新增源码/生成版一致性检查、CA/自签配置回放、回滚验证与 Sing-box JSON 标准解析测试。

## v26.8.27 - 2026-08-27

- Hysteria2 内核诊断推荐版本更新到 v2.12.2，补充 IPv6 mimic 修复与 Stateless Reset 兼容开关说明，默认保留移动端快速重连能力。
- v2rayN 安全与 Hysteria2 兼容建议更新到 7.24.8+，继续保留 `pinSHA256`、`pcs` 与 Sing-box 公钥固定方案。
- GitHub Actions 依赖固定到审核过的完整提交 SHA，降低可移动标签带来的发布供应链风险。

## v26.8.11 - 2026-08-11

- Sing-box 自签配置新增 `certificate_public_key_sha256` 公钥固定，校验值缺失时拒绝导出，最低兼容版本调整为 Sing-box 1.13.0。
- Hysteria2 内核诊断增加版本检查，低于 v2.12.1 时提示更新，并在内核安装完成后显示实际版本。
- 更新 v2rayN 安全版本建议以及 GitHub Actions 的 checkout、Release 发布依赖。

## v26.8.3 - 2026-08-03

- 自签证书指纹缺失或读取失败时停止生成客户端分享链接，避免 v2rayN/Xray 退回使用已移除的 `allowInsecure` 路径。

## v26.7.31 - 2026-07-31

- Hysteria2 自签分享链接移除 `allowInsecure`，同时输出原生客户端使用的 `pinSHA256` 与 v2rayN/Xray 使用的 `pcs` 证书指纹参数。
- 强化配置变更、手动备份与恢复流程，完整处理配置、元数据、证书和私钥，并在失败时自动回滚。
- Hysteria2 内核安装与面板更新改为先下载、校验 Bash 语法，再执行或覆盖目标文件。
- 新增仓库文本规范检查，扩展 GitHub Actions、Smoke E2E、Bats 与交互配置回放测试。

## v26.7.15 - 2026-07-15

- README 删除 `hy2.evzzz.com` 域名安装方式，仅保留 GitHub 官方仓库的 `install.sh` 一键安装命令。

## v26.7.14 - 2026-07-14

- Hysteria2 分享链接按官方 URI 规范使用 `insecure=1/0`，并补充 v2rayN 兼容参数。
- 自签节点自动导出证书 SHA-256 指纹与 `pinSHA256`，v2rayN 使用 Xray 时可转换为 `pinnedPeerCertSha256`。
- 新生成的自签证书增加 SAN、`CA:FALSE` 和 serverAuth 扩展，现有证书不会因面板更新自动重签。
- 原生 Hysteria2 YAML 同步加入证书指纹，并补充链接、指纹、证书兼容性回归测试。
- 版本号切换为 `v年.月.日` 格式；本版本作为预发布版本供实际 VPS、v2rayN 和 Xray 联调验证。

## v1.4.6 - 2026-06-21

- 根据 v2rayN 7.22.7 的 allowInsecure 变更提醒，增加自签模式导出时的 v2rayN / Xray 风险提示。
- README 补充 v2rayN 自签模式建议：长期优先使用 CA 域名证书，自签模式优先使用 Sing-box 完整模板。
- 补充回归测试，确保 v2rayN 自签风险提示持续输出。

## v1.4.5 - 2026-06-10

- 修复 Sing-box Android 启动时报 `dns/udp[local]: detour to an empty direct outbound makes no sense` 的问题。
- 移除完整模板中本地 DNS server 的 `detour: direct` 写法。
- 远程 DNS 和远程规则集下载改为走 `proxy`，并设置 `route.default_domain_resolver`，降低安卓端 DNS 解析失败风险。
- 补充回归测试，防止完整模板再次把本地 DNS detour 到 direct outbound。

## v1.4.4 - 2026-06-06

- 更新菜单 `(8)` Sing-box 完整模板，兼容 sing-box 1.12+ / 1.14+ 新配置格式。
- 移除完整模板中的旧 `geosite`、`geoip`、`inet4_address` 和 DNS outbound 写法，改用 `rule_set` 与 route action。
- 补充回归测试，防止完整模板重新出现已移除的旧字段。

## v1.4.3 - 2026-06-05

- 重新发布恢复后的单文件主线，避免用户继续下载到已撤销 PR #2 的发布产物。
- 面板自更新增加旧脚本备份、下载版本校验和写入失败恢复。
- 发布流程增加产物校验，阻止本地记忆文件、临时检查目录和已撤销模块化文件进入 Release 包。

## v1.4.2 - 2026-05-28

- 主菜单新增 `(12) 更新管理面板脚本`，可直接更新 `/usr/local/bin/hy2`。
- 常用指令速查补充面板脚本更新命令，避免和 Hysteria2 内核更新混淆。
- 同步 README 菜单预览和菜单一致性检查到 `[0-12]`。

## v1.4.1 - 2026-05-24

- 发布页标题改为纯版本号，不再追加旧项目名前缀。
- 发布说明改为从当前版本的 `CHANGELOG.md` 小节生成，只展示“主要变化”。
- 发布前验证保持分阶段执行，便于快速定位 Actions 失败环节。
- 修复菜单同步检查中横线分隔符被 `grep` 误解析为选项的问题。

## v1.4.0 - 2026-04-20

- Added `bats` unit tests under `tests/unit` for core helper behavior.
- Extended `scripts/verify.sh` to run `bats tests/unit`.
- Upgraded CI lint workflow to verify on both Ubuntu and Debian container environments.
- Synced release verification dependencies with new bats-based test suite.
- Added interactive config flow replay test (`tests/e2e/config-flow.sh`) and wired it into `verify`.
- Enhanced diagnostics output with severity summary (`FAIL/WARN/建议项`) for faster triage.
- Moved release verification before release-skipping logic so Auto Release reflects script health even when no new tag is published.
- Included self-signed certificate files in automatic rollback backups.
- Hardened manual restore to stop on missing or failed critical config restoration.
- Added `.gitattributes` to keep scripts and workflows on LF line endings.

## v1.3.0 - 2026-04-05

- Added non-privileged smoke E2E checks and wired them into `verify`, lint, and release workflows.
- Added a library-only entry mode (`HY2_LIB_ONLY=1`) to make `hy2.sh` testable without entering the interactive menu.
- Hardened config/meta writes with atomic file replacement and explicit write-failure handling.
- Improved startup failure diagnosis with categorized hints (permission denied, port in use, ACME failure, parse error).
- Upgraded one-click diagnostics output to structured `结论 + 建议 + 命令` format with de-duplication.

## v1.2.1 - 2026-04-04

- Fixed Linux permission issue where `hysteria-server` could not read `/etc/hysteria/config.yaml`.
- Applied dynamic permission strategy based on real systemd service user.
- Added safer rollback behavior and better startup failure diagnostics.
- Synced menu consistency checks with the latest plain-text menu labels.

## v1.2.0 - 2026-04-04

- Added one-click environment diagnostics and report export/review.
- Added manual backup and restore menu.
- Added full Sing-box profile template output.
- Added self-signed SNI preset domain options.
- Standardized script structure, installer checks, and release quality gates.
