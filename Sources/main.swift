import Cocoa
import WebKit
import Carbon

class HandlePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
    }
}

class HandleView: NSView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let handleHeight: CGFloat = 80
        let handleY = (bounds.height - handleHeight) / 2 + 50
        let pillRect = NSRect(x: bounds.maxX - 6, y: handleY, width: 5, height: handleHeight)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: 2.5, yRadius: 2.5)
        NSColor.systemGray.withAlphaComponent(0.45).setFill()
        path.fill()
    }
}

class WeReadWebView: WKWebView {
    var onScrollPage: ((Bool) -> Void)?
    private var lastScrollTime: TimeInterval = 0

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
        if abs(delta) >= 3 {
            let now = Date().timeIntervalSince1970
            if now - lastScrollTime > 0.32 {
                lastScrollTime = now
                // delta < 0 表示手指向下滑动，阅读后文 -> 下一页
                // delta > 0 表示手指向上滑动，回看前文 -> 上一页
                let forward = delta < 0
                onScrollPage?(forward)
                return
            }
        }
        super.scrollWheel(with: event)
    }
}

class WeReadPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.backgroundColor = NSColor.windowBackgroundColor
        self.hasShadow = true
    }
    override var canBecomeKey: Bool { return true }
}

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate {
    var statusItem: NSStatusItem!
    var panel: WeReadPanel!
    var handlePanel: HandlePanel!
    var handleView: HandleView!
    var webView: WeReadWebView!
    var drawerWidth: CGFloat = 520
    var globalHotKeyRef: EventHotKeyRef?
    var isPinned: Bool = false
    private var mouseCheckTimer: Timer?
    private var outsideHoverCount: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSavedSettings()
        setupStatusItem()
        setupPanel()
        setupHandle()
        setupWebView()
        setupGlobalHotKey()
        setupAutoHiding()
        loadWeRead()
        showDrawer()
    }

    func loadSavedSettings() {
        let saved = UserDefaults.standard.double(forKey: "WeReadDrawerWidth")
        if saved >= 380 && saved <= 1400 { drawerWidth = CGFloat(saved) }
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "📖"
            button.action = #selector(toggleDrawer)
            button.target = self
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示/隐藏抽屉 (⌥+S)", action: #selector(toggleDrawer), keyEquivalent: "s"))
        let pinItem = NSMenuItem(title: "固定窗口 (阻止自动隐藏)", action: #selector(togglePin), keyEquivalent: "p")
        menu.addItem(pinItem)
        menu.addItem(NSMenuItem(title: "回到书架", action: #selector(goShelf), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "刷新页面", action: #selector(reloadPage), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func currentActiveScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        for s in NSScreen.screens {
            if s.frame.contains(mouse) { return s }
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    func setupPanel() {
        let screen = currentActiveScreen()
        let vis = screen.visibleFrame
        let rect = NSRect(x: vis.maxX - drawerWidth, y: vis.minY, width: drawerWidth, height: vis.height)
        panel = WeReadPanel(contentRect: rect)
        panel.minSize = NSSize(width: 380, height: 400)
    }

    func setupHandle() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let handleWidth: CGFloat = 16
        handlePanel = HandlePanel(contentRect: NSRect(x: frame.maxX - handleWidth, y: frame.minY, width: handleWidth, height: frame.height))
        handleView = HandleView(frame: NSRect(x: 0, y: 0, width: handleWidth, height: frame.height))
        handleView.onClick = { [weak self] in self?.showDrawer() }
        handlePanel.contentView = handleView
    }

    func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // 注入去冗余顶部 Header、自适应暗黑模式、4px 浮动滚动条
        let cssClean = """
        .readerTopBar, .navBar, .app_download, .readerControls_fontSize, .wr_header { display: none !important; }
        body, html { overflow-x: hidden !important; padding-top: 10px !important; }
        ::-webkit-scrollbar { width: 4px !important; }
        ::-webkit-scrollbar-thumb { background: rgba(128, 128, 128, 0.25) !important; border-radius: 2px !important; }
        @media (prefers-color-scheme: dark) {
            body, .readerChapterContent, .app_content { background-color: #19191A !important; color: #D1D1D6 !important; }
        }
        """
        let cssB64 = Data(cssClean.utf8).base64EncodedString()
        let cssJS = "let s = document.createElement('style'); s.innerHTML = atob('" + cssB64 + "'); document.head.appendChild(s);"
        let script = WKUserScript(source: cssJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)

        webView = WeReadWebView(frame: panel.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        
        // 核心：监听鼠标滚轮触发翻页！
        webView.onScrollPage = { [weak self] forward in
            self?.flipPage(forward: forward)
        }

        panel.contentView?.addSubview(webView)
    }

    func setupGlobalHotKey() {
        var hotKeyID = EventHotKeyID(signature: OSType(0x57524452), id: 1)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            let delegate = unsafeBitCast(userData, to: AppDelegate.self)
            DispatchQueue.main.async { delegate.toggleDrawer() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
        RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &globalHotKeyRef)
    }

    func loadWeRead() {
        if let url = URL(string: "https://weread.qq.com") { webView.load(URLRequest(url: url)) }
    }

    @objc func toggleDrawer() {
        if panel.isVisible { hideDrawer() } else { showDrawer() }
    }

    func showDrawer() {
        let screen = currentActiveScreen()
        let visible = screen.visibleFrame
        let target = NSRect(x: visible.maxX - drawerWidth, y: visible.minY, width: drawerWidth, height: visible.height)
        panel.setFrame(target, display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
        handlePanel.orderOut(nil)
    }

    func hideDrawer() {
        drawerWidth = panel.frame.width
        UserDefaults.standard.set(Double(drawerWidth), forKey: "WeReadDrawerWidth")
        panel.orderOut(nil)
        showHandle()
    }

    func showHandle() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let handleWidth: CGFloat = 16
        handlePanel.setFrame(NSRect(x: frame.maxX - handleWidth, y: frame.minY, width: handleWidth, height: frame.height), display: true)
        handlePanel.orderFrontRegardless()
    }

    // 核心翻页动作：向下翻页寻找【下一页】按钮，向上翻页寻找【上一页】按钮，并用箭头键兜底！
    func flipPage(forward: Bool) {
        let targetText = forward ? "下一页" : "上一页"
        let key = forward ? "ArrowRight" : "ArrowLeft"
        let keyCode = forward ? 39 : 37
        let js = """
        (function() {
            // 优先查找匹配文本按钮（微信读书底部的“上一页” / “下一页”）
            const candidates = document.querySelectorAll('button, div, span, a');
            for (let i = candidates.length - 1; i >= 0; i--) {
                const el = candidates[i];
                if (el.children.length <= 1 && el.textContent && el.textContent.trim() === '\(targetText)') {
                    el.click();
                    return 'clicked btn';
                }
            }
            // 找不到按钮时，向 document 触发键盘左右箭头翻页事件
            document.dispatchEvent(new KeyboardEvent('keydown', { key: '\(key)', code: '\(key)', keyCode: \(keyCode), which: \(keyCode), bubbles: true }));
            document.dispatchEvent(new KeyboardEvent('keyup', { key: '\(key)', code: '\(key)', keyCode: \(keyCode), which: \(keyCode), bubbles: true }));
            // 长滚动模式平滑滚动兜底
            window.scrollBy({top: \(forward ? "window.innerHeight * 0.85" : "-window.innerHeight * 0.85"), behavior: 'smooth'});
            return 'dispatched key';
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }


    func setupAutoHiding() {
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, self.panel.isVisible, !self.isPinned else { return }
            let mouse = NSEvent.mouseLocation
            if !self.panel.frame.contains(mouse) && !self.handlePanel.frame.contains(mouse) {
                DispatchQueue.main.async {
                    self.hideDrawer()
                }
            }
        }

        mouseCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self, self.panel.isVisible, !self.isPinned else { return }
            let mouse = NSEvent.mouseLocation
            if self.panel.frame.contains(mouse) || self.handlePanel.frame.contains(mouse) {
                self.outsideHoverCount = 0
            } else {
                self.outsideHoverCount += 1
                if self.outsideHoverCount >= 4 {
                    self.outsideHoverCount = 0
                    self.hideDrawer()
                }
            }
        }
    }

    @objc func togglePin() {
        isPinned.toggle()
        if let item = statusItem.menu?.items[1] {
            item.title = isPinned ? "取消固定 (允许自动隐藏)" : "固定窗口 (阻止自动隐藏)"
            item.state = isPinned ? .on : .off
        }
    }

    @objc func reloadPage() { webView.reload() }
    @objc func goShelf() {
        if let url = URL(string: "https://weread.qq.com/web/shelf") { webView.load(URLRequest(url: url)) }
    }
    @objc func quitApp() { NSApplication.shared.terminate(nil) }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                if url.host?.contains("qq.com") == true || url.host?.contains("weixin.qq.com") == true {
                    webView.load(navigationAction.request)
                } else { NSWorkspace.shared.open(url) }
            }
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

