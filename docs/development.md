# 开发与测试

## 开发前准备

```bash
git clone https://github.com/LuoPoJunZi/hy2ctl.git
cd hy2ctl
```

## 本地检查（每次改动后执行）

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
- 工程布局回归（`tests/e2e/repository-layout.sh`）：清单校验、构建兼容性与源码包完整性/防污染

## 修改源码或新增菜单功能的标准步骤

1. 在 `src/` 中找到对应职责模块，不要直接编辑生成版 `hy2.sh`
2. 新增功能函数时放入最接近的职责模块，避免把业务逻辑写进 `main_menu`；新增模块必须加入 `scripts/panel-modules.list`
3. 修改菜单时同步更新 `src/panel/menu.sh` 与 README 菜单预览
4. 执行 `bash scripts/build-panel.sh` 重新生成 `hy2.sh`
5. 执行 `./scripts/verify.sh` 完成全部检查

## 推荐编码约定

- 新功能优先封装成函数，避免把逻辑直接写进 `main_menu`
- 每个源码文件只承担一个清晰职责；不要为了减少文件数重新堆回综合模块
- `hy2.sh` 是构建产物，CI 会拒绝源码与生成文件不一致的提交
- 对外部命令（`systemctl/curl/openssl`）尽量做返回码判断
- 配置写入后统一做权限收敛
- 影响服务可用性的改动，优先考虑回滚路径
- 使用 `.editorconfig` 统一 UTF-8、LF、缩进和文件末尾换行规则
- Shell、Bats、YAML 和 Markdown 文件通过 `.gitattributes` 固定 LF 换行，避免 Windows 编辑后影响 Linux 执行

## 性能检查

```bash
# 不访问网络或真实服务；只测试版本字符串提取与完整模板渲染。
bash scripts/benchmark.sh ./hy2.sh 30
# 在同一机器上比较上一提交（需 Git Bash/Linux Bash）。
bash scripts/benchmark.sh <(git show HEAD:hy2.sh) 30
```

计时为本机累计耗时，不设置跨机器的硬阈值，也不代表代理吞吐量。版本探测不再调用 `grep/head`，模板组合移除六次命令替换，构建用一次 `grep` 和一次 `awk` 批量处理模块。网络带宽、拥塞控制和 Hysteria2 内核参数不在本次优化范围内。


## 测试分层

| 目录 | 用途 |
| --- | --- |
| `tests/helpers/` | Shell 断言、独立临时环境、可控的 systemctl/journalctl 模拟；只供测试显式加载 |
| `tests/fixtures/` | 示例配置、异常元数据和日志；不保存真实密码、私钥或生产报告 |
| `tests/unit/` | 按校验、配置、菜单/诊断、快照/回滚、客户端、证书、更新划分的 Bats 用例 |
| `tests/e2e/` | 无特权回放、冒烟、运行时边界及工程布局回归；外部服务使用模拟 |
| `tests/acceptance/` | 独立 Linux VPS 人工验收清单；不属于自动化通过结论 |

每个需要文件操作的测试用例通过 `test_create_environment` 创建独立临时目录，并由 trap 或 Bats teardown 清理。模拟命令只影响加载它的测试进程，不替换系统命令。

快照/恢复测试必须覆盖末项复制失败、当前指针发布失败、旧格式兼容、损坏指针拒绝、当前/手动快照清理保护以及服务重启后退出；IP 测试覆盖两种地址族、IPv6 压缩/嵌入格式、错误页面、部分响应、本机回退与公网诊断分级。Bats 新增用例不能只修改断言使错误输出“通过”；应先复现失败再验证修复。

`verify.sh syntax/shellcheck` 递归发现 src、scripts、tests 中的 Shell 文件；Bats 递归发现 unit 中的用例。静态样例不要用 `.sh` 伪装不可执行文本。

## 常用检查入口

在仓库根目录执行；Python、Bats、ShellCheck、Sing-box 只用于开发测试，不是面板新增的运行依赖。

```bash
bash scripts/build-panel.sh
bash scripts/verify.sh all
bash scripts/verify.sh bats
bash scripts/verify.sh repository-layout
REQUIRE_SING_BOX_CHECK=1 bash scripts/verify.sh client-render
```

完整检查要求安装 Bash、Git、ShellCheck、Bats、Python 3、OpenSSL 及常用 Unix 工具。CI 通过 `scripts/install-test-sing-box.sh` 下载并校验固定版本 Sing-box。`PYTHON_BIN`、`SING_BOX_BIN` 可指定本机工具路径；未提供 Sing-box 时普通客户端检查允许跳过原生检查，发布验证必须设置 `REQUIRE_SING_BOX_CHECK=1`。

Sing-box 测试安装器默认固定 `1.14.2`，可显式传入 `1.14.0` 检查最低兼容版本；只允许脚本中已审核的版本和 SHA-256。Ubuntu CI 同时验证 `1.14.0` / `1.14.2`，Debian 和发布验证默认使用 `1.14.2`。更新时核对官方附件摘要，不自动追随 latest 或 alpha。Lint 限定只读权限、20 分钟任务上限，并取消同一 PR/分支的过期运行；发布验证仍必须在判断是否发版之前完整执行。

`scripts/smoke-e2e.sh` 保留为旧入口的兼容包装，实际用例为 `tests/e2e/smoke.sh`。

[架构说明](architecture.md) · [发布验收](release.md) · [返回项目首页](../README.md)
