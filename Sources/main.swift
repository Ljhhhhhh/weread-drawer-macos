import Cocoa
import WebKit
import Carbon
import ServiceManagement
import SwiftUI

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
        resetHover()
    }

    func resetHover() {
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
    var canTurnPage: (() -> Bool)?
    private var lastScrollTime: TimeInterval = 0
    private var lastPreciseScrollTime: TimeInterval = 0
    private var preciseScrollOffset: CGFloat = 0
    private var preciseGestureTriggered = false
    private var gestureResetWorkItem: DispatchWorkItem?
    private let trackpadPageThreshold: CGFloat = 36

    override func scrollWheel(with event: NSEvent) {
        guard canTurnPage?() == true else {
            resetPreciseGesture()
            super.scrollWheel(with: event)
            return
        }

        if event.hasPreciseScrollingDeltas {
            handlePreciseScroll(event)
            return
        }

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

    private func handlePreciseScroll(_ event: NSEvent) {
        let now = event.timestamp
        if event.phase == .began || now - lastPreciseScrollTime > 0.24 {
            preciseScrollOffset = 0
            preciseGestureTriggered = false
        }
        lastPreciseScrollTime = now

        if !preciseGestureTriggered {
            preciseScrollOffset += event.scrollingDeltaY
            if abs(preciseScrollOffset) >= trackpadPageThreshold {
                preciseGestureTriggered = true
                onScrollPage?(preciseScrollOffset < 0)
            }
        }

        gestureResetWorkItem?.cancel()
        let reset = DispatchWorkItem { [weak self] in
            self?.resetPreciseGesture()
        }
        gestureResetWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: reset)
    }

    private func resetPreciseGesture() {
        gestureResetWorkItem?.cancel()
        gestureResetWorkItem = nil
        preciseScrollOffset = 0
        preciseGestureTriggered = false
    }
}

class PageTurnFeedbackView: NSView {
    private var forward = true
    private var hideWorkItem: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        alphaValue = 0
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(direction: Bool) {
        forward = direction
        setAccessibilityLabel(direction ? "下一页" : "上一页")
        hideWorkItem?.cancel()
        isHidden = false
        alphaValue = 0
        needsDisplay = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        let hide = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0
            }, completionHandler: {
                self.isHidden = true
            })
        }
        hideWorkItem = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.62, execute: hide)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let size = NSSize(width: 148, height: 48)
        let rect = NSRect(x: bounds.midX - size.width / 2, y: 28, width: size.width, height: size.height)
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        NSColor.controlBackgroundColor.withAlphaComponent(0.94).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        path.lineWidth = 1
        path.stroke()

        let symbolName = forward ? "arrow.down.circle.fill" : "arrow.up.circle.fill"
        let symbolRect = NSRect(x: rect.minX + 14, y: rect.minY + 13, width: 22, height: 22)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            image.draw(in: symbolRect)
        }

        let title = forward ? "下一页" : "上一页"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        title.draw(at: NSPoint(x: rect.minX + 44, y: rect.minY + 16), withAttributes: attributes)
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
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
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

enum ThemeMode: String {
    case auto = "auto"
    case light = "light"
    case dark = "dark"
}

enum VerticalAlignment: String {
    case bottom = "bottom"
    case top = "top"
}

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, NSMenuDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var panel: WeReadPanel!
    var handles: [(screen: NSScreen, panel: HandlePanel)] = []
    var drawerScreen: NSScreen?
    var webView: WeReadWebView!
    var resizeHandle: ResizeHandleView!
    var pageTurnFeedbackView: PageTurnFeedbackView!
    var drawerWidth: CGFloat = 520
    var maxHeightRatio: CGFloat = 1.0
    var verticalAlignment: VerticalAlignment = .bottom
    var isAnimating: Bool = false
    var globalHotKeyRef: EventHotKeyRef?
    var themeHotKeyRef: EventHotKeyRef?
    var hotKeyEventHandler: EventHandlerRef?
    var themeMode: ThemeMode = .auto
    var isPinned: Bool = false
    private var totalSeconds: TimeInterval = 0
    private var openCount: Int = 0
    private var dailySeconds: [String: Double] = [:]
    private var dailyOpenCounts: [String: Int] = [:]
    private var currentSessionStartTime: Date?
    private var statsMenuItem: NSMenuItem?
    private var statsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        loadSavedSettings()
        setupStatusItem()
        setupPanel()
        setupHandle()
        setupWebView()
        setupThemeObserver()
        setupGlobalHotKey()
        setupAutoHiding()
        setupScreenObserver()
        loadWeRead()
        showDrawer()
    }

    func loadSavedSettings() {
        let saved = UserDefaults.standard.double(forKey: "WeReadDrawerWidth")
        if saved >= 380 && saved <= 1400 { drawerWidth = CGFloat(saved) }
        let savedHeight = UserDefaults.standard.double(forKey: "WeReadMaxHeightRatio")
        if savedHeight > 0 && savedHeight <= 1.0 { maxHeightRatio = CGFloat(savedHeight) }
        if let rawAlign = UserDefaults.standard.string(forKey: "WeReadVerticalAlignment"),
           let savedAlign = VerticalAlignment(rawValue: rawAlign) {
            verticalAlignment = savedAlign
        }
        totalSeconds = UserDefaults.standard.double(forKey: "WeReadTotalReadSeconds")
        openCount = UserDefaults.standard.integer(forKey: "WeReadTotalOpenCount")
        dailySeconds = UserDefaults.standard.dictionary(forKey: "WeReadDailyReadSeconds") as? [String: Double] ?? [:]
        dailyOpenCounts = UserDefaults.standard.dictionary(forKey: "WeReadDailyOpenCounts") as? [String: Int] ?? [:]
        if let rawMode = UserDefaults.standard.string(forKey: "WeReadThemeMode"),
           let savedMode = ThemeMode(rawValue: rawMode) {
            themeMode = savedMode
        }
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
        let statsMenu = NSMenu()
        let todayItem = NSMenuItem(title: "今日: 0 分钟 / 打开 0 次", action: nil, keyEquivalent: "")
        todayItem.isEnabled = false
        statsMenu.addItem(todayItem)
        let totalItem = NSMenuItem(title: "累计: 0 分钟 / 打开 0 次", action: nil, keyEquivalent: "")
        totalItem.isEnabled = false
        statsMenu.addItem(totalItem)
        statsMenu.addItem(NSMenuItem.separator())
        statsMenu.addItem(NSMenuItem(title: "打开详细统计看板...", action: #selector(openStatsDashboard), keyEquivalent: ""))
        let statsRootItem = NSMenuItem(title: "📊 今日: 0 分钟 · 累计: 0 分钟", action: nil, keyEquivalent: "")
        statsRootItem.submenu = statsMenu
        menu.addItem(statsRootItem)
        statsMenuItem = statsRootItem
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

        let heightMenu = NSMenu()
        let hFull = NSMenuItem(title: "全屏高度 (100%)", action: #selector(setMaxHeightPreset(_:)), keyEquivalent: "")
        hFull.tag = 100
        heightMenu.addItem(hFull)
        let h85 = NSMenuItem(title: "85% 高度", action: #selector(setMaxHeightPreset(_:)), keyEquivalent: "")
        h85.tag = 85
        heightMenu.addItem(h85)
        let h70 = NSMenuItem(title: "70% 高度", action: #selector(setMaxHeightPreset(_:)), keyEquivalent: "")
        h70.tag = 70
        heightMenu.addItem(h70)
        let h55 = NSMenuItem(title: "55% 高度", action: #selector(setMaxHeightPreset(_:)), keyEquivalent: "")
        h55.tag = 55
        heightMenu.addItem(h55)
        heightMenu.addItem(NSMenuItem.separator())
        let alignBottom = NSMenuItem(title: "贴底对齐", action: #selector(setVerticalAlignBottom), keyEquivalent: "")
        heightMenu.addItem(alignBottom)
        let alignTop = NSMenuItem(title: "贴顶对齐", action: #selector(setVerticalAlignTop), keyEquivalent: "")
        heightMenu.addItem(alignTop)
        let heightItem = NSMenuItem(title: "抽屉高度与对齐", action: nil, keyEquivalent: "")
        heightItem.submenu = heightMenu
        menu.addItem(heightItem)

        let themeItem = NSMenuItem(title: "外观主题", action: nil, keyEquivalent: "")
        let themeMenu = NSMenu()
        themeMenu.addItem(NSMenuItem(title: "跟随系统", action: #selector(setThemeAuto), keyEquivalent: ""))
        themeMenu.addItem(NSMenuItem(title: "亮色模式", action: #selector(setThemeLight), keyEquivalent: ""))
        themeMenu.addItem(NSMenuItem(title: "暗色模式 (快捷键 ⌥+T)", action: #selector(setThemeDark), keyEquivalent: ""))
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

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
        let rect = targetFrame(for: screen)
        panel = WeReadPanel(contentRect: rect)
        panel.delegate = self
        panel.minSize = NSSize(width: 380, height: 400)
        panel.onEscapePressed = { [weak self] in
            self?.hideDrawer()
        }
        panel.onResignKey = { [weak self] in
            guard let self = self else { return }
            self.scheduleHideIfNeeded()
        }

        resizeHandle = ResizeHandleView(frame: NSRect(x: 0, y: 0, width: 6, height: rect.height))
        resizeHandle.autoresizingMask = [.height]
        resizeHandle.onResize = { [weak self] deltaX in
            guard let self = self else { return }
            let screen = self.drawerScreen ?? self.currentActiveScreen()
            let vis = screen.visibleFrame
            let newWidth = min(max(self.panel.frame.width + deltaX, 380), min(1400, vis.width * 0.85))
            self.drawerWidth = newWidth
            self.updatePanelFrame(animated: false)
        }
        resizeHandle.onResizeEnded = { [weak self] in
            guard let self = self else { return }
            UserDefaults.standard.set(Double(self.drawerWidth), forKey: "WeReadDrawerWidth")
        }
        panel.contentView?.addSubview(resizeHandle, positioned: .above, relativeTo: nil)
    }

    func setupHandle() {
        for handle in handles {
            (handle.panel.contentView as? HandleView)?.resetHover()
            handle.panel.orderOut(nil)
        }
        handles = NSScreen.screens.map { screen in
            let frame = screen.frame
            let handleWidth: CGFloat = 16
            let handlePanel = HandlePanel(contentRect: NSRect(x: frame.maxX - handleWidth, y: frame.minY, width: handleWidth, height: frame.height))
            let handleView = HandleView(frame: NSRect(x: 0, y: 0, width: handleWidth, height: frame.height))
            let open: () -> Void = { [weak self] in self?.showDrawer(on: screen) }
            handleView.onClick = open
            handleView.onDragOpen = open
            handleView.onHoverOpen = open
            handlePanel.contentView = handleView
            return (screen, handlePanel)
        }
        showHandle()
    }

    func setupScreenObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let screen = NSScreen.screens.first { $0 == self.drawerScreen } ?? self.currentActiveScreen()
            self.drawerScreen = screen
            if self.panel.isVisible {
                self.updatePanelFrame(animated: false)
            }
            self.setupHandle()
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
        
        // 核心：监听鼠标滚轮与触控板手势触发翻页。
        webView.onScrollPage = { [weak self] forward in
            guard let self = self else { return }
            self.flipPage(forward: forward)
            self.pageTurnFeedbackView.show(direction: forward)
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        webView.canTurnPage = { [weak self] in
            self?.webView.url?.path.contains("/web/reader/") == true
        }

        panel.contentView?.addSubview(webView)
        pageTurnFeedbackView = PageTurnFeedbackView(frame: webView.bounds)
        pageTurnFeedbackView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(pageTurnFeedbackView, positioned: .above, relativeTo: webView)
    }

    func setupGlobalHotKey() {
        let toggleDrawerID = EventHotKeyID(signature: OSType(0x57524452), id: 1)
        let toggleThemeID = EventHotKeyID(signature: OSType(0x57524452), id: 2)
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, eventRef, userData) -> OSStatus in
            guard let ptr = userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async {
                if hotKeyID.id == 1 {
                    delegate.toggleDrawer()
                } else if hotKeyID.id == 2 {
                    delegate.toggleThemeMode()
                }
            }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyEventHandler)
        let s1 = RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey), toggleDrawerID, GetApplicationEventTarget(), 0, &globalHotKeyRef)
        let s2 = RegisterEventHotKey(UInt32(kVK_ANSI_T), UInt32(optionKey), toggleThemeID, GetApplicationEventTarget(), 0, &themeHotKeyRef)
        if s1 != noErr || s2 != noErr {
            NSLog("[WeReadDrawer] 注册全局快捷键结果: ⌥+S code=%d, ⌥+T code=%d", s1, s2)
        }
    }

    func loadWeRead() {
        if let url = URL(string: "https://weread.qq.com") { webView.load(URLRequest(url: url)) }
    }

    func targetFrame(for screen: NSScreen, width: CGFloat? = nil) -> NSRect {
        let vis = screen.visibleFrame
        let w = width ?? drawerWidth
        let effectiveHeight = min(vis.height, max(400, vis.height * maxHeightRatio))
        let y = (verticalAlignment == .top) ? (vis.maxY - effectiveHeight) : vis.minY
        return NSRect(x: vis.maxX - w, y: y, width: w, height: effectiveHeight)
    }

    func updatePanelFrame(animated: Bool = false) {
        guard panel != nil else { return }
        let screen = drawerScreen ?? currentActiveScreen()
        let frame = targetFrame(for: screen)
        if animated {
            panel.animator().setFrame(frame, display: true)
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    @objc func toggleDrawer() {
        if panel.isVisible { hideDrawer() } else { showDrawer() }
    }

    func showDrawer(on requestedScreen: NSScreen? = nil) {
        guard !isAnimating else { return }
        let screen = requestedScreen ?? currentActiveScreen()
        guard !panel.isVisible || drawerScreen != screen else { return }
        drawerScreen = screen
        if !panel.isVisible {
            openCount += 1
            let today = todayKey()
            dailyOpenCounts[today, default: 0] += 1
            currentSessionStartTime = Date()
            UserDefaults.standard.set(dailyOpenCounts, forKey: "WeReadDailyOpenCounts")
            UserDefaults.standard.set(openCount, forKey: "WeReadTotalOpenCount")
            updateStatsMenuItem()
        }
        let visible = screen.visibleFrame
        let target = targetFrame(for: screen)
        let offscreen = NSRect(x: visible.maxX, y: target.minY, width: target.width, height: target.height)

        panel.setFrame(offscreen, display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        showHandle()

        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            self?.isAnimating = false
            self?.applyCurrentTheme()
        })
    }

    func hideDrawer() {
        guard !isAnimating && panel.isVisible else { return }
        saveVerticalAlignment()
        recordSessionTime()
        drawerWidth = panel.frame.width
        UserDefaults.standard.set(Double(drawerWidth), forKey: "WeReadDrawerWidth")

        let screen = drawerScreen ?? currentActiveScreen()
        let visible = screen.visibleFrame
        let current = panel.frame
        let offscreen = NSRect(x: visible.maxX, y: current.minY, width: current.width, height: current.height)

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
        for handle in handles {
            if panel.isVisible && handle.screen == drawerScreen {
                (handle.panel.contentView as? HandleView)?.resetHover()
                handle.panel.orderOut(nil)
            } else {
                handle.panel.orderFrontRegardless()
            }
        }
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
            self?.scheduleHideIfNeeded()
        }
    }

    private func scheduleHideIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.panel.isVisible, !self.isPinned else { return }
            let mouse = NSEvent.mouseLocation
            if self.panel.frame.contains(mouse) || self.handles.contains(where: { $0.panel.isVisible && $0.panel.frame.contains(mouse) }) { return }
            self.hideDrawer()
        }
    }

    @objc func togglePin() {
        isPinned.toggle()
        updatePinMenuItem()
    }

    private func updatePinMenuItem() {
        guard let item = statusItem.menu?.items.first(where: { $0.action == #selector(togglePin) }) else { return }
        item.title = isPinned ? "取消固定 (允许自动隐藏)" : "固定窗口 (阻止自动隐藏)"
        item.state = isPinned ? .on : .off
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
            updatePanelFrame(animated: true)
        }
    }

    @objc func setMaxHeightPreset(_ sender: NSMenuItem) {
        maxHeightRatio = CGFloat(sender.tag) / 100.0
        UserDefaults.standard.set(Double(maxHeightRatio), forKey: "WeReadMaxHeightRatio")
        if panel.isVisible {
            updatePanelFrame(animated: true)
        }
    }

    @objc func setVerticalAlignBottom() {
        verticalAlignment = .bottom
        UserDefaults.standard.set(verticalAlignment.rawValue, forKey: "WeReadVerticalAlignment")
        if panel.isVisible {
            updatePanelFrame(animated: true)
        }
    }

    @objc func setVerticalAlignTop() {
        verticalAlignment = .top
        UserDefaults.standard.set(verticalAlignment.rawValue, forKey: "WeReadVerticalAlignment")
        if panel.isVisible {
            updatePanelFrame(animated: true)
        }
    }

    func setupThemeObserver() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.themeMode == .auto {
                self.applyCurrentTheme()
            }
        }
    }

    func isEffectiveDark() -> Bool {
        switch themeMode {
        case .dark: return true
        case .light: return false
        case .auto:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
    }

    func applyCurrentTheme() {
        let dark = isEffectiveDark()
        panel.appearance = dark ? NSAppearance(named: .darkAqua) : NSAppearance(named: .aqua)
        webView.appearance = panel.appearance
        panel.backgroundColor = dark ? NSColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0) : NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)

        // 纯粹调用微信读书官方自带的切换机制，不添加任何自定义 CSS 覆写
        let js = """
        (function(targetDark) {
            const isCurrentlyWhite = document.body && document.body.classList.contains("wr_whiteTheme");
            const isCurrentlyDark = !isCurrentlyWhite;
            if (targetDark === isCurrentlyDark) return;

            // 1. 阅读器内：点击微信读书官方自带的亮色/暗色切换按钮
            if (targetDark) {
                // 当前为浅色，需切换为深色：触发包含 dark 类名的按钮（月亮图标）
                const darkBtn = document.querySelector(".readerControls_item.dark, .readerControls button.dark, .rbsp_color_item.dark, button[title*='深色']");
                if (darkBtn) { darkBtn.click(); return; }
            } else {
                // 当前为深色，需切换为浅色：触发包含 white 类名的按钮（太阳图标）
                const whiteBtn = document.querySelector(".readerControls_item.white, .readerControls button.white, .rbsp_color_item.white, button[title*='浅色']");
                if (whiteBtn) { whiteBtn.click(); return; }
            }

            // 兜底：直接触发阅读器内的主题切换按钮
            const anyThemeBtn = document.querySelector(".readerControls_item.white, .readerControls_item.dark, .readerControls button.white, .readerControls button.dark");
            if (anyThemeBtn) { anyThemeBtn.click(); return; }

            // 2. 非阅读页（书架、主页）：调用官方 Vuex Store 的 toggleTheme 动作
            try {
                const root = document.getElementById("app") || document.querySelector(".app") || document.body;
                const store = (root && root.__vue__ && root.__vue__.$store) ? root.__vue__.$store : null;
                if (store && store.dispatch) {
                    store.dispatch("toggleTheme", { isWhite: !targetDark, modifyCookie: true });
                }
            } catch(e) {}
        })(\(dark));
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    @objc func toggleThemeMode() {
        // 快捷键 ⌥+T：直接触发微信读书官方阅读器自带的主题切换按钮
        let js = """
        (function() {
            const btn = document.querySelector(".readerControls_item.white, .readerControls_item.dark, .readerControls button.white, .readerControls button.dark");
            if (btn) {
                btn.click();
                return true;
            }
            return false;
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] (res, _) in
            guard let self = self else { return }
            if (res as? Bool) != true {
                let currentDark = self.isEffectiveDark()
                self.themeMode = currentDark ? .light : .dark
                UserDefaults.standard.set(self.themeMode.rawValue, forKey: "WeReadThemeMode")
                self.applyCurrentTheme()
            }
        }
    }

    @objc func setThemeAuto() {
        themeMode = .auto
        UserDefaults.standard.set(themeMode.rawValue, forKey: "WeReadThemeMode")
        applyCurrentTheme()
    }

    @objc func setThemeLight() {
        themeMode = .light
        UserDefaults.standard.set(themeMode.rawValue, forKey: "WeReadThemeMode")
        applyCurrentTheme()
    }

    @objc func setThemeDark() {
        themeMode = .dark
        UserDefaults.standard.set(themeMode.rawValue, forKey: "WeReadThemeMode")
        applyCurrentTheme()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyCurrentTheme()
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
        if let themeHotKey = themeHotKeyRef {
            UnregisterEventHotKey(themeHotKey)
        }
        if let handler = hotKeyEventHandler {
            RemoveEventHandler(handler)
        }
    }

    private func recordSessionTime() {
        if let start = currentSessionStartTime {
            let elapsed = Date().timeIntervalSince(start)
            let today = todayKey()
            totalSeconds += elapsed
            dailySeconds[today, default: 0] += elapsed
            UserDefaults.standard.set(totalSeconds, forKey: "WeReadTotalReadSeconds")
            UserDefaults.standard.set(dailySeconds, forKey: "WeReadDailyReadSeconds")
            currentSessionStartTime = nil
            updateStatsMenuItem()
        }
    }

    private func todayKey(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func updateStatsMenuItem() {
        let today = todayKey()
        var todaySec = dailySeconds[today] ?? 0
        var totalSec = totalSeconds
        if let start = currentSessionStartTime {
            let live = Date().timeIntervalSince(start)
            todaySec += live
            totalSec += live
        }
        let todayMins = Int(todaySec / 60)
        let totalMins = Int(totalSec / 60)
        let todayOpens = dailyOpenCounts[today] ?? 0

        statsMenuItem?.title = "📊 今日: \(todayMins) 分钟 · 累计: \(totalMins) 分钟"
        if let sub = statsMenuItem?.submenu, sub.items.count >= 2 {
            sub.items[0].title = "今日阅读: \(todayMins) 分钟 / 打开 \(todayOpens) 次"
            sub.items[1].title = "历史累计: \(totalMins) 分钟 / 打开 \(openCount) 次"
        }
    }

    @objc func openStatsDashboard() {
        let today = todayKey()
        var todaySec = dailySeconds[today] ?? 0
        var totalSec = totalSeconds
        if let start = currentSessionStartTime {
            let live = Date().timeIntervalSince(start)
            todaySec += live
            totalSec += live
        }
        let todayMins = Int(todaySec / 60)
        let totalMins = Int(totalSec / 60)
        let todayOpens = dailyOpenCounts[today] ?? 0

        let cal = Calendar.current
        let now = Date()
        let fmtDay = DateFormatter()
        fmtDay.dateFormat = "M/d"

        var recentList: [StatsDayItem] = []
        for i in (0..<7).reversed() {
            if let date = cal.date(byAdding: .day, value: -i, to: now) {
                let key = todayKey(for: date)
                var sec = dailySeconds[key] ?? 0
                if i == 0, let start = currentSessionStartTime {
                    sec += Date().timeIntervalSince(start)
                }
                let mins = Int(sec / 60)
                let opens = dailyOpenCounts[key] ?? 0
                let label = i == 0 ? "今天" : fmtDay.string(from: date)
                recentList.append(StatsDayItem(dateKey: key, label: label, minutes: mins, opens: opens, isToday: i == 0))
            }
        }

        let contentView = StatsDashboardView(
            todayMinutes: todayMins,
            todayOpens: todayOpens,
            totalMinutes: totalMins,
            totalOpens: openCount,
            recentDays: recentList
        )

        if let controller = statsWindowController, let window = controller.window {
            window.contentView = NSHostingView(rootView: contentView)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 490),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "阅读统计看板"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: contentView)

        let controller = NSWindowController(window: window)
        statsWindowController = controller
        window.delegate = self
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        let screen = drawerScreen ?? window.screen ?? currentActiveScreen()
        saveVerticalAlignment()
        maxHeightRatio = min(1, window.frame.height / screen.visibleFrame.height)
        drawerWidth = window.frame.width
        UserDefaults.standard.set(Double(maxHeightRatio), forKey: "WeReadMaxHeightRatio")
        UserDefaults.standard.set(Double(drawerWidth), forKey: "WeReadDrawerWidth")
        updatePanelFrame()
    }

    private func saveVerticalAlignment() {
        let visible = (drawerScreen ?? panel.screen ?? currentActiveScreen()).visibleFrame
        let bottomGap = abs(panel.frame.minY - visible.minY)
        let topGap = abs(panel.frame.maxY - visible.maxY)
        // Full-height windows do not indicate a preferred edge.
        guard abs(bottomGap - topGap) > 1 else { return }
        verticalAlignment = bottomGap < topGap ? .bottom : .top
        UserDefaults.standard.set(verticalAlignment.rawValue, forKey: "WeReadVerticalAlignment")
    }

    func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, closingWindow == statsWindowController?.window {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateStatsMenuItem()
        if let themeItem = statusItem.menu?.items.first(where: { $0.submenu != nil && $0.title.contains("外观主题") }),
           let sub = themeItem.submenu {
            for item in sub.items {
                switch item.action {
                case #selector(setThemeAuto): item.state = themeMode == .auto ? .on : .off
                case #selector(setThemeLight): item.state = themeMode == .light ? .on : .off
                case #selector(setThemeDark): item.state = themeMode == .dark ? .on : .off
                default: break
                }
            }
        }
        if let heightItem = statusItem.menu?.items.first(where: { $0.submenu != nil && $0.title.contains("抽屉高度与对齐") }),
           let sub = heightItem.submenu {
            for item in sub.items {
                if item.action == #selector(setMaxHeightPreset(_:)) {
                    let tagRatio = CGFloat(item.tag) / 100.0
                    item.state = abs(maxHeightRatio - tagRatio) < 0.01 ? .on : .off
                } else if item.action == #selector(setVerticalAlignBottom) {
                    item.state = verticalAlignment == .bottom ? .on : .off
                } else if item.action == #selector(setVerticalAlignTop) {
                    item.state = verticalAlignment == .top ? .on : .off
                }
            }
        }
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

struct StatsDayItem: Identifiable {
    var id: String { dateKey }
    let dateKey: String
    let label: String
    let minutes: Int
    let opens: Int
    let isToday: Bool
}

struct StatsDashboardView: View {
    let todayMinutes: Int
    let todayOpens: Int
    let totalMinutes: Int
    let totalOpens: Int
    let recentDays: [StatsDayItem]

    private var maxMins: Int {
        max(recentDays.map { $0.minutes }.max() ?? 1, 30)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("阅读统计看板")
                        .font(.system(size: 20, weight: .bold))
                    Text("追踪每日阅读节奏与历史沉淀")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.linearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
            }

            HStack(spacing: 12) {
                statCard(title: "今日专注", primaryText: "\(todayMinutes) 分钟", subText: "打开 \(todayOpens) 次", icon: "flame.fill", color: .orange)
                statCard(title: "历史累计", primaryText: "\(totalMinutes) 分钟", subText: "打开 \(totalOpens) 次", icon: "clock.arrow.circlepath", color: .blue)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("近 7 天趋势")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(recentDays) { item in
                        VStack(spacing: 6) {
                            Text("\(item.minutes)m")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(item.isToday ? .accentColor : .secondary)

                            GeometryReader { geo in
                                VStack {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 5)
                                        .fill(item.isToday ? Color.accentColor : Color.secondary.opacity(0.25))
                                        .frame(height: max(CGFloat(item.minutes) / CGFloat(maxMins) * geo.size.height, 4))
                                }
                            }
                            .frame(height: 110)

                            Text(item.label)
                                .font(.system(size: 11, weight: item.isToday ? .bold : .regular))
                                .foregroundColor(item.isToday ? .primary : .secondary)
                        }
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor).opacity(0.6)))
            }

            Spacer(minLength: 0)
        }
        .padding(26)
        .padding(.top, 14)
        .frame(width: 440, height: 480)
    }

    private func statCard(title: String, primaryText: String, subText: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Text(primaryText)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(subText)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
