import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [PanelController] = []
    private var hotKeys: [String: HotKey] = [:]
    private var panelController: PanelController { controllers[0] } // Claude
    /// The panel you're typing in, so ⌘R, ⌘W, zoom etc. act on the right window.
    private var activeController: PanelController {
        controllers.first { $0.panel.isKeyWindow } ?? panelController
    }
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controllers = Config.sites.enumerated().map { index, site in
            PanelController(site: site, cornerOffset: CGFloat(index) * 30)
        }
        buildMainMenu()
        buildStatusItem()

        var failed: [String] = []
        for controller in controllers {
            let site = controller.site
            controller.onPresentationBlocked = { [weak self] appName in
                self?.showBlockedIndicator(appName: appName, site: site)
            }
            hotKeys[site.id] = HotKey(id: site.hotKeyID, keyCode: site.hotKeyCode, modifiers: site.hotKeyModifiers) { [weak controller] in
                Task { @MainActor in
                    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
                    Log.hotKey.info("\(site.title, privacy: .public) hotkey handler running; frontmost=\(front, privacy: .public) secureInput=\(IsSecureEventInputEnabled())")
                    controller?.toggle()
                }
            }
            if hotKeys[site.id] == nil { failed.append(site.hotKeyLabel) }
        }
        if !failed.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Couldn't register \(failed.joined(separator: ", "))"
            alert.informativeText = "Another app may already be using this shortcut. You can still open the window from the menu bar icon."
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
        for controller in controllers {
            addItem(to: menu, "Open \(controller.site.title) (\(controller.site.hotKeyLabel))", #selector(PanelController.show), target: controller)
        }
        menu.addItem(.separator())
        addItem(to: menu, "New Chat", #selector(PanelController.newChat), target: panelController)
        addItem(to: menu, "Chats", #selector(PanelController.showChats), target: panelController)
        addItem(to: menu, "Reload", #selector(PanelController.reload), target: panelController)
        menu.addItem(.separator())
        addItem(to: menu, "Sign In with Link from Clipboard", #selector(PanelController.openLinkFromClipboard), target: panelController)
        if let web = controllers.first(where: { $0.site.id == Config.web.id }) {
            addItem(to: menu, "Add Google Account…", #selector(PanelController.addGoogleAccount), target: web)
            addItem(to: menu, "Change Default Google Account…", #selector(PanelController.changeDefaultGoogleAccount), target: web)
        }
        addItem(to: menu, "Copy Diagnostics", #selector(copyDiagnostics), target: self)
        launchAtLoginItem = addItem(to: menu, "Launch at Login", #selector(toggleLaunchAtLogin), target: self)
        menu.addItem(.separator())
        addItem(to: menu, "Quit Claude Mini", #selector(NSApplication.terminate(_:)), target: NSApp)
        statusItem.menu = menu
        updateLaunchAtLoginItem()
    }

    /// Fallback when macOS or the frontmost app keeps the panel off screen: say so in the menu
    /// bar instead of failing silently. Nothing tries to force the window over that app.
    private func showBlockedIndicator(appName: String, site: Site) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "\(site.title) couldn't open")
        button.toolTip = "\(appName) isn't allowing other windows on top right now. Switch to another app or window, then press \(site.hotKeyLabel)."
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
        Shortcuts: \(controllers.map { "\($0.site.hotKeyLabel) registered=\(hotKeys[$0.site.id] != nil)" }.joined(separator: ", ")) (Carbon RegisterEventHotKey, needs no Accessibility/Input Monitoring permission)
        Secure keyboard entry active: \(IsSecureEventInputEnabled())
        Frontmost app: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")
        Claude Mini active: \(NSApp.isActive)
        \(controllers.map { $0.diagnostics() }.joined(separator: "\n"))
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
        addItem(to: chatMenu, "New Chat / Home", #selector(newChat), key: "n", target: self)
        addItem(to: chatMenu, "Chats", #selector(showChats), key: "e", target: self)
        addItem(to: chatMenu, "Open Location", #selector(focusAddressBar), key: "l", target: self)
        addItem(to: chatMenu, "Back", #selector(goBack), key: "[", target: self)
        addItem(to: chatMenu, "Forward", #selector(goForward), key: "]", target: self)
        addItem(to: chatMenu, "Reload", #selector(reload), key: "r", target: self)
        addItem(to: chatMenu, "New Tab", #selector(newTab), key: "t", target: self)
        addItem(to: chatMenu, "Close Tab / Hide", #selector(closeTabOrHide), key: "w", target: self)
        addItem(to: chatMenu, "Next Tab", #selector(nextTab), key: "\t", target: self).keyEquivalentModifierMask = [.control]
        addItem(to: chatMenu, "Previous Tab", #selector(previousTab), key: "\t", target: self).keyEquivalentModifierMask = [.control, .shift]
        addItem(to: chatMenu, "Next Tab", #selector(nextTab), key: "}", target: self)
        addItem(to: chatMenu, "Previous Tab", #selector(previousTab), key: "{", target: self)
        chatMenu.addItem(.separator())
        addItem(to: chatMenu, "Zoom In", #selector(zoomIn), key: "=", target: self)
        addItem(to: chatMenu, "Zoom Out", #selector(zoomOut), key: "-", target: self)
        addItem(to: chatMenu, "Actual Size", #selector(resetZoom), key: "0", target: self)

        NSApp.mainMenu = mainMenu
    }

    @objc private func newChat() { activeController.newChat() }
    @objc private func showChats() { activeController.showChats() }
    @objc private func focusAddressBar() { activeController.focusAddressBar() }
    @objc private func goBack() { activeController.goBack() }
    @objc private func goForward() { activeController.goForward() }
    @objc private func reload() { activeController.reload() }
    @objc private func newTab() { activeController.newTab() }
    @objc private func closeTabOrHide() { activeController.closeTabOrHide() }
    @objc private func nextTab() { activeController.nextTab() }
    @objc private func previousTab() { activeController.previousTab() }
    @objc private func zoomIn() { activeController.zoomIn() }
    @objc private func zoomOut() { activeController.zoomOut() }
    @objc private func resetZoom() { activeController.resetZoom() }

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
