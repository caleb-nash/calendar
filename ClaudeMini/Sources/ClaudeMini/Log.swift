import os

/// View live with:
///   log stream --level info --predicate 'subsystem == "com.calebnash.ClaudeMini"'
enum Log {
    static let hotKey = Logger(subsystem: "com.calebnash.ClaudeMini", category: "hotkey")
    static let window = Logger(subsystem: "com.calebnash.ClaudeMini", category: "window")
}
