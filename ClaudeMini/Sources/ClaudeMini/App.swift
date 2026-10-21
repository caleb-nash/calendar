import AppKit

@main
enum ClaudeMiniApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Accessory: no Dock icon, and showing the panel never pulls the user out of their current app.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
