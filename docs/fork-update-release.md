# Fork 应用内更新发布

`feature/fork-in-app-updater` 是 Fork 更新通道的发布分支。需要发布新的
应用内更新时，应先把上游和 Fork 功能合入该分支，再从该分支提交创建
Release 标签；不要从未包含更新通道修改的普通分支创建标签。

## 发布顺序

1. 将最新 `upstream/main` 合入 `feature/fork-in-app-updater`，解决冲突并
   确认 `UpdateCheckService.defaultOwner` 仍为 `shenghuo2`。
2. 将 `pubspec.yaml` 提高到新的 Fork 版本，例如
   `3.0.0-picmanager.2+38`。公开标签必须为 `v3.0.0-picmanager.2`。
3. 更新 Changelog，执行局部测试、静态分析和 macOS Build Workflow。
4. 推送 feature 分支，等待 Actions 成功。
5. 在该分支已验证的提交上创建并推送 `v*` 标签，由 Release Workflow
   构建并发布 Windows、macOS DMG 和 Android 资产。

## 更新链路

- Windows 安装版和便携版会下载、校验、退出、替换并重新启动；便携版
  支持启动失败回滚。
- macOS 会选择当前 CPU 对应的 DMG，完成大小与 SHA-256 校验后退出应用。
  独立脚本挂载 DMG、校验 Bundle ID、版本和代码签名，备份并替换 `.app`，
  然后重新启动；启动失败时恢复旧应用。
- Android 会选择当前 ABI 对应的 APK，完成校验后打开系统安装界面。

macOS 应用必须已从 DMG 移到 `/Applications`、`~/Applications` 或其他可写
目录。从 `/Volumes` 或 App Translocation 路径运行时不会启用自动替换。
标准用户对 `/Applications` 没有写权限时，应改装到 `~/Applications`。

`v3.0.0-picmanager.1` 仍查询上游仓库，无法发现第一个修复更新通道的版本。
用户需要手动覆盖安装一次桥接版本；桥接版本之后才可连续应用内升级。

## macOS 签名

当前 CI 使用 ad-hoc 签名并通过 `codesign --verify --deep --strict` 验证。更新包
的真实性依赖 GitHub HTTPS、Release manifest 和 SHA-256。面向大范围分发前，
应配置 Apple Developer ID 签名和 notarization；在此之前不能把 ad-hoc 签名
描述为 Apple 公证。
