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
- `download_script` 统一面板/内核安装脚本下载：连接超时 8 秒、单次请求最多 120 秒、最多重试 2 次（不是整个操作 120 秒）。调用方负责临时文件清理、语法校验与替换。
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
