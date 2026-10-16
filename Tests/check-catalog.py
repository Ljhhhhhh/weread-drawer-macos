#!/usr/bin/env python3
"""Exercise the native catalog button against a public WeRead reader page."""
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Sources/main.swift").read_text().split("let app = NSApplication.shared")[0]

check = r'''
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

class CatalogTestDelegate: AppDelegate {
    var readerLoaded = false
    override func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        super.webView(webView, didFinish: navigation)
        readerLoaded = true
    }
}

let delegate = CatalogTestDelegate()
delegate.setupStatusItem()
delegate.setupPanel()
delegate.setupWebView()
guard let readerWebView = delegate.webView else { fatalError("Reader web view was not created") }
delegate.panel.orderFrontRegardless()
delegate.updatePanelFrame()
guard delegate.catalogButton?.isHidden == true else { fatalError("Catalog button should start hidden") }

func waitFor(_ condition: @escaping (@escaping (Bool) -> Void) -> Void, timeout: TimeInterval = 30) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        var result: Bool?
        condition { result = $0 }
        let checkDeadline = Date().addingTimeInterval(0.5)
        while result == nil && Date() < checkDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        if result == true { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }
    return false
}

func catalogState(_ done: @escaping (Bool) -> Void) {
    readerWebView.evaluateJavaScript("""
        (() => {
            const catalog = document.querySelector('.readerCatalog');
            const list = document.querySelector('.readerCatalog_list_scroll_area');
            const toolbar = document.querySelector('.reader_toolbar_container');
            if (!catalog || !list || getComputedStyle(catalog).display === 'none') return false;
            const rect = catalog.getBoundingClientRect();
            return document.documentElement.dataset.drawerCatalogOpen === 'true' &&
                (!toolbar || getComputedStyle(toolbar).display === 'none') &&
                rect.left >= 8 && rect.right <= innerWidth - 8 &&
                list.clientHeight > 0 && catalog.querySelectorAll('.readerCatalog_list_item').length > 1;
        })()
        """) { value, _ in done(value as? Bool == true) }
}

let readerURL = URL(string: "https://weread.qq.com/web/reader/a7a32960723fa2a6a7afb50")!
readerWebView.load(URLRequest(url: readerURL))
guard waitFor({ done in
    guard delegate.readerLoaded, !readerWebView.isLoading else { done(false); return }
    readerWebView.evaluateJavaScript("!!document.querySelector('button.readerControls_item.catalog') && document.querySelectorAll('.readerCatalog_list_item').length > 1") {
        value, _ in done(value as? Bool == true)
    }
}) else { fatalError("Live reader catalog did not load") }

guard let button = delegate.catalogButton, let hotspot = delegate.catalogHotspot, button.isEnabled else {
    fatalError("Native catalog button is unavailable on the reader page")
}
let pointerEvent = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: delegate.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
hotspot.mouseExited(with: pointerEvent)
guard button.isHidden else { fatalError("Catalog button should be hidden away from the top-right corner") }
hotspot.mouseEntered(with: pointerEvent)
guard !button.isHidden else { fatalError("Hovering the top-right corner did not reveal the catalog button") }
var pageTurns = 0
readerWebView.onScrollPage = { _ in pageTurns += 1 }
let wheel = NSEvent(cgEvent: CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -4, wheel2: 0, wheel3: 0)!)!
button.performClick(nil)
guard waitFor(catalogState, timeout: 10) else { fatalError("Native button did not reveal a usable catalog") }
guard readerWebView.isCatalogOpen else { fatalError("Page turning was not paused while the catalog is open") }
readerWebView.scrollWheel(with: wheel)
guard pageTurns == 0 else { fatalError("Scrolling an open catalog turned the reading page") }

var imageSaved = false
readerWebView.takeSnapshot(with: nil) { image, _ in
    if let image = image,
       let tiff = image.tiffRepresentation,
       let bitmap = NSBitmapImageRep(data: tiff),
       let png = bitmap.representation(using: .png, properties: [:]) {
        imageSaved = (try? png.write(to: URL(fileURLWithPath: "\(CommandLine.arguments[1])/Tests/catalog-live.png"))) != nil
    }
}
let snapshotDeadline = Date().addingTimeInterval(5)
while !imageSaved && Date() < snapshotDeadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
guard imageSaved else { fatalError("Could not capture the open catalog") }

readerWebView.evaluateJavaScript("document.querySelectorAll('.readerCatalog_list_item')[2].click()", completionHandler: nil)
guard waitFor({ done in
    readerWebView.evaluateJavaScript("getComputedStyle(document.querySelector('.readerCatalog')).display === 'none' && !document.documentElement.dataset.drawerCatalogOpen") {
        value, _ in done(value as? Bool == true)
    }
}, timeout: 5) else { fatalError("Selecting a chapter did not close the catalog") }
guard !readerWebView.isCatalogOpen else { fatalError("Page turning was not restored after selecting a chapter") }

button.performClick(nil)
guard waitFor(catalogState, timeout: 5) else { fatalError("Native button did not reopen the catalog") }
guard readerWebView.isCatalogOpen else { fatalError("Page turning was not paused after reopening the catalog") }
button.performClick(nil)
guard waitFor({ done in
    readerWebView.evaluateJavaScript("getComputedStyle(document.querySelector('.readerCatalog')).display === 'none' && !document.documentElement.dataset.drawerCatalogOpen") {
        value, _ in done(value as? Bool == true)
    }
}, timeout: 5) else { fatalError("Second native click did not close the catalog") }
guard !readerWebView.isCatalogOpen else { fatalError("Page turning was not restored after closing the catalog") }
readerWebView.scrollWheel(with: wheel)
guard pageTurns == 1 else { fatalError("Closing the catalog did not restore wheel page turning") }
hotspot.mouseExited(with: pointerEvent)
guard button.isHidden else { fatalError("Catalog button remained visible after leaving the corner") }

readerWebView.load(URLRequest(url: URL(string: "https://weread.qq.com/")!))
guard waitFor({ done in
    done(readerWebView.url?.path == "/" && button.isHidden)
}, timeout: 20) else { fatalError("Catalog button remained visible outside the reader") }

let artifact: [String: Any] = [
    "status": "PASS",
    "readerURL": readerURL.absoluteString,
    "nativeButton": button.title,
    "openedWithVisibleScrollableChapters": true,
    "selectionToolbarSuppressedWhileCatalogOpen": true,
    "catalogScrollDoesNotTurnPage": true,
    "pageTurnRestoredAfterClose": true,
    "hiddenOutsideReader": true,
    "shownOnlyWhileHoveringCorner": true,
    "closedAfterChapterSelection": true,
    "reopenedAfterChapterSelection": true,
    "closedOnSecondClick": true,
    "snapshot": "Tests/catalog-live.png"
]
let data = try! JSONSerialization.data(withJSONObject: artifact, options: [.prettyPrinted, .sortedKeys])
print("ARTIFACT_START")
print(String(data: data, encoding: .utf8)!)
print("ARTIFACT_END")
'''

with tempfile.TemporaryDirectory() as directory:
    swift = Path(directory) / "main.swift"
    binary = Path(directory) / "CatalogE2E"
    swift.write_text(source + check)
    subprocess.run(["swiftc", str(swift), "-o", str(binary), "-framework", "Cocoa", "-framework", "WebKit", "-framework", "Carbon", "-framework", "SwiftUI", "-F", str(root / ".dependencies/Sparkle"), "-framework", "Sparkle", "-Xlinker", "-rpath", "-Xlinker", str(root / ".dependencies/Sparkle")], check=True)
    result = subprocess.run([str(binary), str(root)], capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise RuntimeError(result.stdout + "\n" + result.stderr)
    artifact = json.loads(result.stdout.split("ARTIFACT_START\n")[1].split("\nARTIFACT_END")[0])
    path = root / "Tests" / "catalog_e2e_artifact.json"
    path.write_text(json.dumps(artifact, ensure_ascii=False, indent=2) + "\n")
    print(f"E2E passed: {path}")
    print(json.dumps(artifact, ensure_ascii=False, indent=2))
