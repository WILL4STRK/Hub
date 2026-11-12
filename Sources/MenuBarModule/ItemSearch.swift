import AppKit
import ShelfCore
import SwiftUI

/// Search popup: lists every menu bar item, Return or click opens it.
/// Opening reveals the item's section first, then presses it through
/// Accessibility, so its menu appears in the right place.
final class ItemSearchController {
    private var panel: SearchPanel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    var onPick: ((MenuBarItems.Described) -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? close() : open()
    }

    func open() {
        close()
        let model = SearchModel(items: MenuBarItems.describe())
        let width: CGFloat = 360
        let height: CGFloat = 340
        guard let screen = NSScreen.main else { return }
        let frame = NSRect(x: screen.frame.midX - width / 2,
                           y: screen.frame.maxY - screen.frame.height * 0.22 - height,
                           width: width, height: height)

        let panel = SearchPanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true
        let host = NSHostingView(rootView: SearchView(model: model, onPick: { [weak self] in self?.pick($0) }))
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)
        panel.contentView = background
        panel.setAccessibilityLabel("Search menu bar items")

        // Arrow keys, Return and Esc while the panel is key; everything else goes to the field.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak model] event in
            guard let self, let model, event.window === self.panel else { return event }
            switch event.keyCode {
            case 125: model.move(1); return nil // down
            case 126: model.move(-1); return nil // up
            case 53: self.close(); return nil // esc
            case 36, 76: // return, enter
                if let item = model.selected { self.pick(item) }
                return nil
            default: return event
            }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.close() }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func pick(_ item: MenuBarItems.Described) {
        close()
        onPick?(item)
    }
}

/// Borderless panels cannot become key by default; the search field needs it.
private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class SearchModel: ObservableObject {
    let items: [MenuBarItems.Described]
    @Published var query = "" { didSet { selection = 0 } }
    @Published var selection = 0

    init(items: [MenuBarItems.Described]) { self.items = items }

    var results: [MenuBarItems.Described] {
        items.compactMap { item -> (MenuBarItems.Described, Int)? in
            SearchRank.score(query: query, fields: [item.name, item.appName]).map { (item, $0) }
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.item.frame.minX > $1.0.item.frame.minX }
        .map(\.0)
    }

    var selected: MenuBarItems.Described? {
        let r = results
        return r.indices.contains(selection) ? r[selection] : nil
    }

    func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }
}

private struct SearchView: View {
    @ObservedObject var model: SearchModel
    let onPick: (MenuBarItems.Described) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Search menu bar items", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .accessibilityLabel("Search menu bar items")
            }
            .padding(12)
            Divider()
            let results = model.results
            if results.isEmpty {
                Text("No matching items").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.key) { index, item in
                                row(item, selected: index == model.selection)
                                    .id(index)
                                    .onTapGesture { onPick(item) }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: model.selection) { proxy.scrollTo($0) }
                }
            }
        }
        .onAppear { focused = true }
    }

    private func row(_ item: MenuBarItems.Described, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: item.icon ?? NSImage())
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1)
                if item.name != item.appName {
                    Text(item.appName).font(.caption).foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
