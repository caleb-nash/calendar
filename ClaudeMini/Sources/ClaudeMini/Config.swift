import AppKit
import Carbon.HIToolbox

/// One floating window: what it loads, its global shortcut, and which links stay inside it.
struct Site {
    let id: String
    let hotKeyID: UInt32
    let title: String
    let symbol: String
    let homeURL: URL
    // Global shortcut. For Command use cmdKey; for Option+Space use kVK_Space.
    let hotKeyCode: UInt32
    let hotKeyModifiers: UInt32
    let hotKeyLabel: String
    let defaultSize: NSSize
    /// Pages that stay inside the panel; other links open in the default browser. nil = everything stays.
    let internalHosts: [String]?
    let hasAddressBar: Bool

    var isClaude: Bool { id == "claude" }

    func isInternal(_ url: URL) -> Bool {
        guard let internalHosts else { return true }
        return Config.matches(url, internalHosts)
    }
}

enum Config {
    static let newChatURL = URL(string: "https://claude.ai/new")!
    static let recentsURL = URL(string: "https://claude.ai/recents")!

    static let claude = Site(
        id: "claude", hotKeyID: 1, title: "Claude", symbol: "sparkle",
        homeURL: newChatURL,
        hotKeyCode: UInt32(kVK_ANSI_L), hotKeyModifiers: UInt32(optionKey), hotKeyLabel: "⌥L",
        defaultSize: NSSize(width: 420, height: 620),
        internalHosts: ["claude.ai", "claude.com", "anthropic.com"],
        hasAddressBar: false)

    static let web = Site(
        id: "web", hotKeyID: 2, title: "Web", symbol: "globe",
        homeURL: URL(string: "https://www.google.com")!,
        hotKeyCode: UInt32(kVK_ANSI_M), hotKeyModifiers: UInt32(optionKey), hotKeyLabel: "⌥M",
        defaultSize: NSSize(width: 520, height: 680),
        internalHosts: nil,
        hasAddressBar: true)

    static let roblox = Site(
        id: "roblox", hotKeyID: 3, title: "Roblox", symbol: "gamecontroller",
        homeURL: URL(string: "https://www.roblox.com/home")!,
        hotKeyCode: UInt32(kVK_ANSI_N), hotKeyModifiers: UInt32(optionKey), hotKeyLabel: "⌥N",
        defaultSize: NSSize(width: 520, height: 680),
        internalHosts: ["roblox.com", "rbxcdn.com", "arkoselabs.com", "funcaptcha.com"],
        hasAddressBar: false)

    static let sites = [claude, web, roblox]

    static let minSize = NSSize(width: 320, height: 380)

    // claude.ai serves a reduced experience to unknown browsers, so present as Safari.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    // Sign-in popups that must stay in-app so the login cookie lands in the panel.
    static let authHosts = ["accounts.google.com", "appleid.apple.com"]

    static func isInternal(_ url: URL) -> Bool { claude.isInternal(url) }
    static func isAuth(_ url: URL) -> Bool { matches(url, authHosts) }

    static func matches(_ url: URL, _ hosts: [String]) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// Turns address-bar text into a URL: full URLs as-is, "example.com" gets https://,
    /// anything else becomes a Google search.
    static func url(fromAddressBar text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) {
            return url
        }
        if !trimmed.contains(" "), trimmed.contains("."), let url = URL(string: "https://" + trimmed) {
            return url
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
    }
}
