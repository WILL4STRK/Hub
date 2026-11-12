import AppKit

// `Hub --unregister-login` is used by ./clean.sh.
if CommandLine.arguments.contains("--unregister-login") {
    if LoginItem.status != .notRegistered { try? LoginItem.set(false) }
    exit(0)
}

// One copy at a time: a second launch asks the running Hub to open Settings, then quits.
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
    DistributedNotificationCenter.default().postNotificationName(.init("local.hub.Hub.openSettings"), object: nil,
                                                                 userInfo: nil, deliverImmediately: true)
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = HubDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)  // no Dock icon; Hub's one menu-bar icon is the way in
    app.run()
}
