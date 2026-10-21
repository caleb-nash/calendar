import AppKit
import Carbon.HIToolbox

enum Config {
    static let newChatURL = URL(string: "https://claude.ai/new")!
    static let recentsURL = URL(string: "https://claude.ai/recents")!

    // Global shortcut. To use Option+Space instead: kVK_Space and optionKey.
    static let hotKeyCode = UInt32(kVK_ANSI_L)
    static let hotKeyModifiers = UInt32(cmdKey)
    static let hotKeyLabel = "⌘L"

    static let defaultSize = NSSize(width: 420, height: 620)
    static let minSize = NSSize(width: 320, height: 380)

    // claude.ai serves a reduced experience to unknown browsers, so present as Safari.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    // Pages that stay inside the panel; any other link opens in the default browser.
    static let internalHosts = ["claude.ai", "claude.com", "anthropic.com"]
    // Sign-in popups that must stay in-app so the login cookie lands in the panel.
    static let authHosts = ["accounts.google.com", "appleid.apple.com"]

    static func isInternal(_ url: URL) -> Bool { matches(url, internalHosts) }
    static func isAuth(_ url: URL) -> Bool { matches(url, authHosts) }

    private static func matches(_ url: URL, _ hosts: [String]) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}
