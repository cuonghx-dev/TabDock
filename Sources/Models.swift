import Foundation

struct WebApp: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String?
    /// Normalized host plus optional path, e.g. `mail.google.com`. Keeps an explicit `http://`
    /// so plain-HTTP apps (localhost, intranet) still open correctly.
    var url: String
    /// Chrome profile directory (e.g. `Profile 2`) to open this app in; nil uses the last browser.
    var chromeProfile: String?

    var openURL: URL? { URL(string: url.contains("://") ? url : "https://" + url) }

    /// Stored value without the scheme, shown under the name.
    var displayURL: String { url.hasPrefix("http://") ? String(url.dropFirst(7)) : url }

    var displayName: String {
        guard let name, !name.isEmpty else { return displayURL }
        return name
    }

    /// Tab belongs to this app when its host equals the app host (or is a subdomain of it), the
    /// port matches, and the tab path starts with the app path.
    func matches(_ tabURL: String) -> Bool {
        guard let app = openURL, let tab = URL(string: tabURL),
              let appHost = app.host?.lowercased(), let tabHost = tab.host?.lowercased() else { return false }
        guard tabHost == appHost || tabHost.hasSuffix("." + appHost),
              app.port == tab.port else { return false }
        let appPath = Self.trimSlash(app.path)
        return appPath.isEmpty || Self.trimSlash(tab.path).hasPrefix(appPath)
    }

    /// Strip scheme, `www.` and trailing slashes. Returns nil for empty or unparseable input.
    static func normalize(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return nil }
        var scheme = ""
        let lower = s.lowercased()
        if lower.hasPrefix("https://") {
            s.removeFirst(8)
        } else if lower.hasPrefix("http://") {
            s.removeFirst(7)
            scheme = "http://"
        } else if s.contains("://") {
            return nil
        }
        if s.lowercased().hasPrefix("www.") { s.removeFirst(4) }
        while s.hasSuffix("/") { s.removeLast() }
        if let slash = s.firstIndex(of: "/") {
            s = s[..<slash].lowercased() + s[slash...]
        } else {
            s = s.lowercased()
        }
        guard let host = URL(string: "https://" + s)?.host, !host.isEmpty,
              host.contains(".") || host == "localhost" else { return nil }
        return scheme + s
    }

    private static func trimSlash(_ p: String) -> String {
        p.hasSuffix("/") ? String(p.dropLast()) : p
    }
}

enum Browser: String, CaseIterable, Codable {
    case chrome = "com.google.Chrome"
    case safari = "com.apple.Safari"

    var appName: String {
        switch self {
        case .chrome: "Google Chrome"
        case .safari: "Safari"
        }
    }
}

struct ChromeProfile: Hashable, Identifiable {
    /// Directory name under Chrome's user data dir, passed as `--profile-directory`.
    let dir: String
    let name: String

    var id: String { dir }

    /// Profiles listed in Chrome's `Local State`, sorted by display name.
    static func loadAll() -> [ChromeProfile] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (root["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return [] }
        return cache.map { dir, info in
            ChromeProfile(dir: dir, name: (info as? [String: Any])?["name"] as? String ?? dir)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct TabRef: Hashable {
    let browser: Browser
    let windowID: Int
    let tabIndex: Int
    let isActive: Bool
    let url: String
    let title: String
}
