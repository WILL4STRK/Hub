import AppKit
import SwiftUI
import WidgetCore

/// The Claude Widgets module inside Hub: desktop panels fed by usage-grid's files.
/// `start()` shows the widgets and starts the 3 s file reader; `stop()` hides them and stops the reader.
@MainActor
public final class WidgetsModule {
    public static let shared = WidgetsModule()
    /// Set by Hub: opens Hub's Settings on the Widgets page.
    public var onOpenSettings: (() -> Void)?

    let store = Store()
    private var panels: [DesktopPanel] = []
    private var screenObserver: Any?
    public private(set) var isRunning = false

    private init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        store.start()
        if panels.isEmpty {
            let home = DesktopPanel(key: "home", size: HomeWidget.size, defaultOrigin: Self.defaultOrigin()) { [store] h in
                HomeWidget(store: store, handle: h)
            }
            panels = [home]
        }
        panels.forEach { $0.keepOnScreen(); $0.orderFrontRegardless() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.panels.forEach { $0.keepOnScreen() } }
        }
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        store.stop()
        panels.forEach { $0.orderOut(nil) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
    }

    /// One line for Hub's Overview.
    public var statusText: String {
        guard isRunning else { return "Off" }
        let open = store.chats.count
        let busy = store.agents.working.count
        let data = store.stats == nil && store.limits == nil ? "waiting for usage-grid data" : "usage data loaded"
        return "\(open) chat\(open == 1 ? "" : "s") open · \(busy) working · \(data)"
    }

    public func refresh() {
        store.tick()
        store.rescan(force: true)
    }

    /// Top-left of the main screen.
    static func defaultOrigin() -> CGPoint {
        let f = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 14
        return CGPoint(x: f.minX + margin, y: max(f.minY, f.maxY - HomeWidget.size.height - margin))
    }

    public func resetPositions() {
        panels.forEach { $0.setFrameOrigin(Self.defaultOrigin()) }
    }

    /// The Widgets page of Hub's Settings.
    public func settingsPage() -> AnyView {
        AnyView(WidgetsSettingsPage(module: self, store: store))
    }
}

/// Right-click menu on every widget.
struct WidgetMenu: ViewModifier {
    let store: Store
    func body(content: Content) -> some View {
        content.contextMenu {
            Button("Refresh now") {
                store.tick()
                store.rescan(force: true)
            }
            Button("Open Claude Code") { NSWorkspace.shared.open(openClaudeURL) }
            Divider()
            Button("Reset widget position") { WidgetsModule.shared.resetPositions() }
            Button("Widget Settings…") { WidgetsModule.shared.onOpenSettings?() }
        }
    }
}

extension View {
    func widgetMenu(store: Store) -> some View { modifier(WidgetMenu(store: store)) }
}

/// Every Claude Widgets setting: position lock, position reset, the prompt box's folder, data refresh.
struct WidgetsSettingsPage: View {
    let module: WidgetsModule
    @ObservedObject var store: Store
    @AppStorage("ClaudeWidgets.locked") private var locked = false
    @AppStorage("promptFolder") private var folder = ""

    var body: some View {
        Form {
            Section("Position") {
                Toggle("Lock widget position", isOn: $locked)
                Text("Unlocked: drag a widget anywhere. Double-click a widget for the same lock bar.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reset widget position") { module.resetPositions() }
            }
            Section("New chat prompt") {
                Picker("Folder for new chats", selection: $folder) {
                    Text("Claude's default folder").tag("")
                    ForEach(store.recentFolders, id: \.self) { Text(($0 as NSString).abbreviatingWithTildeInPath).tag($0) }
                    if !folder.isEmpty, !store.recentFolders.contains(folder) {
                        Text((folder as NSString).abbreviatingWithTildeInPath).tag(folder)
                    }
                }
            }
            Section("Data") {
                LabeledContent("Source", value: (store.paths.root.path as NSString).abbreviatingWithTildeInPath)
                LabeledContent("Status", value: module.statusText)
                LabeledContent("Scanner", value: DataPaths.statsScript == nil ? "usage-grid stats.py not found" : "usage-grid stats.py found")
                Button("Refresh now") { module.refresh() }
            }
        }
        .formStyle(.grouped)
    }
}
