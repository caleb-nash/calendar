import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panelController: PanelController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = PanelController()
        buildMainMenu()
        buildStatusItem()

        panelController.onPresentationBlocked = { [weak self] appName in
            self?.showBlockedIndicator(appName: appName)
        }

        hotKey = HotKey(keyCode: Config.hotKeyCode, modifiers: Config.hotKeyModifiers) { [weak self] in
            Task { @MainActor in
                let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
                Log.hotKey.info("Hotkey handler running; frontmost=\(front, privacy: .public) secureInput=\(IsSecureEventInputEnabled())")
                self?.panelController.toggle()
            }
        }
        if hotKey == nil {
            let alert = NSAlert()
            alert.messageText = "Couldn't register \(Config.hotKeyLabel)"
            alert.informativeText = "Another app may already be using this shortcut. You can still open Claude Mini from the menu bar icon."
            alert.runModal()
        }

        // On first launch, show the panel so you can sign in.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "didLaunchBefore") {
            defaults.set(true, forKey: "didLaunchBefore")
            panelController.show()
        }
    }

    // MARK: - Menu bar icon

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Claude Mini")

        let menu = NSMenu()
        addItem(to: menu, "Open Claude Mini (\(Config.hotKeyLabel))", #selector(PanelController.show), target: panelController)
        addItem(to: menu, "New Chat", #selector(PanelController.newChat), target: panelController)
        addItem(to: menu, "Chats", #selector(PanelController.showChats), target: panelController)
        addItem(to: menu, "Reload", #selector(PanelController.reload), target: panelController)
        menu.addItem(.separator())
        addItem(to: menu, "Sign In with Link from Clipboard", #selector(PanelController.openLinkFromClipboard), target: panelController)
        addItem(to: menu, "Copy Diagnostics", #selector(copyDiagnostics), target: self)
        launchAtLoginItem = addItem(to: menu, "Launch at Login", #selector(toggleLaunchAtLogin), target: self)
        menu.addItem(.separator())
        addItem(to: menu, "Quit Claude Mini", #selector(NSApplication.terminate(_:)), target: NSApp)
        statusItem.menu = menu
        updateLaunchAtLoginItem()
    }

    /// Fallback when macOS or the frontmost app keeps the panel off screen: say so in the menu
    /// bar instead of failing silently. Nothing tries to force the window over that app.
    private func showBlockedIndicator(appName: String) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Claude Mini couldn't open")
        button.toolTip = "\(appName) isn't allowing other windows on top right now. Switch to another app or window, then press \(Config.hotKeyLabel)."
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            button.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: "Claude Mini")
            button.toolTip = nil
        }
    }

    @objc private func copyDiagnostics() {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let report = """
        Claude Mini diagnostics
        macOS: \(osVersion)
        Shortcut: \(Config.hotKeyLabel) registered=\(hotKey != nil) (Carbon RegisterEventHotKey, needs no Accessibility/Input Monitoring permission)
        Secure keyboard entry active: \(IsSecureEventInputEnabled())
        Frontmost app: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")
        \(panelController.diagnostics())
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        Log.hotKey.info("Diagnostics copied")
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        updateLaunchAtLoginItem()
    }

    private func updateLaunchAtLoginItem() {
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    // MARK: - Main menu
    // Never visible (no Dock icon / menu bar of our own), but it's what makes
    // ⌘C, ⌘V, ⌘A, ⌘Z etc. work inside the web view.

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = submenu(in: mainMenu, "Claude Mini")
        addItem(to: appMenu, "Quit Claude Mini", #selector(NSApplication.terminate(_:)), key: "q")

        let editMenu = submenu(in: mainMenu, "Edit")
        addItem(to: editMenu, "Undo", Selector(("undo:")), key: "z")
        addItem(to: editMenu, "Redo", Selector(("redo:")), key: "z").keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        addItem(to: editMenu, "Cut", #selector(NSText.cut(_:)), key: "x")
        addItem(to: editMenu, "Copy", #selector(NSText.copy(_:)), key: "c")
        addItem(to: editMenu, "Paste", #selector(NSText.paste(_:)), key: "v")
        addItem(to: editMenu, "Select All", #selector(NSText.selectAll(_:)), key: "a")

        let chatMenu = submenu(in: mainMenu, "Chat")
        addItem(to: chatMenu, "New Chat", #selector(PanelController.newChat), key: "n", target: panelController)
        addItem(to: chatMenu, "Chats", #selector(PanelController.showChats), key: "e", target: panelController)
        addItem(to: chatMenu, "Reload", #selector(PanelController.reload), key: "r", target: panelController)
        addItem(to: chatMenu, "Hide", #selector(PanelController.hide), key: "w", target: panelController)
        chatMenu.addItem(.separator())
        addItem(to: chatMenu, "Zoom In", #selector(PanelController.zoomIn), key: "=", target: panelController)
        addItem(to: chatMenu, "Zoom Out", #selector(PanelController.zoomOut), key: "-", target: panelController)
        addItem(to: chatMenu, "Actual Size", #selector(PanelController.resetZoom), key: "0", target: panelController)

        NSApp.mainMenu = mainMenu
    }

    private func submenu(in menu: NSMenu, _ title: String) -> NSMenu {
        let item = NSMenuItem()
        let sub = NSMenu(title: title)
        item.submenu = sub
        menu.addItem(item)
        return sub
    }

    @discardableResult
    private func addItem(to menu: NSMenu, _ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
