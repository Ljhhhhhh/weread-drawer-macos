import Cocoa
import WebKit
import Carbon
import ServiceManagement

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
    var onDragOpen: (() -> Void)?
    var onHoverOpen: (() -> Void)?
    private var isHovered: Bool = false
    private var dragStartX: CGFloat = 0
    private var hoverTimer: Timer?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
            guard let self = self, self.isHovered else { return }
            self.onHoverOpen?()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    override func mouseDown(with event: NSEvent) {
        hoverTimer?.invalidate()
        hoverTimer = nil
        dragStartX = NSEvent.mouseLocation.x
    }

    override func mouseDragged(with event: NSEvent) {
        let currentX = NSEvent.mouseLocation.x
        if dragStartX - currentX > 18 {
            dragStartX = currentX
            onDragOpen?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let currentX = NSEvent.mouseLocation.x
        if abs(dragStartX - currentX) < 6 {
            onClick?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let handleHeight: CGFloat = isHovered ? 96 : 80
        let handleWidth: CGFloat = isHovered ? 7 : 4
        let handleY = (bounds.height - handleHeight) / 2
        let pillRect = NSRect(x: bounds.maxX - handleWidth - 2, y: handleY, width: handleWidth, height: handleHeight)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: handleWidth / 2, yRadius: handleWidth / 2)
        let alpha: CGFloat = isHovered ? 0.75 : 0.4
        NSColor.systemGray.withAlphaComponent(alpha).setFill()
        path.fill()
    }
}

class ResizeHandleView: NSView {
    var onResize: ((CGFloat) -> Void)?
    var onResizeEnded: (() -> Void)?
    private var initialMouseX: CGFloat = 0

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseX = NSEvent.mouseLocation.x
    }

    override func mouseDragged(with event: NSEvent) {
        let currentMouseX = NSEvent.mouseLocation.x
        let deltaX = initialMouseX - currentMouseX
        initialMouseX = currentMouseX
        onResize?(deltaX)
    }

    override func mouseUp(with event: NSEvent) {
        onResizeEnded?()
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
    var onEscapePressed: (() -> Void)?
    var onResignKey: (() -> Void)?
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

    override func cancelOperation(_ sender: Any?) {
        onEscapePressed?()
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var panel: WeReadPanel!
    var handlePanel: HandlePanel!
    var handleView: HandleView!
    var webView: WeReadWebView!
    var resizeHandle: ResizeHandleView!
    var drawerWidth: CGFloat = 520
    var isAnimating: Bool = false
    var globalHotKeyRef: EventHotKeyRef?
    var hotKeyEventHandler: EventHandlerRef?
    var isPinned: Bool = false
    private var totalSeconds: TimeInterval = 0
    private var openCount: Int = 0
    private var currentSessionStartTime: Date?
    private var statsMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSavedSettings()
        setupStatusItem()
        setupPanel()
        setupHandle()
        setupWebView()
        setupGlobalHotKey()
        setupAutoHiding()
        setupScreenObserver()
        loadWeRead()
        showDrawer()
    }

    func loadSavedSettings() {
        let saved = UserDefaults.standard.double(forKey: "WeReadDrawerWidth")
        if saved >= 380 && saved <= 1400 { drawerWidth = CGFloat(saved) }
        totalSeconds = UserDefaults.standard.double(forKey: "WeReadTotalReadSeconds")
        openCount = UserDefaults.standard.integer(forKey: "WeReadTotalOpenCount")
    }

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            if let image = NSImage(systemSymbolName: "book.pages", accessibilityDescription: "WeRead Drawer")?.withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            } else if let fallback = NSImage(systemSymbolName: "book", accessibilityDescription: "WeRead Drawer")?.withSymbolConfiguration(config) {
                fallback.isTemplate = true
                button.image = fallback
            } else {
                button.title = "📖"
            }
            button.action = #selector(toggleDrawer)
            button.target = self
        }
        let menu = NSMenu()
        let statsItem = NSMenuItem(title: statsSummaryString(), action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)
        statsMenuItem = statsItem
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "显示/隐藏抽屉 (⌥+S)", action: #selector(toggleDrawer), keyEquivalent: "s"))
        let pinItem = NSMenuItem(title: "固定窗口 (阻止自动隐藏)", action: #selector(togglePin), keyEquivalent: "p")
        pinItem.state = isPinned ? .on : .off
        menu.addItem(pinItem)

        let autoLaunchItem = NSMenuItem(title: "开机自启动", action: #selector(toggleAutoLaunch), keyEquivalent: "")
        autoLaunchItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(autoLaunchItem)

        menu.addItem(NSMenuItem.separator())
        let widthMenu = NSMenu()
        let w420 = NSMenuItem(title: "精简 (420px)", action: #selector(setWidthPreset(_:)), keyEquivalent: "")
        w420.tag = 420
        widthMenu.addItem(w420)
        let w520 = NSMenuItem(title: "标准 (520px)", action: #selector(setWidthPreset(_:)), keyEquivalent: "")
        w520.tag = 520
        widthMenu.addItem(w520)
        let w680 = NSMenuItem(title: "宽屏 (680px)", action: #selector(setWidthPreset(_:)), keyEquivalent: "")
        w680.tag = 680
        widthMenu.addItem(w680)
        let w840 = NSMenuItem(title: "沉浸 (840px)", action: #selector(setWidthPreset(_:)), keyEquivalent: "")
        w840.tag = 840
        widthMenu.addItem(w840)
        let widthItem = NSMenuItem(title: "抽屉宽度预设", action: nil, keyEquivalent: "")
        widthItem.submenu = widthMenu
        menu.addItem(widthItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "回到书架", action: #selector(goShelf), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "刷新页面", action: #selector(reloadPage), keyEquivalent: "r"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        menu.delegate = self
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
        panel.onEscapePressed = { [weak self] in
            self?.hideDrawer()
        }
        panel.onResignKey = { [weak self] in
            guard let self = self, !self.isPinned, self.panel.isVisible else { return }
            DispatchQueue.main.async {
                self.hideDrawer()
            }
        }

        resizeHandle = ResizeHandleView(frame: NSRect(x: 0, y: 0, width: 6, height: rect.height))
        resizeHandle.autoresizingMask = [.height]
        resizeHandle.onResize = { [weak self] deltaX in
            guard let self = self else { return }
            let screen = self.currentActiveScreen()
            let vis = screen.visibleFrame
            let newWidth = min(max(self.panel.frame.width + deltaX, 380), min(1400, vis.width * 0.85))
            self.drawerWidth = newWidth
            let newFrame = NSRect(x: vis.maxX - newWidth, y: vis.minY, width: newWidth, height: vis.height)
            self.panel.setFrame(newFrame, display: true)
        }
        resizeHandle.onResizeEnded = { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.set(Double(self.drawerWidth), forKey: "WeReadDrawerWidth")
        }
        panel.contentView?.addSubview(resizeHandle, positioned: .above, relativeTo: nil)
    }

    func setupHandle() {
        let screen = currentActiveScreen()
        let frame = screen.frame
        let handleWidth: CGFloat = 16
        handlePanel = HandlePanel(contentRect: NSRect(x: frame.maxX - handleWidth, y: frame.minY, width: handleWidth, height: frame.height))
        handleView = HandleView(frame: NSRect(x: 0, y: 0, width: handleWidth, height: frame.height))
        handleView.onClick = { [weak self] in self?.showDrawer() }
        handleView.onDragOpen = { [weak self] in self?.showDrawer() }
        handleView.onHoverOpen = { [weak self] in self?.showDrawer() }
        handlePanel.contentView = handleView
    }

    func setupScreenObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let screen = self.currentActiveScreen()
            let vis = screen.visibleFrame
            if self.panel.isVisible {
                let target = NSRect(x: vis.maxX - self.drawerWidth, y: vis.minY, width: self.drawerWidth, height: vis.height)
                self.panel.setFrame(target, display: true)
            } else {
                self.showHandle()
            }
        }
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
        let hotKeyID = EventHotKeyID(signature: OSType(0x57524452), id: 1)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            guard let ptr = userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
            DispatchQueue.main.async {
                delegate.toggleDrawer()
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyEventHandler)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &globalHotKeyRef)
        if status != noErr {
            NSLog("[WeReadDrawer] 注册全局快捷键 ⌥+S 失败，错误码: %d", status)
        }
    }

    func loadWeRead() {
        if let url = URL(string: "https://weread.qq.com") { webView.load(URLRequest(url: url)) }
    }

    @objc func toggleDrawer() {
        if panel.isVisible { hideDrawer() } else { showDrawer() }
    }

    func showDrawer() {
        guard !isAnimating else { return }
        if !panel.isVisible {
            openCount += 1
            currentSessionStartTime = Date()
            UserDefaults.standard.set(openCount, forKey: "WeReadTotalOpenCount")
            updateStatsMenuItem()
        }
        let screen = currentActiveScreen()
        let visible = screen.visibleFrame
        let target = NSRect(x: visible.maxX - drawerWidth, y: visible.minY, width: drawerWidth, height: visible.height)
        let offscreen = NSRect(x: visible.maxX, y: visible.minY, width: drawerWidth, height: visible.height)

        handlePanel.orderOut(nil)
        panel.setFrame(offscreen, display: false)
        panel.orderFrontRegardless()
        panel.makeKey()

        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            self?.isAnimating = false
        })
    }

    func hideDrawer() {
        guard !isAnimating && panel.isVisible else { return }
        recordSessionTime()
        drawerWidth = panel.frame.width
        UserDefaults.standard.set(Double(drawerWidth), forKey: "WeReadDrawerWidth")

        let screen = currentActiveScreen()
        let visible = screen.visibleFrame
        let offscreen = NSRect(x: visible.maxX, y: visible.minY, width: drawerWidth, height: visible.height)

        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(offscreen, display: true)
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.panel.orderOut(nil)
            self.isAnimating = false
            self.showHandle()
        })
    }

    func showHandle() {
        let screen = currentActiveScreen()
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
    }

    @objc func togglePin() {
        isPinned.toggle()
        if let item = statusItem.menu?.items[1] {
            item.title = isPinned ? "取消固定 (允许自动隐藏)" : "固定窗口 (阻止自动隐藏)"
            item.state = isPinned ? .on : .off
        }
    }

    @objc func toggleAutoLaunch() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("[WeReadDrawer] 切换开机自启动失败: %@", error.localizedDescription)
        }
        if let item = statusItem.menu?.items.first(where: { $0.action == #selector(toggleAutoLaunch) }) {
            item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc func setWidthPreset(_ sender: NSMenuItem) {
        drawerWidth = CGFloat(sender.tag)
        UserDefaults.standard.set(Double(drawerWidth), forKey: "WeReadDrawerWidth")
        if panel.isVisible {
            let screen = currentActiveScreen()
            let vis = screen.visibleFrame
            let newFrame = NSRect(x: vis.maxX - drawerWidth, y: vis.minY, width: drawerWidth, height: vis.height)
            panel.setFrame(newFrame, display: true)
        }
    }

    @objc func reloadPage() { webView.reload() }
    @objc func goShelf() {
        if let url = URL(string: "https://weread.qq.com/web/shelf") { webView.load(URLRequest(url: url)) }
    }
    @objc func quitApp() { NSApplication.shared.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        recordSessionTime()
        if let hotKey = globalHotKeyRef {
            UnregisterEventHotKey(hotKey)
        }
        if let handler = hotKeyEventHandler {
            RemoveEventHandler(handler)
        }
    }

    private func recordSessionTime() {
        if let start = currentSessionStartTime {
            let elapsed = Date().timeIntervalSince(start)
            totalSeconds += elapsed
            UserDefaults.standard.set(totalSeconds, forKey: "WeReadTotalReadSeconds")
            currentSessionStartTime = nil
            updateStatsMenuItem()
        }
    }

    private func statsSummaryString() -> String {
        var liveSeconds = totalSeconds
        if let start = currentSessionStartTime {
            liveSeconds += Date().timeIntervalSince(start)
        }
        let minutes = Int(liveSeconds / 60)
        return "📊 阅读统计: \(minutes) 分钟 / 打开 \(openCount) 次"
    }

    private func updateStatsMenuItem() {
        statsMenuItem?.title = statsSummaryString()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStatsMenuItem()
    }

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
