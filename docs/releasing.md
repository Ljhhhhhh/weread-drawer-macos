# 发布 macOS 版本

## 更新签名密钥

更新私钥保存在 macOS 登录钥匙串中，Sparkle 账户名为 `com.weread.drawer`，公钥位于 `Resources/Info.plist` 的 `SUPublicEDKey`。不要把私钥提交到仓库或上传到 Release。

迁移构建机器前，使用 Sparkle 的 `generate_keys --account com.weread.drawer -x <安全路径>` 导出并妥善保存私钥，再在新机器使用 `-f <安全路径>` 导入。工具在首次构建后位于 `.dependencies/Sparkle/bin/`。丢失私钥会导致已安装的版本无法接受后续更新。

## 准备发布文件

1. 修改 `Resources/Info.plist` 中的 `CFBundleShortVersionString`（展示版本），并递增 `CFBundleVersion`（更新比较版本）。
2. 执行 `./scripts/prepare-release.sh`。脚本校验钥匙串公钥，构建双架构应用，生成拖放安装 DMG、签名的 `appcast.xml` 和 `SHA256SUMS`，输出到 `build/release/`。DMG 内包含应用和指向 `/Applications` 的快捷方式，自动更新也使用同一份 DMG。
3. 提交并推送源代码，使用与展示版本一致的 `v<版本>` 标签创建 GitHub Release，将三个发布文件全部上传后再公开发布，并将稳定版本设为 Latest。

更新器读取最新 Release 中的 `appcast.xml`，其中的安装包链接指向该版本固定标签下的 DMG。请勿删除历史发布包，也不要把缺少更新源的 Release 设为 Latest。

应用、Sparkle 框架及指定中文的更新助手使用 ad-hoc 代码签名。主应用和更新助手均通过 `CFBundleLocalizations` 声明简体中文，检查、下载和安装进度界面统一使用中文。更新包和更新源使用 Ed25519 签名；这不等同于 Apple Developer ID 签名或公证。首次安装仍可能受到 Gatekeeper 提示。

## 校验

`prepare-release.sh` 会验证应用及嵌套框架的代码签名，并验证 DMG 和更新源签名。发布前还应只读挂载 DMG，核对应用版本、双架构二进制及 Applications 快捷方式；发布后确认公开地址能够下载。

完整更新验证需要用较低构建号的版本下载、安装并重新启动新版本。执行前先确认测试范围和是否保留可重复验证材料。
