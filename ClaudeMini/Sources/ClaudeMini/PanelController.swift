import AppKit
import WebKit

/// Owns one floating panel and its web view (Claude, Web or Roblox). The page is loaded at
/// launch and kept alive while hidden, so summoning the panel is instant.
@MainActor
final class PanelController: NSObject {
    let site: Site
    let panel: FloatingPanel
    /// Open tabs. Only the Web panel shows a tab strip; the others always have exactly one.
    private var tabs: [WKWebView] = []
    private var currentTab = 0
    var webView: WKWebView { tabs[currentTab] }
    private let configuration: WKWebViewConfiguration
    private let webContainer: NSView
    private let tabStrip: NSStackView
    private var tabObservations: [ObjectIdentifier: [NSKeyValueObservation]] = [:]
    private var faviconCache: [String: NSImage] = [:]
    private var faviconRequests: Set<String> = []
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
        webContainer = NSView()
        tabStrip = NSStackView()
        panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: site.defaultSize))

        configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // keeps you signed in between launches
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        super.init()

        tabs = [makeWebView(configuration: configuration)]
        panel.onEscape = { [weak self] in self?.hide() }
        buildLayout()
        installCurrentTab()

        let restored = panel.setFrameUsingName(frameName)
        panel.setFrameAutosaveName(frameName)
        if !restored, let screen = NSScreen.main {
            placeInCorner(of: screen, offset: cornerOffset)
        }

        webView.load(URLRequest(url: site.homeURL))
    }

    // MARK: - Showing and hiding

    func toggle() {
        // Roblox games only run in the Roblox app, so while a game is open ⌥N shows/hides that
        // app; the roblox.com panel is for picking a game when it isn't running.
        if site.id == Config.roblox.id, let player = Self.runningRobloxPlayer() {
            if player.isActive {
                Log.window.info("Hiding Roblox player")
                player.hide()
            } else {
                Log.window.info("Bringing Roblox player to front")
                hide()
                player.unhide()
                player.activate(options: [])
            }
            return
        }
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    private static func runningRobloxPlayer() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == Config.robloxPlayerBundleID || $0.localizedName == "Roblox"
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
        \(site.title) panel (\(tabs.count) tab(s)): visible=\(panel.isVisible) key=\(panel.isKeyWindow) onActiveSpace=\(panel.isOnActiveSpace) \
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
        for tab in tabs {
            tab.pageZoom = clamped
        }
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

    // MARK: - Tabs

    private func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = Config.userAgent
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.setValue(false, forKey: "drawsBackground") // avoid a white flash in dark mode
        if let zoom = UserDefaults.standard.object(forKey: zoomKey) as? Double {
            view.pageZoom = CGFloat(zoom)
        }
        if site.hasTabs {
            // Keep tab titles, icons and the address bar in sync, including in single-page apps.
            tabObservations[ObjectIdentifier(view)] = [
                view.observe(\.title) { [weak self] _, _ in Task { @MainActor in self?.tabsChanged() } },
                view.observe(\.url) { [weak self] _, _ in Task { @MainActor in self?.tabsChanged() } },
            ]
        }
        return view
    }

    /// ⌘T. Outside the Web panel it behaves like ⌘N.
    @objc func newTab() {
        guard site.hasTabs else { return newChat() }
        addTab(loading: site.homeURL)
        show()
        focusAddressBar()
    }

    /// ⌘W: closes the current tab in the Web panel, hides the other panels.
    @objc func closeTabOrHide() {
        guard site.hasTabs else { return hide() }
        closeTab(at: currentTab)
    }

    @objc func nextTab() {
        guard tabs.count > 1 else { return }
        selectTab((currentTab + 1) % tabs.count)
    }

    @objc func previousTab() {
        guard tabs.count > 1 else { return }
        selectTab((currentTab - 1 + tabs.count) % tabs.count)
    }

    /// Opens a tab right after the current one, like Chrome. Pass `configuration` when WebKit
    /// asks for a new window so the page keeps its link to the opener.
    @discardableResult
    private func addTab(loading url: URL?, configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        let view = makeWebView(configuration: configuration ?? self.configuration)
        tabs.insert(view, at: currentTab + 1)
        selectTab(currentTab + 1)
        if let url { view.load(URLRequest(url: url)) }
        return view
    }

    private func closeTab(at index: Int) {
        let view = tabs.remove(at: index)
        tabObservations[ObjectIdentifier(view)] = nil
        view.removeFromSuperview()
        if tabs.isEmpty {
            // Closing the last tab hides the panel and leaves a fresh start page for next time.
            tabs = [makeWebView(configuration: configuration)]
            webView.load(URLRequest(url: site.homeURL))
            currentTab = 0
            installCurrentTab()
            hide()
            return
        }
        if index < currentTab || currentTab >= tabs.count {
            currentTab -= 1
        }
        installCurrentTab()
    }

    private func selectTab(_ index: Int) {
        currentTab = index
        installCurrentTab()
    }

    /// Puts the current tab's web view on screen and refreshes the tab strip and address bar.
    private func installCurrentTab() {
        for view in webContainer.subviews where view !== webView {
            view.removeFromSuperview()
        }
        if webView.superview !== webContainer {
            webView.translatesAutoresizingMaskIntoConstraints = false
            webContainer.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: webContainer.topAnchor),
                webView.leadingAnchor.constraint(equalTo: webContainer.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: webContainer.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: webContainer.bottomAnchor),
            ])
        }
        tabsChanged()
        if panel.isKeyWindow {
            panel.makeFirstResponder(webView)
        }
    }

    private func tabsChanged() {
        guard site.hasTabs else { return }
        if panel.firstResponder !== addressField.currentEditor() {
            addressField.stringValue = webView.url?.absoluteString ?? ""
        }
        rebuildTabStrip()
    }

    private func rebuildTabStrip() {
        for view in tabStrip.arrangedSubviews {
            view.removeFromSuperview()
        }
        for (index, tab) in tabs.enumerated() {
            tabStrip.addArrangedSubview(makeTabView(for: tab, index: index, selected: index == currentTab))
        }
        tabStrip.addArrangedSubview(headerButton("plus", tip: "New tab (⌘T)", action: #selector(newTab)))
    }

    private func makeTabView(for tab: WKWebView, index: Int, selected: Bool) -> NSView {
        let globe = NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
        let icon = NSImageView(image: favicon(for: tab.url) ?? globe)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.contentTintColor = .secondaryLabelColor

        let tabTitle = (tab.title?.isEmpty == false ? tab.title : nil) ?? tab.url?.host ?? "New Tab"
        let titleButton = NSButton(title: tabTitle, target: self, action: #selector(tabClicked(_:)))
        titleButton.tag = index
        titleButton.isBordered = false
        titleButton.font = .systemFont(ofSize: 11, weight: selected ? .medium : .regular)
        titleButton.contentTintColor = selected ? .labelColor : .secondaryLabelColor
        titleButton.alignment = .left
        titleButton.lineBreakMode = .byTruncatingTail
        titleButton.toolTip = tabTitle
        titleButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let closeImage = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close tab") ?? NSImage()
        let closeButton = NSButton(image: closeImage, target: self, action: #selector(closeTabClicked(_:)))
        closeButton.tag = index
        closeButton.isBordered = false
        closeButton.toolTip = "Close tab (⌘W)"
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)

        let tabView = NSStackView(views: [icon, titleButton, closeButton])
        tabView.spacing = 5
        tabView.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 6)
        tabView.wantsLayer = true
        tabView.layer?.cornerRadius = 7
        if selected {
            panel.effectiveAppearance.performAsCurrentDrawingAppearance {
                tabView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
            }
        }
        tabView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            tabView.heightAnchor.constraint(equalToConstant: 26),
            tabView.widthAnchor.constraint(lessThanOrEqualToConstant: 180),
            tabView.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        // Tabs prefer 180pt and shrink evenly when there are many.
        let preferred = tabView.widthAnchor.constraint(equalToConstant: 180)
        preferred.priority = .defaultLow
        preferred.isActive = true
        return tabView
    }

    @objc private func tabClicked(_ sender: NSButton) {
        guard tabs.indices.contains(sender.tag) else { return }
        selectTab(sender.tag)
    }

    @objc private func closeTabClicked(_ sender: NSButton) {
        guard tabs.indices.contains(sender.tag) else { return }
        closeTab(at: sender.tag)
    }

    /// Site icons for tabs, fetched once per host.
    private func favicon(for url: URL?) -> NSImage? {
        guard let host = url?.host else { return nil }
        if let cached = faviconCache[host] { return cached }
        if !faviconRequests.contains(host),
           let iconURL = URL(string: "https://www.google.com/s2/favicons?sz=32&domain=\(host)") {
            faviconRequests.insert(host)
            Task {
                if let result = try? await URLSession.shared.data(from: iconURL), let image = NSImage(data: result.0) {
                    faviconCache[host] = image
                    rebuildTabStrip()
                }
            }
        }
        return nil
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

        for view in [header, webContainer, title, left, right] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        container.addSubview(webContainer)
        container.addSubview(header)

        // Chrome-style tab row above the address bar (Web panel only).
        var headerTop = container.topAnchor
        if site.hasTabs {
            let tabRow = DragHeaderView()
            tabRow.material = .titlebar
            tabRow.blendingMode = .withinWindow
            tabStrip.spacing = 2
            tabStrip.distribution = .fill
            tabRow.translatesAutoresizingMaskIntoConstraints = false
            tabStrip.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(tabRow)
            tabRow.addSubview(tabStrip)
            NSLayoutConstraint.activate([
                tabRow.topAnchor.constraint(equalTo: container.topAnchor),
                tabRow.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                tabRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                tabRow.heightAnchor.constraint(equalToConstant: 34),
                tabStrip.leadingAnchor.constraint(equalTo: tabRow.leadingAnchor, constant: 8),
                tabStrip.trailingAnchor.constraint(lessThanOrEqualTo: tabRow.trailingAnchor, constant: -8),
                tabStrip.centerYAnchor.constraint(equalTo: tabRow.centerYAnchor),
            ])
            headerTop = tabRow.bottomAnchor
        }
        header.addSubview(left)
        header.addSubview(title)
        header.addSubview(right)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: headerTop),
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

            webContainer.topAnchor.constraint(equalTo: header.bottomAnchor),
            webContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
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
            if site.id == Config.roblox.id {
                hide() // get out of the way of the game that's launching
            }
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
            // The Web panel opens new-window links as a new tab.
            if site.hasTabs {
                return addTab(loading: nil, configuration: configuration)
            }
            if !site.isInternal(url), !Config.isAuth(url) {
                NSWorkspace.shared.open(url)
                return nil
            }
        }
        return openPopup(configuration: configuration)
    }

    func webViewDidClose(_ webView: WKWebView) {
        if site.hasTabs, let index = tabs.firstIndex(where: { $0 === webView }) {
            closeTab(at: index)
        } else {
            popupWindows.first { $0.contentView === webView }?.close()
        }
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
