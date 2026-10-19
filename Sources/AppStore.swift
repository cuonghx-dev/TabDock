import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppStore: ObservableObject {
    enum AddResult { case added, invalid, duplicate(UUID) }

    @Published var apps: [WebApp] = [] { didSet { save() } }
    @Published private(set) var tabs: [TabRef] = []
    @Published private(set) var automationDenied = false
    @Published private(set) var lastRemoved: (app: WebApp, index: Int)?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != oldValue else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("TabDock login item error: \(error)")
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    /// Browser the user was in most recently; used to open apps that have no tab yet.
    private var lastBrowser: Browser? {
        didSet { UserDefaults.standard.set(lastBrowser?.rawValue, forKey: "lastBrowser") }
    }

    private let pollQueue = DispatchQueue(label: "tabdock.poll")
    private var timer: Timer?
    private var polling = false

    static let configURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TabDock", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("apps.json")
    }()

    init() {
        load()
        lastBrowser = UserDefaults.standard.string(forKey: "lastBrowser").flatMap(Browser.init(rawValue:))
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let browser = app?.bundleIdentifier.flatMap(Browser.init(rawValue:)) else { return }
            Task { @MainActor in self?.lastBrowser = browser }
        }
        refresh()
    }

    func tabs(for app: WebApp) -> [TabRef] {
        tabs.filter { app.matches($0.url) }
    }

    func isOpen(_ app: WebApp) -> Bool {
        tabs.contains { app.matches($0.url) }
    }

    var openCount: Int {
        apps.filter(isOpen).count
    }

    func refresh() {
        guard !polling else { return }
        guard BrowserBridge.anyRunning else {
            if !tabs.isEmpty { tabs = [] }
            return
        }
        polling = true
        pollQueue.async {
            let result = BrowserBridge.listTabs()
            Task { @MainActor in
                self.tabs = result.tabs
                self.automationDenied = result.denied
                self.polling = false
            }
        }
    }

    /// Focus the most recently used matching tab, or open the app in the last-used browser.
    func activate(_ app: WebApp) {
        let candidates = tabs(for: app).enumerated().min { a, b in
            rank(a.element, a.offset) < rank(b.element, b.offset)
        }?.element
        if let tab = candidates {
            pollQueue.async { BrowserBridge.focus(tab) }
        } else if let url = app.openURL {
            BrowserBridge.open(url, in: lastBrowser)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.refresh() }
    }

    /// Last-used browser first, then active tabs, then window z-order (list order).
    private func rank(_ tab: TabRef, _ order: Int) -> (Int, Int, Int) {
        (tab.browser == lastBrowser ? 0 : 1, tab.isActive ? 0 : 1, order)
    }

    /// Close every matching tab in every browser. Highest index first so earlier indices stay valid.
    func closeTabs(of app: WebApp) {
        let targets = tabs(for: app).sorted { $0.tabIndex > $1.tabIndex }
        tabs.removeAll { app.matches($0.url) }
        pollQueue.async {
            targets.forEach(BrowserBridge.close)
            Task { @MainActor in self.refresh() }
        }
    }

    func add(url: String) -> AddResult {
        guard let normalized = WebApp.normalize(url) else { return .invalid }
        if let existing = apps.first(where: { $0.url.lowercased() == normalized.lowercased() }) {
            return .duplicate(existing.id)
        }
        apps.append(WebApp(url: normalized))
        return .added
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        apps[i].name = trimmed.isEmpty ? nil : trimmed
    }

    func remove(_ app: WebApp) {
        guard let i = apps.firstIndex(of: app) else { return }
        lastRemoved = (app, i)
        apps.remove(at: i)
    }

    func undoRemove() {
        guard let (app, index) = lastRemoved else { return }
        apps.insert(app, at: min(index, apps.count))
        lastRemoved = nil
    }

    func clearUndo() {
        lastRemoved = nil
    }

    /// Move an app so it lands before the item currently at `destination` (or at the end).
    func move(_ id: UUID, to destination: Int) {
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return }
        let target = destination > i ? destination - 1 : destination
        guard target != i else { return }
        var reordered = apps
        reordered.insert(reordered.remove(at: i), at: target)
        apps = reordered
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.configURL),
              let decoded = try? JSONDecoder().decode([WebApp].self, from: data) else { return }
        // Older configs stored full URLs; bring them to the normalized host+path form.
        apps = decoded.map { app in
            var app = app
            if let normalized = WebApp.normalize(app.url) { app.url = normalized }
            if app.name?.isEmpty == true { app.name = nil }
            return app
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(apps).write(to: Self.configURL, options: .atomic)
    }
}
