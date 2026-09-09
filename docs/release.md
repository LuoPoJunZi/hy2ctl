# 发布与验收

- 版本来源：`src/bootstrap.sh` 中 `sh_ver`，构建时同步进入 `hy2.sh`
- 版本号采用 `v年.月.日` 格式，例如 `v26.7.14`
- push 到 `main` 后触发：
  - `Lint`（质量检查）
  - `Auto Release`（自动打包发布）
- VPS 安装和菜单 `11` 的面板更新仍只部署单文件 `hy2.sh`，不会在服务器上动态下载模块
- 发布包会额外校验模块源码和生成脚本，并避免本地记忆文件、临时检查目录或已撤销模块进入正式 Release

## 发布前检查

1. 业务修改先更新源码，再生成 `hy2.sh`；版本变更同步 bootstrap、生成版、README 预览与 CHANGELOG。
2. 运行 `REQUIRE_SING_BOX_CHECK=1 bash scripts/verify.sh all`，不能用只做语法检查替代完整验证。
3. 对涉及服务、权限、证书或安装的修改，按 [VPS 验收清单](../tests/acceptance/README.md) 在独立测试机验收。
4. 向用户展示差异，获得明确提交/推送授权；本地记忆文件不得提交。
5. 推送后核对目标提交的 Lint 和 Auto Release，再核对正式 Release 及附件；推送成功不等于发布成功。
6. 若当前日期版本已发布，不覆盖现有标签或附件；先确定下一版本号，或把纯维护变更记录到 Unreleased。

## 源码发布包

- 模块文件来自 `scripts/panel-modules.list`；构建与发布检查共用清单。
- 发布检查同时要求当前工程的 `scripts/`、`tests/`、`docs/` 完整存在，包含辅助库、样例和文档。
- 本地文件禁止打包规则独立保留，不能从模块清单推导或删除这些规则。
- 附件必须包含 `code.tar.gz`、`hy2.sh`、`install.sh`、`SHA256SUMS`；校验清单必须覆盖前三个附件。
- 安装仍只部署单文件；源码包中的 docs/tests 不会变成 VPS 运行依赖。

[架构说明](architecture.md) · [开发与测试](development.md) · [返回项目首页](../README.md)
