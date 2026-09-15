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
- 🖥️ **多显示器自适应**：智能感知当前鼠标所在屏幕，无论在外接大屏还是笔记本内屏，始终贴合当前屏幕右侧。
- 🔒 **持久化免反复扫码**：基于原生持久化 `WKWebsiteDataStore`，保持微信扫码登录态。

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

---

## 📄 开源许可

本项目基于 [MIT 协议](LICENSE) 开源。
