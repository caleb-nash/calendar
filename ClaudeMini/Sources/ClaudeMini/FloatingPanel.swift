import AppKit

/// A Spotlight-style panel: floats above everything (including full-screen apps),
/// takes keyboard focus without activating the app, and never shows in the Dock.
final class FloatingPanel: NSPanel {
    var onEscape: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        // fullScreenAuxiliary lets the panel appear inside another app's full-screen space
        // instead of macOS switching to the desktop.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        minSize = Config.minSize
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // Intercept Escape before the web view sees it.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            onEscape?()
            return
        }
        super.sendEvent(event)
    }
}

/// Header strip that can be dragged to move the panel.
final class DragHeaderView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { true }
}
