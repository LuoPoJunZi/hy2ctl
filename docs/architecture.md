# 架构与模块边界

| 层 | 职责与约束 |
| --- | --- |
| `src/core/` | 通用输入、校验、编码、文件与网络操作；不承担业务快照、权限恢复或菜单分派 |
| `src/hysteria/` | 包含 runtime_snapshot.sh 四文件快照；配置草稿 → 备份 → 证书与配置应用 → 激活/回滚；保留动态服务用户权限 |
| `src/clients/` | 客户端模板与展示；证书固定校验失败禁止导出，模板调用失败必须向上传播 |
| `src/operations/` | 诊断与备份恢复；每次使用新状态，不能引用失败解析后的旧节点信息 |
| `src/panel/` | 主菜单、服务/备份子菜单、分派、交互循环与面板更新；每次重绘刷新版本与服务状态 |
| `src/main.sh` | 运行入口；`HY2_LIB_ONLY=1` 仅加载函数，供无特权测试使用 |

- 全局变量只用于启动常量、`HY2_DRAFT_*` 配置草稿、`DIAG_*` 诊断上下文和兼容节点字段；导航选项与解析临时变量必须 `local`。
- `read_input` 区分空行与 EOF：空行可使用默认值，EOF 必须立即返回，不能触发默认部署或菜单忙循环。
- `read_meta_info` 先清空旧节点状态，用局部变量解析并校验，成功后才发布 `ip/port/password/sni/insecure/up_mbps/down_mbps`。未知字段不执行，旧文件缺带宽字段仍兼容。
- 配置写入通过 here-document 直接交给 `write_file_atomic`，避免额外管道；权限收敛与四文件回滚仍由配置流程负责。
- 自动快照写入 `backup/runtime-XXXXXX/`（私有目录，保留 `.bak` / `.bak.absent`），完整校验后通过原子文件写入切换 `backup/runtime.current`。复制或发布失败只清理本次暂存目录；成功后仅清理已被替换的新版自动快照，不动手动备份和旧版平铺文件。恢复兼容旧格式，但存在损坏指针时拒绝退回过时快照；指针只允许本目录下的受限名称，不执行内容。
- 快照“发布”是原子操作，四文件“恢复”仍是逐项复制/删除并检查错误，不宣称跨文件事务或并发配置安全。配置/恢复应串行操作；中断残留暂存目录不参与当前快照选择。
- `restart_hy2_service_checked` 统一重启和两秒后 `is-active` 检查，配置及手动恢复各自处理失败提示/四文件回滚。回滚重启也要检查存活；该检查不证明长期运行或客户端可连接。
- `download_script` 统一面板/内核安装脚本下载：连接超时 8 秒、单次请求最多 120 秒、最多重试 2 次（不是整个操作 120 秒）。调用方负责临时文件清理、语法校验与替换。
- `core/ip.sh` 用 Bash 内建校验 IPv4、压缩/完整/IPv4 嵌入式 IPv6，筛选公网候选；特殊用途范围依据 [IANA IPv4](https://www.iana.org/assignments/iana-ipv4-special-registry/) / [IPv6](https://www.iana.org/assignments/iana-ipv6-special-registry/) 登记。不把地址分类当作实际可达证明。`fetch_public_ip` 每个地址族连接超时三秒、请求最多六秒，配置 `--max-filesize 128` 并在格式解析前拒绝超长结果；[curl 8.4 以前](https://curl.se/docs/manpage.html#--max-filesize)无法在传输中限制未知长度响应，不能把该参数称为旧版 curl 的内存硬上限。`fetch_local_ip` 只接受合法地址，公网候选优先。诊断区分外部确认和本机回退，不通过失败请求的部分响应更新元数据。
- 模板顺序输出以减少子 Shell；组合函数必须逐段检查返回码。证书固定材料在首字节输出前校验。若写文件，调用方只能在渲染成功后发布临时文件，不能使用失败的部分输出。
- 面板不启用全局 `set -e`；关键失败路径显式 `return`。工程脚本使用 `set -euo pipefail`，语法检查逐个遍历文件。
- CI 的 Ubuntu、Debian 和发布任务统一执行 `verify.sh all`，包括品牌同步、运行时边界和真实 Sing-box 校验。

## 源码与发布边界

- `scripts/panel-modules.list` 是源码顺序的唯一清单。只保存仓库相对路径，不执行其中的文本。
- `scripts/lib/source-manifest.sh` 验证路径、重复/遗漏模块及首尾入口，供构建和发布检查共用；它不是 VPS 运行时模块。
- `src/bootstrap.sh` 必须排第一，`src/main.sh` 必须排最后。业务文件加载时只定义函数，不启动服务、不访问网络。
- `core/files.sh` 只负责原子文件写入；四文件快照及恢复权限位于 `hysteria/runtime_snapshot.sh`。
- 服务菜单在 `panel/service_menu.sh`，状态变更在 `hysteria/service.sh`；备份菜单在 `panel/backup_menu.sh`，备份操作在 `operations/backup_*.sh`。
- 用户配置、证书和私钥属于 VPS 运行数据，不放进仓库。测试证书仅在临时目录生成。

## 保持兼容的接口

继续在根目录生成 `hy2.sh`；`install.sh`、`hy2` 命令、菜单编号和默认值不变。不在 VPS 上动态下载模块，不引入新的运行依赖。

单个业务文件无需为目录整齐再次细分。变动优先遵循职责边界，而不是行数或文件数量。

[开发与测试](development.md) · [发布验收](release.md) · [返回项目首页](../README.md)
