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
for screen in NSScreen.screens {
    for alignment in [VerticalAlignment.top, .bottom] {
        delegate.verticalAlignment = alignment
        for percent in [100, 85, 70, 55] {
            let item = NSMenuItem()
            item.tag = percent
            delegate.setMaxHeightPreset(item)
            delegate.showDrawer(on: screen)
            settle()
            let expected = delegate.targetFrame(for: screen)
            delegate.hideDrawer()
            settle()
            delegate.showDrawer(on: screen)
            settle()
            assert(abs(delegate.panel.frame.height - expected.height) < 1)
            assert(abs(delegate.panel.frame.minY - expected.minY) < 1)
            delegate.hideDrawer()
            settle()
        }
        delegate.showDrawer(on: screen)
        settle()
        var resized = delegate.panel.frame
        resized.size.height = 430
        // Start with the opposite saved setting to reproduce snapping to the old edge.
        delegate.verticalAlignment = alignment == .top ? .bottom : .top
        resized.origin.y = alignment == .top ? screen.visibleFrame.maxY - 430 : screen.visibleFrame.minY
        delegate.panel.setFrame(resized, display: true)
        NotificationCenter.default.post(name: NSWindow.didEndLiveResizeNotification, object: delegate.panel)
        assert(delegate.verticalAlignment == alignment)
        assert(abs(delegate.panel.frame.minY - resized.minY) < 1)
        assert(abs(delegate.maxHeightRatio - 430 / screen.visibleFrame.height) < 0.001)
        delegate.hideDrawer()
        settle()
        delegate.showDrawer(on: screen)
        settle()
        assert(abs(delegate.panel.frame.height - 430) < 1)
        assert(abs(delegate.panel.frame.minY - resized.minY) < 1)
        let restored = HeightDelegate()
        restored.loadSavedSettings()
        assert(abs(restored.maxHeightRatio - delegate.maxHeightRatio) < 0.001)
        assert(restored.verticalAlignment == alignment)
        // Moving the resized window to the opposite edge must survive hide/reopen too.
        resized.origin.y = alignment == .top ? screen.visibleFrame.minY : screen.visibleFrame.maxY - 430
        delegate.panel.setFrame(resized, display: true)
        delegate.hideDrawer()
        settle()
        delegate.showDrawer(on: screen)
        settle()
        assert(abs(delegate.panel.frame.minY - resized.minY) < 1)
        delegate.hideDrawer()
        settle()
    }
}
print("PASS: presets, native resize notification, hide/reopen, saved-height reload on all displays")
'''
with tempfile.TemporaryDirectory() as directory:
    swift = Path(directory) / 'main.swift'
    binary = Path(directory) / ('HeightCheck-' + Path(directory).name)
    swift.write_text(source + check)
    subprocess.run(['swiftc', str(swift), '-o', str(binary), '-framework', 'Cocoa', '-framework', 'WebKit', '-framework', 'Carbon', '-framework', 'SwiftUI'], check=True)
    subprocess.run([str(binary)], check=True)
