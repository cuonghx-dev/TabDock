import AppKit

/// Reads, focuses and closes Chrome / Safari tabs through AppleScript. Only talks to a browser
/// when it is already running, so polling never launches one by accident.
enum BrowserBridge {
    private static let fieldSep = "\u{1F}"
    private static let rowSep = "\u{1E}"
    /// errAEEventNotPermitted: the user denied the Automation permission.
    private static let notPermitted = -1743

    static func isRunning(_ browser: Browser) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.rawValue).isEmpty
    }

    static var anyRunning: Bool { Browser.allCases.contains(where: isRunning) }

    /// Tabs of every running browser, windows front to back. `denied` is true when any browser
    /// refused the Apple Events permission.
    static func listTabs() -> (tabs: [TabRef], denied: Bool) {
        var tabs: [TabRef] = []
        var denied = false
        for browser in Browser.allCases where isRunning(browser) {
            let (raw, code) = run(listSource(browser))
            if code == notPermitted { denied = true }
            guard let raw else { continue }
            tabs += raw.components(separatedBy: rowSep).compactMap { row in
                let f = row.components(separatedBy: fieldSep)
                guard f.count == 5, let wid = Int(f[0]), let idx = Int(f[1]) else { return nil }
                return TabRef(browser: browser, windowID: wid, tabIndex: idx, isActive: f[2] == "1",
                              url: f[3], title: f[4])
            }
        }
        return (tabs, denied)
    }

    private static func listSource(_ browser: Browser) -> String {
        let activeIndex = browser == .chrome ? "active tab index of w" : "index of current tab of w"
        let titleProp = browser == .chrome ? "title" : "name"
        return """
        set FS to (ASCII character 31)
        set RS to (ASCII character 30)
        set out to ""
        tell application "\(browser.appName)"
            repeat with w in windows
                try
                    set wid to id of w
                    set act to \(activeIndex)
                    repeat with i from 1 to count of tabs of w
                        try
                            set t to tab i of w
                            set u to URL of t
                            set n to \(titleProp) of t
                            if u is missing value then set u to ""
                            if n is missing value then set n to ""
                            set a to "0"
                            if i = act then set a to "1"
                            set out to out & wid & FS & i & FS & a & FS & u & FS & n & RS
                        end try
                    end repeat
                end try
            end repeat
        end tell
        return out
        """
    }

    static func focus(_ tab: TabRef) {
        let select = tab.browser == .chrome
            ? "set active tab index of w to \(tab.tabIndex)"
            : "set current tab of w to tab \(tab.tabIndex) of w"
        _ = run("""
        tell application "\(tab.browser.appName)"
            set w to window id \(tab.windowID)
            \(select)
            set index of w to 1
            activate
        end tell
        """)
    }

    static func close(_ tab: TabRef) {
        _ = run("""
        tell application "\(tab.browser.appName)"
            close tab \(tab.tabIndex) of window id \(tab.windowID)
        end tell
        """)
    }

    /// Open in the preferred browser; fall back to the default browser if it is not installed.
    static func open(_ url: URL, in browser: Browser?) {
        guard let browser,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.rawValue) else {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func run(_ source: String) -> (String?, Int?) {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { NSLog("TabDock AppleScript error: \(error)") }
        return (result?.stringValue, error?[NSAppleScript.errorNumber] as? Int)
    }
}
