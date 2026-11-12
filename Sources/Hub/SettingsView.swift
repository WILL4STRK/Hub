import AppKit
import HubCore
import Island
import MenuBar
import SwiftUI
import Widgets

enum SettingsPage: String, CaseIterable, Identifiable {
    case overview, widgets, island, menuBar, general
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .widgets: return "Widgets"
        case .island: return "Island"
        case .menuBar: return "Menu Bar"
        case .general: return "General"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .widgets: return "rectangle.3.group"
        case .island: return "capsule.portrait"
        case .menuBar: return "menubar.rectangle"
        case .general: return "gearshape"
        }
    }

    var module: HubModuleID? {
        switch self {
        case .widgets: return .widgets
        case .island: return .island
        case .menuBar: return .menuBar
        default: return nil
        }
    }
}

/// Lets the menu, widgets, island and chevron open Settings on a given page.
@MainActor
final class SettingsRouter: ObservableObject {
    @Published var page: SettingsPage = .overview
}

struct HubSettingsView: View {
    @ObservedObject var modules: ModuleManager
    @ObservedObject var router: SettingsRouter
    let onQuit: () -> Void

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: Binding(get: { router.page }, set: { if let p = $0 { router.page = p } })) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            Group {
                switch router.page {
                case .overview: OverviewPage(modules: modules, router: router)
                case .general: GeneralPage(modules: modules, onQuit: onQuit)
                default: ModulePage(modules: modules, id: router.page.module!)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle(router.page.title)
        }
    }
}

// MARK: Overview

struct OverviewPage: View {
    @ObservedObject var modules: ModuleManager
    @ObservedObject var router: SettingsRouter

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ForEach(HubModuleID.allCases, id: \.self) { id in
                    ModuleCard(modules: modules, id: id) { router.page = page(for: id) }
                }
                Text("Switching a module off removes it from the screen and stops its work. Its settings are kept.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(20)
        }
    }

    private func page(for id: HubModuleID) -> SettingsPage {
        switch id {
        case .widgets: return .widgets
        case .island: return .island
        case .menuBar: return .menuBar
        }
    }
}

struct ModuleCard: View {
    @ObservedObject var modules: ModuleManager
    let id: HubModuleID
    let onOpen: () -> Void

    var body: some View {
        let active = modules.isActive(id)
        let paused = modules.isEnabled(id) && !active
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? Color.accentColor.gradient : Color.gray.opacity(0.35).gradient)
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(id.title).font(.system(size: 15, weight: .semibold, design: .rounded))
                    Circle().fill(active ? Color.green : (paused ? Color.orange : Color.secondary.opacity(0.5)))
                        .frame(width: 7, height: 7)
                    Text(active ? "Running" : (paused ? "Paused" : "Off"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                // ModuleManager.tick re-renders this every 2 s while Settings is open, so it stays live.
                Text(modules.statusText(id))
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(paused ? Color.orange : Color.primary)
                    .lineLimit(2)
            }
            Spacer(minLength: 10)
            Button("Settings…", action: onOpen).controlSize(.small)
            Toggle("", isOn: Binding(get: { modules.isEnabled(id) }, set: { modules.setEnabled(id, $0) }))
                .labelsHidden().toggleStyle(.switch)
                .accessibilityLabel("\(id.title) on or off")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: HubTheme.cardRadius, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .haloBorder()
        .padding(4)
    }

    private var symbol: String {
        switch id {
        case .widgets: return "rectangle.3.group.fill"
        case .island: return "capsule.portrait.fill"
        case .menuBar: return "menubar.rectangle"
        }
    }

    private var subtitle: String {
        switch id {
        case .widgets: return "Claude Code usage on the desktop: hero card, limit rings, working now, new chat."
        case .island: return "Notch island: now playing, battery, Bluetooth, weather, lyrics, lock-screen card."
        case .menuBar: return "Hide and arrange menu-bar items: sections, arranger, search, shortcuts, notch bar."
        }
    }
}

// MARK: Module pages

struct ModulePage: View {
    @ObservedObject var modules: ModuleManager
    let id: HubModuleID

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(modules.statusText(id))
                    .font(.callout).foregroundStyle(modules.isEnabled(id) && !modules.isActive(id) ? Color.orange : Color.secondary)
                    .lineLimit(2)
                Spacer()
                Toggle("\(id.title) on", isOn: Binding(get: { modules.isEnabled(id) }, set: { modules.setEnabled(id, $0) }))
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            page
                .id("\(id.rawValue)-\(modules.isActive(id))")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder private var page: some View {
        switch id {
        case .widgets: WidgetsModule.shared.settingsPage()
        case .island: IslandModule.shared.settingsPage()
        case .menuBar: MenuBarModule.shared.settingsPage()
        }
    }
}

// MARK: General

struct GeneralPage: View {
    @ObservedObject var modules: ModuleManager
    let onQuit: () -> Void
    @State private var login = LoginItem.isEnabled
    @State private var loginStatus = LoginItem.statusText
    @State private var loginError: String?
    @State private var showReport = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Hub at login", isOn: Binding(get: { login }, set: setLogin))
                Text(loginError ?? loginStatus).font(.caption)
                    .foregroundStyle(loginError == nil ? Color.secondary : Color.red)
            }
            Section("Appearance") {
                LabeledContent("Light and dark", value: "Follows System Settings › Appearance")
                LabeledContent("Accent colour", value: "Follows the system accent colour")
            }
            Section("Network") {
                Text("Hub contacts only two free, keyless services, both from the Island: api.open-meteo.com (weather) and lrclib.net (lyrics). Switch them off on the Island page. No accounts, no telemetry.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Settings from the old apps") {
                let report = SettingsMigration.report
                Text(report.first ?? "Not copied yet.")
                Text("Copied once, on Hub's first launch, from Awning, Shelf and Claude Widgets. Their own settings were left as they were.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Details", isExpanded: $showReport) {
                    ScrollView {
                        Text(report.dropFirst().joined(separator: "\n"))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(height: 160)
                }
            }
            Section {
                HStack {
                    Text("Stops the widgets, the island and the menu-bar manager, then quits Hub.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Everything", role: .destructive, action: onQuit)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            loginError = nil
        } catch {
            loginError = "Could not change the login item: \(error.localizedDescription)"
        }
        login = LoginItem.isEnabled
        loginStatus = LoginItem.statusText
    }
}

// MARK: Halo

/// The Claude Widgets halo (Theme.haloBorder), shared by Hub's own cards so they match the widgets.
enum HubTheme {
    static let cardRadius: CGFloat = 18
    static let halo = AngularGradient(
        colors: [Color(hex: 0x0A84FF), Color(hex: 0x5E5CE6), Color(hex: 0xBF5AF2), Color(hex: 0x64D2FF), Color(hex: 0x0A84FF)],
        center: .center)
}

struct HubHaloBorder: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: HubTheme.cardRadius, style: .continuous)
        content
            .overlay(shape.strokeBorder(HubTheme.halo, lineWidth: 1.5).opacity(0.85))
            .background(shape.stroke(HubTheme.halo, lineWidth: 3).blur(radius: 5).opacity(0.55))
    }
}

extension View {
    func haloBorder() -> some View { modifier(HubHaloBorder()) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
