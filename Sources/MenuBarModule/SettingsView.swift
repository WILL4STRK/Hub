import AppKit
import ShelfCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var items: ItemListModel
    let onAssign: (String, MenuSection) -> Void
    let onRefresh: () -> Void
    /// Row hover: key while hovering, nil when the pointer leaves.
    let onLocate: (String?) -> Void

    var body: some View {
        Form {
            Section("Sections") {
                Toggle("Always-hidden section", isOn: $settings.alwaysHiddenEnabled)
                Text("Hold ⌘ and drag menu bar items to arrange them. Items left of the solid divider are hidden. Items left of the dashed divider stay hidden until you Option-click the chevron.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if items.needsAccessibility {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("To move items for you, Hub needs Accessibility. It only sends ⌘-drags in the menu bar. Turn it on to choose sections here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open Privacy Settings…") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                if let error = items.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                ForEach(items.rows) { row in
                    HStack(spacing: 8) {
                        Image(nsImage: row.icon ?? NSImage())
                            .resizable()
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name).lineLimit(1)
                            if let detail = row.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Picker(row.name, selection: Binding(
                            get: { settings.itemSections[row.id] ?? row.section },
                            set: { onAssign(row.id, $0) }
                        )) {
                            Text("Visible").tag(MenuSection.visible)
                            Text("Hidden").tag(MenuSection.hidden)
                            Text("Always hidden").tag(MenuSection.alwaysHidden)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                        .disabled(items.busy || items.needsAccessibility)
                    }
                    .contentShape(Rectangle())
                    .onHover { inside in onLocate(inside ? row.id : nil) }
                    .accessibilityHint("Hover to highlight this item in the menu bar")
                }
            } header: {
                HStack {
                    Text("Menu bar items")
                    Spacer()
                    if items.busy { ProgressView().controlSize(.small) }
                    Button("Refresh", action: onRefresh)
                        .buttonStyle(.borderless)
                        .disabled(items.busy)
                }
            }

            Section("Show hidden items") {
                Toggle("Click an empty area of the menu bar (not beside the chevron)", isOn: $settings.showOnClick)
                Toggle("Hover over an empty area of the menu bar", isOn: $settings.showOnHover)
                Toggle("Point near the chevron (within 80 pt to its left)", isOn: $settings.showOnHoverNearChevron)
                Toggle("Scroll or swipe in the menu bar", isOn: $settings.showOnScroll)
                LabeledContent("Keyboard shortcut") {
                    HotKeyRecorder(spec: $settings.hotKey)
                }
                if let error = settings.hotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Search") {
                LabeledContent("Search shortcut") {
                    HotKeyRecorder(spec: $settings.searchHotKey)
                }
                if let error = settings.searchHotKeyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text("Also in the chevron's right-click menu. Opening an item needs Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Rehide") {
                Toggle("Rehide automatically", isOn: $settings.autoRehide)
                if settings.autoRehide {
                    Stepper(value: $settings.rehideSeconds, in: RehidePolicy.minSeconds...RehidePolicy.maxSeconds, step: 1) {
                        Text("After \(Int(settings.rehideSeconds)) seconds")
                    }
                }
                Toggle("Rehide when the pointer leaves the menu bar", isOn: $settings.rehideWhenLeaving)
                Text("Never while a menu from a revealed item is open.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle("Tint the menu bar", isOn: $settings.menuBarTint)
                ColorPicker("Tint colour", selection: Binding(
                    get: { Color(nsColor: NSColor(hex: settings.menuBarTintColor) ?? .systemPurple) },
                    set: { settings.menuBarTintColor = NSColor($0).hexString }), supportsOpacity: false)
                    .disabled(!settings.menuBarTint)
            }

            Section("Notch") {
                Toggle("Use a bar below the menu bar when items would go behind the notch", isOn: $settings.useBarOnNotch)
                Text(notchStatus).font(.caption).foregroundStyle(.secondary)
            }

        }
        .formStyle(.grouped)
        .onAppear(perform: onRefresh)
    }

    private var notchStatus: String {
        let notched = NSScreen.screens.contains { NotchLayout.notchRect($0.shelfInfo) != nil }
        return notched ? "A display with a notch is connected." : "No display with a notch is connected."
    }

}

/// Records a global shortcut. Esc cancels. Needs at least one of ⌘ ⌥ ⌃.
struct HotKeyRecorder: View {
    @Binding var spec: HotKeySpec?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? "Type shortcut…" : (spec?.display ?? "Record Shortcut")) {
                recording ? stop() : start()
            }
            .accessibilityLabel(recording ? "Recording shortcut. Press Escape to cancel." : "Keyboard shortcut \(spec?.display ?? "none")")
            if spec != nil, !recording {
                Button { spec = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Clear shortcut")
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            let flags = event.modifierFlags
            let candidate = HotKeySpec(
                keyCode: UInt32(event.keyCode),
                modifiers: HotKeySpec.modifiers(command: flags.contains(.command), option: flags.contains(.option),
                                                control: flags.contains(.control), shift: flags.contains(.shift)),
                key: Self.keyName(event)
            )
            if candidate.isValid {
                spec = candidate
                stop()
            } else {
                NSSound.beep()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "Space"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }
}
