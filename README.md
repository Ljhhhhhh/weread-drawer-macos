# WeRead Drawer for macOS (微信读书桌面边缘抽屉)

轻量、纯粹、沉浸的原生 macOS 贴边抽屉阅读工具。让你在敲代码、浏览网页、写文档的间隙，零切换成本享受“微阅读”。

![macOS](https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Language-Swift%206-orange?logo=swift)
![License](https://img.shields.io/badge/License-MIT-green)

---

## ✨ 核心特性

- 🚀 **全局秒级唤醒**：按下快捷键 `⌥ + S`（Option + S），抽屉即刻从屏幕边缘顺滑推出；再按一次立即隐藏。
- 📊 **精美统计看板与按天追踪**：状态栏支持按日与历史累计统计，并提供原生居中弹窗看板，包含近 7 天阅读趋势柱状图。
- 🌓 **快捷切换亮/暗色主题**：支持快捷键 `⌥ + T`（Option + T）快速切换亮色/暗色模式，并默认**跟随 macOS 系统主题**自动切换。
- 🖱️ **鼠标滚轮原生切页**：支持直接通过**鼠标滚轮**或触控板手势向上/向下滑动触发翻页（上一页/下一页），完美契合微信读书排版。
- 🫥 **智能自动隐藏 (Auto-Hide)**：
  - **点击外部即收**：鼠标点击抽屉外部任意应用或桌面，抽屉瞬间收回，专注主流程。
  - **移出离开收起**：光标移出抽屉区域超时后自动收起为右侧边缘极细把手。
  - **Pin 固定模式**：支持状态栏勾选“固定窗口”，边写代码边参考资料时不收起。
- 🎨 **Web 界面纯净清洗**：
  - 自动抹除微信读书网页版多余的大 Header、Banner 与 App 推广，正文纵向视野提升 25%+。
  - 注入自适应 **Dark Mode** 暗黑模式与 4px 超细半透明滚动条。
- 🖥️ **多显示器自适应**：每个屏幕的所选角落各有一个手柄，点击或悬停即可在该屏幕打开同一个阅读抽屉，保留阅读进度；支持显示器插拔与布局变化。
- 📍 **四角吸附**：拖动边缘手柄或展开窗口顶部的拖动条，松手后吸附到所在屏幕最近的一角（展开窗口按窗口中心判断，收起手柄按鼠标位置判断）；也可通过状态栏菜单“抽屉位置”选择左上、右上、左下、右下。位置自动保存，左右两侧的展开、收起及宽度调整方向随之切换。全屏高度时上下位置相同，可在“抽屉高度”中调整。
- 🔒 **持久化免反复扫码**：基于原生持久化 `WKWebsiteDataStore`，保持微信扫码登录态。
- 🔄 **自动更新**：后台检查新版本，发现更新后提示下载并安装；也可从状态栏菜单选择“检查更新…”。更新源为 GitHub Releases，更新包与更新源均经过签名验证。

---

## ⌨️ 快捷键指南

| 快捷键 | 动作 |
| :--- | :--- |
| **`⌥ + S`** (Option + S) | 显示 / 隐藏阅读抽屉 |
| **`⌥ + T`** (Option + T) | 快速切换亮色 / 暗色模式 |
| **`⌥ + PageDown`** | 快速翻到下一页（HUD 浏览态，不夺取键盘焦点） |
| **`⌥ + PageUp`** | 快速翻到上一页 |
| **鼠标滚轮上下滑动** | 抽屉内直接切上一页 / 下一页 |

---

## 🛠️ 构建与安装

从 [最新发布](https://github.com/Ljhhhhhh/weread-drawer-macos/releases/latest) 下载 macOS ZIP，解压后将 `WeReadDrawer.app` 移至“应用程序”文件夹运行。支持 Apple Silicon 和 Intel Mac。尚未包含更新功能的旧版本需要手动安装一次。

应用未经过 Apple 公证；若 macOS 阻止打开，请在“系统设置 → 隐私与安全性”中确认来源后允许打开。

### 依赖环境
- macOS 14.0+
- Xcode Command Line Tools (`xcode-select --install` 或自带 `swiftc`)

### 一键编译
```bash
git clone https://github.com/Ljhhhhhh/weread-drawer-macos.git
cd weread-drawer-macos
make
```
构建生成的产物位于 `build/WeReadDrawer.app`，双击即可直接运行。
首次构建会下载并校验 Sparkle 框架，需要连接 GitHub。

维护者发布新版本请参阅[发布指南](docs/releasing.md)。

---

## 📄 开源许可

本项目基于 [MIT 协议](LICENSE) 开源。
