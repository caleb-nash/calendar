import AppKit
import WebKit

/// Owns one floating panel and its web view (Claude, Web or Roblox). The page is loaded at
/// launch and kept alive while hidden, so summoning the panel is instant.
@MainActor
final class PanelController: NSObject {
    let site: Site
    let panel: FloatingPanel
    let webView: WKWebView
    private let addressField: NSTextField
    private var popupWindows: [NSWindow] = []
    /// The app that was frontmost when the panel opened, so focus can go back to it.
    private var previousApp: NSRunningApplication?
    /// Called when the panel was ordered front but macOS didn't actually put it on screen.
    var onPresentationBlocked: ((String) -> Void)?
    // Claude keeps the original keys so its saved position and zoom survive the update.
    private var frameName: String { site.isClaude ? "ClaudeMiniPanel" : "ClaudeMiniPanel-\(site.id)" }
    private var zoomKey: String { site.isClaude ? "pageZoom" : "pageZoom-\(site.id)" }

    init(site: Site, cornerOffset: CGFloat = 0) {
        self.site = site
        addressField = NSTextField()
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: site.defaultSize))

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // keeps you signed in between launches
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        webView.customUserAgent = Config.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground") // avoid a white flash in dark mode
        if let zoom = UserDefaults.standard.object(forKey: zoomKey) as? Double {
            webView.pageZoom = CGFloat(zoom)
        }

        panel.onEscape = { [weak self] in self?.hide() }
        buildLayout()

        let restored = panel.setFrameUsingName(frameName)
        panel.setFrameAutosaveName(frameName)
        if !restored, let screen = NSScreen.main {
            placeInCorner(of: screen, offset: cornerOffset)
        }

        webView.load(URLRequest(url: site.homeURL))
    }

    // MARK: - Showing and hiding

    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    @objc func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = frontmost
        }
        moveToScreenWithMouse()
        // orderFrontRegardless + makeKey shows the panel without activating this app,
        // so the app underneath stays active and keeps its full-screen state.
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(webView)
        logState("\(site.title) show requested over \(frontmost?.bundleIdentifier ?? "unknown")")
        if site.isClaude {
            focusComposer()
        } else if site.hasAddressBar, webView.url == nil || webView.url == site.homeURL {
            focusAddressBar()
        }
        Task { await confirmOnScreen(retried: false) }
    }

    @objc func hide() {
        panel.orderOut(nil)
        Log.window.info("\(self.site.title, privacy: .public) panel hidden")
        // Normally this app never became active, so the other app kept focus the whole time.
        // If it did activate (file picker, presentation retry), hand focus back explicitly.
        if NSApp.isActive, let previousApp, !previousApp.isTerminated {
            Log.window.info("Returning focus to \(previousApp.bundleIdentifier ?? "unknown", privacy: .public)")
            previousApp.activate(options: [])
        }
    }

    /// `orderFrontRegardless` only *requests* that the panel appear. Check that it really is on
    /// the current Space and not covered, retry once with normal activation, then give up
    /// visibly instead of leaving an invisible key window that swallows typing.
    private func confirmOnScreen(retried: Bool) async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard panel.isVisible else { return } // dismissed in the meantime
        if panel.isOnActiveSpace && panel.occlusionState.contains(.visible) {
            logState("Confirmed on screen")
            return
        }
        logState("Not on screen")
        if !retried {
            Log.window.notice("Retrying presentation with app activation")
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            await confirmOnScreen(retried: true)
        } else {
            let appName = previousApp?.localizedName ?? "this app"
            Log.window.error("Presentation blocked over \(appName, privacy: .public)")
            hide()
            onPresentationBlocked?(appName)
        }
    }

    func diagnostics() -> String {
        """
        \(site.title) panel: visible=\(panel.isVisible) key=\(panel.isKeyWindow) onActiveSpace=\(panel.isOnActiveSpace) \
        occlusionVisible=\(panel.occlusionState.contains(.visible)) level=\(panel.level.rawValue) \
        collectionBehavior=\(panel.collectionBehavior.rawValue) frame=\(NSStringFromRect(panel.frame))
        Previous app: \(previousApp?.bundleIdentifier ?? "none")
        """
    }

    private func logState(_ label: String) {
        Log.window.info("\(label, privacy: .public): visible=\(self.panel.isVisible) key=\(self.panel.isKeyWindow) onActiveSpace=\(self.panel.isOnActiveSpace) occlusionVisible=\(self.panel.occlusionState.contains(.visible)) level=\(self.panel.level.rawValue) appActive=\(NSApp.isActive)")
    }

    // MARK: - Actions (header buttons and menu items)

    /// ⌘N: a new chat in Claude, the start page elsewhere.
    @objc func newChat() {
        load(site.isClaude ? Config.newChatURL : site.homeURL)
    }

    @objc func showChats() {
        guard site.isClaude else { return }
        load(Config.recentsURL)
    }

    @objc func goHome() {
        load(site.homeURL)
    }

    @objc func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    @objc func goForward() {
        if webView.canGoForward { webView.goForward() }
    }

    /// ⌘L in the Web panel, like a browser.
    @objc func focusAddressBar() {
        guard site.hasAddressBar else { return }
        panel.makeFirstResponder(addressField)
        addressField.currentEditor()?.selectAll(nil)
    }

    @objc private func addressEntered() {
        guard let url = Config.url(fromAddressBar: addressField.stringValue) else { return }
        webView.load(URLRequest(url: url))
        panel.makeFirstResponder(webView)
    }

    /// Hands the current page to Google Chrome (or the default browser if Chrome isn't installed).
    @objc func openInChrome() {
        guard let url = webView.url else { return }
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func reload() {
        webView.reload()
    }

    @objc func zoomIn() { setZoom(webView.pageZoom + 0.1) }
    @objc func zoomOut() { setZoom(webView.pageZoom - 0.1) }
    @objc func resetZoom() { setZoom(1.0) }

    /// For email sign-in: copy the login link from the email, then use this so the session
    /// is created inside the panel rather than in your browser.
    @objc func openLinkFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), url.scheme == "https", Config.isInternal(url) else {
            let alert = NSAlert()
            alert.messageText = "No claude.ai link on the clipboard"
            alert.informativeText = "Copy the sign-in link from your email (right-click → Copy Link), then try again."
            alert.runModal()
            return
        }
        load(url)
        show()
    }

    private func load(_ url: URL) {
        webView.load(URLRequest(url: url))
        show()
    }

    private func setZoom(_ zoom: CGFloat) {
        let clamped = min(max(zoom, 0.6), 1.6)
        webView.pageZoom = clamped
        UserDefaults.standard.set(Double(clamped), forKey: zoomKey)
    }

    /// Puts the cursor in claude.ai's message box so you can type immediately. Retries briefly
    /// because the box may not exist yet while the page is still loading; without focus,
    /// keystrokes hit the page body and WebKit beeps.
    private func focusComposer() {
        let script = """
        (() => {
          const el = document.querySelector('div.ProseMirror[contenteditable="true"]')
                  || document.querySelector('[contenteditable="true"]')
                  || document.querySelector('textarea');
          if (el) { el.focus(); return true; }
          return false;
        })();
        """
        Task {
            for _ in 0..<10 {
                if (try? await webView.evaluateJavaScript(script)) as? Bool == true { return }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            Log.window.notice("Message box not found; is the page signed in and loaded?")
        }
    }

    // MARK: - Layout

    private func buildLayout() {
        let container = NSView()
        let header = DragHeaderView()
        header.material = .titlebar
        header.blendingMode = .withinWindow

        let title: NSView
        if site.hasAddressBar {
            addressField.placeholderString = "Search or enter website"
            addressField.font = .systemFont(ofSize: 12)
            addressField.bezelStyle = .roundedBezel
            addressField.lineBreakMode = .byTruncatingTail
            addressField.target = self
            addressField.action = #selector(addressEntered)
            title = addressField
        } else {
            let label = NSTextField(labelWithString: site.title)
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .secondaryLabelColor
            title = label
        }

        var leftButtons = [headerButton("chevron.left", tip: "Back", action: #selector(goBack))]
        var rightButtons: [NSButton] = []
        if site.isClaude {
            leftButtons.append(headerButton("sidebar.left", tip: "Chats", action: #selector(showChats)))
            rightButtons.append(headerButton("square.and.pencil", tip: "New chat (⌘N)", action: #selector(newChat)))
        } else {
            leftButtons.append(headerButton("chevron.right", tip: "Forward", action: #selector(goForward)))
            leftButtons.append(headerButton("house", tip: "Home", action: #selector(goHome)))
            if site.hasAddressBar {
                rightButtons.append(headerButton("arrow.up.forward.app", tip: "Open in Chrome", action: #selector(openInChrome)))
            }
        }
        rightButtons.append(headerButton("xmark", tip: "Hide (Esc or \(site.hotKeyLabel))", action: #selector(hide)))
        let left = NSStackView(views: leftButtons)
        let right = NSStackView(views: rightButtons)
        left.spacing = 2
        right.spacing = 2

        for view in [header, webView, title, left, right] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        container.addSubview(webView)
        container.addSubview(header)
        header.addSubview(left)
        header.addSubview(title)
        header.addSubview(right)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 34),

            left.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            left.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            right.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -8),
            right.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(greaterThanOrEqualTo: left.trailingAnchor, constant: 8),
            title.trailingAnchor.constraint(lessThanOrEqualTo: right.leadingAnchor, constant: -8),

            webView.topAnchor.constraint(equalTo: header.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        if site.hasAddressBar {
            // Fill the space between the button groups.
            let fill = addressField.widthAnchor.constraint(equalToConstant: 2000)
            fill.priority = .defaultLow
            fill.isActive = true
        }

        panel.contentView = container
    }

    private func headerButton(_ symbol: String, tip: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.toolTip = tip
        button.contentTintColor = .secondaryLabelColor
        button.widthAnchor.constraint(equalToConstant: 26).isActive = true
        return button
    }

    // MARK: - Positioning

    private func moveToScreenWithMouse() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) else { return }
        if !screen.visibleFrame.intersects(panel.frame) {
            placeInCorner(of: screen)
        }
    }

    private func placeInCorner(of screen: NSScreen, offset: CGFloat = 0) {
        let visible = screen.visibleFrame
        var frame = panel.frame
        frame.size.height = min(frame.height, visible.height - 40)
        frame.origin = NSPoint(x: visible.maxX - frame.width - 20 - offset, y: visible.maxY - frame.height - 20 - offset)
        panel.setFrame(frame, display: false)
    }
}

// MARK: - WKNavigationDelegate

extension PanelController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { return .allow }
        // App links such as Roblox's Play button (roblox-player:) launch the installed app.
        if !["http", "https", "about", "blob", "data", "file"].contains(scheme) {
            Log.window.info("Opening app link with scheme \(scheme, privacy: .public)")
            NSWorkspace.shared.open(url)
            return .cancel
        }
        // Outside links open in your normal browser.
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame == true,
           !site.isInternal(url), !Config.isAuth(url) {
            NSWorkspace.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if webView === self.webView, site.hasAddressBar, panel.firstResponder !== addressField.currentEditor() {
            addressField.stringValue = webView.url?.absoluteString ?? ""
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === self.webView, site.isClaude, panel.isKeyWindow {
            focusComposer()
        }
    }
}

// MARK: - WKUIDelegate

extension PanelController: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, url.scheme?.hasPrefix("http") == true {
            // The Web panel keeps new-tab links in the panel itself.
            if site.internalHosts == nil {
                webView.load(URLRequest(url: url))
                return nil
            }
            if !site.isInternal(url), !Config.isAuth(url) {
                NSWorkspace.shared.open(url)
                return nil
            }
        }
        return openPopup(configuration: configuration)
    }

    func webViewDidClose(_ webView: WKWebView) {
        popupWindows.first { $0.contentView === webView }?.close()
    }

    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = parameters.allowsMultipleSelection
        openPanel.canChooseDirectories = parameters.allowsDirectories
        openPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        NSApp.activate(ignoringOtherApps: true)
        return openPanel.runModal() == .OK ? openPanel.urls : nil
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Sign-in popups (e.g. "Continue with Google") need a real window that shares the
    /// panel's cookies and can talk back to it.
    private func openPopup(configuration: WKWebViewConfiguration) -> WKWebView {
        let popupView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: configuration)
        popupView.customUserAgent = Config.userAgent
        popupView.uiDelegate = self
        popupView.navigationDelegate = self

        let window = NSPanel(contentRect: popupView.frame,
                             styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                             backing: .buffered,
                             defer: false)
        window.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = popupView
        window.center()
        window.orderFrontRegardless()
        window.makeKey()
        popupWindows.append(window)
        return popupView
    }
}

// MARK: - NSWindowDelegate (popups)

extension PanelController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        popupWindows.removeAll { $0 === window }
    }
}
