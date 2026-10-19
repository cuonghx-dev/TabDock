import SwiftUI

@main
struct TabDockApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            DockView().environmentObject(store)
        } label: {
            Image(systemName: "square.grid.2x2")
            if store.openCount > 0 { Text("\(store.openCount)") }
        }
        .menuBarExtraStyle(.window)
    }
}

private let rowHeight: CGFloat = 40
private let gutter: CGFloat = 18

struct DockView: View {
    @EnvironmentObject var store: AppStore
    @State private var editingNameId: UUID?
    @State private var flashId: UUID?
    @State private var draggingId: UUID?
    @State private var dropIndex: Int?
    @State private var listHeight: CGFloat = rowHeight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if store.automationDenied { permissionNotice }

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.apps.enumerated()), id: \.element.id) { index, app in
                            AppRow(app: app, editingNameId: $editingNameId, flashing: flashId == app.id,
                                   onDragStart: { draggingId = app.id })
                                .overlay(alignment: .top) { insertionLine(at: index) }
                                .overlay(alignment: .bottom) {
                                    if index == store.apps.count - 1 { insertionLine(at: index + 1) }
                                }
                        }
                    }
                    .onDrop(of: [.text], delegate: ReorderDropDelegate(
                        count: store.apps.count, dropIndex: $dropIndex,
                        canDrop: draggingId != nil,
                        perform: { destination in
                            if let id = draggingId { store.move(id, to: destination) }
                            draggingId = nil
                        }))

                    AddRow(onDuplicate: flash)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            // ScrollView has no ideal height inside MenuBarExtra and collapses to zero; size it to its content.
            .frame(height: min(listHeight, 420))

            Divider().padding(.vertical, 6).padding(.horizontal, 8)

            QuitRow()
        }
        .padding(6)
        .frame(width: 300)
        .background {
            Button("Undo Remove", action: store.undoRemove)
                .keyboardShortcut("z", modifiers: .command)
                .disabled(store.lastRemoved == nil || editingNameId != nil)
                .opacity(0)
        }
        .onAppear { store.refresh() }
        .onDisappear {
            store.clearUndo()
            editingNameId = nil
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("TabDock").font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(store.openCount) of \(store.apps.count) open")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Menu {
                Toggle("Launch at login", isOn: $store.launchAtLogin)
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 22, height: 22)
        }
        .padding(EdgeInsets(top: 4, leading: 8, bottom: 6, trailing: 4))
    }

    private var permissionNotice: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("Browser access denied.").foregroundStyle(.secondary)
            Button("Open Settings…") {
                let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                if let url = URL(string: url) { NSWorkspace.shared.open(url) }
            }
            .buttonStyle(.link)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    @ViewBuilder private func insertionLine(at index: Int) -> some View {
        if dropIndex == index {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(height: 2)
                .padding(.leading, gutter)
                .offset(y: index == store.apps.count ? 1 : -1)
                .allowsHitTesting(false)
        }
    }

    private func flash(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.15)) { flashId = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeIn(duration: 0.3)) { if flashId == id { flashId = nil } }
        }
    }
}

/// Rows are a fixed height, so the drop slot follows directly from the pointer's y position.
struct ReorderDropDelegate: DropDelegate {
    let count: Int
    @Binding var dropIndex: Int?
    let canDrop: Bool
    let perform: (Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { canDrop }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        dropIndex = min(max(Int((info.location.y + rowHeight / 2) / rowHeight), 0), count)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { dropIndex = nil }

    func performDrop(info: DropInfo) -> Bool {
        defer { dropIndex = nil }
        guard let dropIndex else { return false }
        perform(dropIndex)
        return true
    }
}

struct AppRow: View {
    @EnvironmentObject var store: AppStore
    let app: WebApp
    @Binding var editingNameId: UUID?
    let flashing: Bool
    let onDragStart: () -> Void
    @State private var hovering = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    private var isOpen: Bool { store.isOpen(app) }
    private var isEditing: Bool { editingNameId == app.id }

    private var rowFill: Color {
        if flashing { return Color.accentColor.opacity(0.2) }
        return hovering ? Color.primary.opacity(0.08) : Color.clear
    }

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(app: app)
            labels
            Spacer(minLength: 0)
            if hovering && !isEditing { hoverButtons }
            StatusDot(isOpen: isOpen)
        }
        .buttonStyle(.borderless)
        .padding(.leading, gutter)
        .padding(.trailing, 8)
        .frame(height: rowHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(rowFill))
        .overlay(alignment: .leading) { grip }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !isEditing { store.activate(app) } }
    }

    @ViewBuilder private var labels: some View {
        VStack(alignment: .leading, spacing: 1) {
            if isEditing {
                TextField("Name", text: $draftName, prompt: Text(app.displayURL))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .font(.system(size: 13))
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { editingNameId = nil }
                    .onChange(of: nameFocused) { _, focused in if !focused { commitRename() } }
                    .onAppear { nameFocused = true }
            } else {
                Text(app.displayName)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .gesture(TapGesture(count: 2).onEnded(startRename)
                        .exclusively(before: TapGesture().onEnded { store.activate(app) }))
            }
            Text(app.displayURL)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder private var hoverButtons: some View {
        if isOpen {
            Button { store.closeTabs(of: app) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .help("Close all tabs of this app")
        }
        Button { store.remove(app) } label: {
            Image(systemName: "trash").font(.system(size: 11))
                .foregroundStyle(.red)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .help("Remove from list")
    }

    /// Always in the hierarchy (only its opacity changes) so the drag session keeps its source view.
    private var grip: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 16, height: rowHeight)
            .contentShape(Rectangle())
            .opacity(hovering && !isEditing ? 1 : 0)
            .onTapGesture {}
            .onDrag {
                onDragStart()
                return NSItemProvider(object: app.id.uuidString as NSString)
            } preview: {
                DragPreview(app: app, isOpen: isOpen)
            }
            .help("Drag to reorder")
    }

    private func startRename() {
        draftName = app.name ?? ""
        editingNameId = app.id
    }

    private func commitRename() {
        guard isEditing else { return }
        store.rename(app.id, to: draftName)
        editingNameId = nil
    }
}

/// The lifted row shown under the pointer while reordering.
struct DragPreview: View {
    let app: WebApp
    let isOpen: Bool

    var body: some View {
        HStack(spacing: 8) {
            AppIcon(app: app)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.displayName).font(.system(size: 13)).lineLimit(1)
                Text(app.displayURL).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            StatusDot(isOpen: isOpen)
        }
        .padding(.leading, gutter)
        .padding(.trailing, 8)
        .frame(width: 288, height: rowHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 8, y: 6)
        .rotationEffect(.degrees(-0.6))
        .offset(x: 4)
        .padding(12)
    }
}

struct AddRow: View {
    @EnvironmentObject var store: AppStore
    let onDuplicate: (UUID) -> Void
    @State private var isAdding = false
    @State private var newURL = ""
    @State private var invalid = false
    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isAdding {
                TextField("URL, e.g. github.com", text: $newURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .overlay {
                        if invalid {
                            RoundedRectangle(cornerRadius: 5).strokeBorder(Color.red, lineWidth: 1)
                        }
                    }
                    .focused($focused)
                    .onSubmit(add)
                    .onExitCommand(perform: collapse)
                    .onChange(of: newURL) { invalid = false }
                    .onAppear { focused = true }
                Button("Add", action: add)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .foregroundStyle(.tertiary)
                    .overlay(Image(systemName: "plus").font(.system(size: 11)).foregroundStyle(.secondary))
                    .frame(width: 24, height: 24)
                Text("Add app").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, gutter)
        .padding(.trailing, 8)
        .frame(height: rowHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering && !isAdding ? Color.primary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !isAdding { isAdding = true } }
        .onDisappear(perform: collapse)
    }

    private func add() {
        switch store.add(url: newURL) {
        case .added:
            collapse()
        case .invalid:
            invalid = true
        case .duplicate(let id):
            collapse()
            onDuplicate(id)
        }
    }

    private func collapse() {
        isAdding = false
        newURL = ""
        invalid = false
    }
}

struct QuitRow: View {
    @State private var hovering = false

    var body: some View {
        Button { NSApp.terminate(nil) } label: {
            HStack {
                Text("Quit")
                Spacer()
                Text("⌘Q").foregroundStyle(.secondary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Color.primary.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("q", modifiers: .command)
        .onHover { hovering = $0 }
    }
}

struct StatusDot: View {
    let isOpen: Bool

    var body: some View {
        Circle()
            .fill(isOpen ? Color.green : Color.gray.opacity(0.35))
            .frame(width: 8, height: 8)
    }
}

struct AppIcon: View {
    let app: WebApp

    var body: some View {
        AsyncImage(url: faviconURL) { image in
            image.resizable().interpolation(.high)
        } placeholder: {
            ZStack {
                Color.accentColor.opacity(0.8)
                Text(String(app.displayName.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Favicon from the app's own origin; nothing is sent to third parties.
    private var faviconURL: URL? {
        guard let u = app.openURL, let scheme = u.scheme, let host = u.host else { return nil }
        let port = u.port.map { ":\($0)" } ?? ""
        return URL(string: "\(scheme)://\(host)\(port)/favicon.ico")
    }
}
