#!/usr/bin/env python3
"""Exercise actual AppKit frames and saved settings in an isolated executable."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/main.swift').read_text().split('let app = NSApplication.shared')[0]
check = r'''
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
class HeightDelegate: AppDelegate {
    override func applyCurrentTheme() {}
}
let delegate = HeightDelegate()
delegate.setupStatusItem()
delegate.setupPanel()
func settle() {
    let deadline = Date().addingTimeInterval(0.4)
    while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    assert(!delegate.isAnimating)
}
delegate.maxHeightRatio = 0.55
for screen in NSScreen.screens {
    for tag in 0..<4 {
        let point = NSPoint(x: tag % 2 == 0 ? screen.visibleFrame.minX + 20 : screen.visibleFrame.maxX - 20,
                            y: tag < 2 ? screen.visibleFrame.maxY - 20 : screen.visibleFrame.minY + 20)
        delegate.snapDrawer(at: point)
        assert(delegate.isLeft == (tag % 2 == 0))
        assert(delegate.verticalAlignment == (tag < 2 ? .top : .bottom))
        let expected = delegate.targetFrame(for: screen)
        assert(screen.visibleFrame.contains(expected))
        delegate.showDrawer(on: screen)
        settle()
        assert(abs(delegate.panel.frame.minX - expected.minX) < 1 && abs(delegate.panel.frame.minY - expected.minY) < 1 && abs(delegate.panel.frame.height - expected.height) < 1)
        assert(abs(delegate.resizeHandle.frame.minX - (delegate.isLeft ? expected.width - 6 : 0)) < 1)
        delegate.hideDrawer()
        settle()
        assert(!delegate.panel.isVisible)
        let handle = delegate.handles.first { $0.screen == screen }!
        assert(handle.panel.isVisible)
        assert(screen.visibleFrame.contains(handle.panel.frame))
        assert(delegate.isLeft ? handle.panel.frame.minX == expected.minX : handle.panel.frame.maxX == expected.maxX)
        let restored = HeightDelegate()
        restored.loadSavedSettings()
        assert(restored.isLeft == delegate.isLeft && restored.verticalAlignment == delegate.verticalAlignment)
        delegate.showDrawer(on: screen)
        settle()
        assert(abs(delegate.panel.frame.minX - expected.minX) < 1 && abs(delegate.panel.frame.minY - expected.minY) < 1 && abs(delegate.panel.frame.height - expected.height) < 1)
        delegate.hideDrawer()
        settle()
    }
}
// Dragging the top grip must use the window center, not the pointer above it.
for screen in NSScreen.screens {
    let visible = screen.visibleFrame
    for left in [true, false] {
        let frame = NSRect(x: left ? visible.minX : visible.maxX - 380,
                           y: visible.minY, width: 380, height: visible.height * 0.7)
        let pointer = NSPoint(x: frame.midX, y: frame.maxY - 12)
        assert(pointer.y > visible.midY)
        delegate.snapDrawer(at: pointer, windowFrame: frame)
        assert(delegate.verticalAlignment == .bottom && delegate.isLeft == left)
        let topFrame = NSRect(x: frame.minX, y: visible.maxY - frame.height,
                              width: frame.width, height: frame.height)
        delegate.snapDrawer(at: NSPoint(x: topFrame.midX, y: topFrame.maxY - 12), windowFrame: topFrame)
        assert(delegate.verticalAlignment == .top && delegate.isLeft == left)
        delegate.verticalAlignment = .bottom
        delegate.snapDrawer(at: pointer, windowFrame: visible)
        assert(delegate.verticalAlignment == .bottom)
    }
}
for tag in 0..<4 {
    let item = NSMenuItem()
    item.tag = tag
    delegate.setCorner(item)
    assert(delegate.isLeft == (tag % 2 == 0))
    assert(delegate.verticalAlignment == (tag < 2 ? .top : .bottom))
}
print("PASS: four corners, menus, resize edge, hide/reopen, handles and saved settings on all displays")
'''
with tempfile.TemporaryDirectory() as directory:
    swift = Path(directory) / 'main.swift'
    binary = Path(directory) / ('HeightCheck-' + Path(directory).name)
    swift.write_text(source + check)
    subprocess.run(['swiftc', str(swift), '-o', str(binary), '-framework', 'Cocoa', '-framework', 'WebKit', '-framework', 'Carbon', '-framework', 'SwiftUI'], check=True)
    subprocess.run([str(binary)], check=True)
