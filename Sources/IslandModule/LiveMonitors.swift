import AppKit
import CoreAudio
import IOBluetooth
import IOKit
import IOKit.ps

/// Short-lived notices shown in the island.
enum Toast: Equatable {
    enum Level { case volume, brightness }
    case battery(level: Int, charging: Bool, title: String)
    case lowPower(on: Bool)
    case bluetooth(name: String, detail: String, connected: Bool)
    case level(kind: Level, value: Double, muted: Bool)
    case output(name: String)

    /// Seconds the toast stays up.
    var lifetime: TimeInterval {
        if case .level = self { return 1.6 }
        if case .bluetooth = self { return 4 }
        return 2.8
    }
}

// MARK: Battery

/// Battery transitions from IOKit power sources: plugged in, unplugged, low battery, Low Power Mode.
final class PowerMonitor {
    private let onToast: (Toast) -> Void
    private var source: CFRunLoopSource?
    private var lastPlugged: Bool?
    private var lowAlerted: Set<Int> = []

    init(onToast: @escaping (Toast) -> Void) {
        self.onToast = onToast
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<PowerMonitor>.fromOpaque(ctx).takeUnretainedValue().read()
        }, context)?.takeRetainedValue() {
            source = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.onToast(.lowPower(on: ProcessInfo.processInfo.isLowPowerModeEnabled))
        }
        read()
    }

    struct Reading { let level: Int; let charging: Bool; let plugged: Bool }

    static func current() -> Reading? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let cap = d[kIOPSCurrentCapacityKey] as? Int,
                  let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return Reading(level: cap * 100 / max,
                           charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                           plugged: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    private func read() {
        guard let r = Self.current() else { return }
        defer { lastPlugged = r.plugged }
        guard let last = lastPlugged else { return } // first reading: no toast
        if r.plugged && !last {
            lowAlerted.removeAll()
            onToast(.battery(level: r.level, charging: r.charging, title: r.charging ? "Charging" : "Plugged in"))
        } else if !r.plugged && last {
            onToast(.battery(level: r.level, charging: false, title: "On battery"))
        } else if !r.plugged {
            for threshold in [20, 10, 5] where r.level <= threshold && !lowAlerted.contains(threshold) {
                lowAlerted.insert(threshold)
                onToast(.battery(level: r.level, charging: false, title: "Low battery"))
                break
            }
        }
    }
}

// MARK: Bluetooth

/// Connect/disconnect notices. Battery levels come from `system_profiler` (public tool);
/// "Battery unknown" when the device does not report them.
final class BluetoothMonitor: NSObject {
    private let onToast: (Toast) -> Void
    private var connectNote: IOBluetoothUserNotification?
    private let started = Date()

    init(onToast: @escaping (Toast) -> Void) {
        self.onToast = onToast
        super.init()
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self,
                                                 selector: #selector(connected(_:device:)))
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        device.register(forDisconnectNotification: self, selector: #selector(disconnected(_:device:)))
        // Registration replays already-connected devices; ignore those.
        guard Date().timeIntervalSince(started) > 3 else { return }
        let name = device.name ?? "Bluetooth device"
        onToast(.bluetooth(name: name, detail: "Connected", connected: true))
        let address = device.addressString ?? ""
        // Battery levels show up a moment after connecting.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2.5) { [weak self] in
            let detail = Self.batteryDetail(address: address) ?? "Battery unknown"
            DispatchQueue.main.async {
                self?.onToast(.bluetooth(name: name, detail: detail, connected: true))
            }
        }
    }

    @objc private func disconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        onToast(.bluetooth(name: device.name ?? "Bluetooth device", detail: "Disconnected", connected: false))
    }

    static func batteryDetail(address: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let want = normalize(address)
        guard let props = findDevice(json, address: want) else { return nil }
        let parts: [(String, String)] = [("Left", "device_batteryLevelLeft"), ("Right", "device_batteryLevelRight"),
                                         ("Case", "device_batteryLevelCase"), ("Battery", "device_batteryLevelMain")]
        let found = parts.compactMap { label, key in (props[key] as? String).map { "\(label) \($0)" } }
        return found.isEmpty ? nil : found.joined(separator: " · ")
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().filter { $0.isHexDigit }
    }

    /// Walks system_profiler JSON for a device dictionary with a matching address.
    private static func findDevice(_ node: Any, address: String) -> [String: Any]? {
        if let dict = node as? [String: Any] {
            if let a = dict["device_address"] as? String, normalize(a) == address { return dict }
            for value in dict.values { if let hit = findDevice(value, address: address) { return hit } }
        } else if let array = node as? [Any] {
            for value in array { if let hit = findDevice(value, address: address) { return hit } }
        }
        return nil
    }
}

// MARK: Audio output (CoreAudio)

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

/// Lists output devices, switches the default output and reports volume changes.
final class AudioOutputs: ObservableObject {
    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var defaultID: AudioDeviceID = 0

    var onVolume: ((Float, Bool) -> Void)?
    var onOutputChanged: ((String) -> Void)?

    private var watchedDevice: AudioDeviceID = 0
    private var lastVolume: (Float, Bool)?
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { self?.reload(announce: true) }
    }
    private lazy var volumeListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
        DispatchQueue.main.async { self?.volumeChanged() }
    }

    init() {
        var defaultAddr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var listAddr = Self.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(system, &defaultAddr, .main, deviceListener)
        AudioObjectAddPropertyListenerBlock(system, &listAddr, .main, deviceListener)
        reload(announce: false)
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                                element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    func reload(announce: Bool) {
        let previous = defaultID
        defaultID = Self.defaultOutput()
        devices = Self.outputDevices()
        if defaultID != watchedDevice { watchVolume(of: defaultID) }
        if announce, previous != 0, previous != defaultID, let d = devices.first(where: { $0.id == defaultID }) {
            onOutputChanged?(d.name)
        }
    }

    func select(_ id: AudioDeviceID) {
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var value = id
        AudioObjectSetPropertyData(system, &addr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &value)
        reload(announce: false)
    }

    static func defaultOutput() -> AudioDeviceID {
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func outputDevices() -> [AudioDevice] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { return nil }
            var nameAddr = address(kAudioObjectPropertyName)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &name) == noErr,
                  let cf = name?.takeRetainedValue() else { return nil }
            return AudioDevice(id: id, name: cf as String)
        }
    }

    // Volume: main element when present, otherwise channel 1.
    private func volumeAddresses(_ id: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        var out: [AudioObjectPropertyAddress] = []
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element in [kAudioObjectPropertyElementMain, 1] as [AudioObjectPropertyElement] {
                var a = Self.address(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
                if AudioObjectHasProperty(id, &a) { out.append(a); break }
            }
        }
        return out
    }

    private func watchVolume(of id: AudioDeviceID) {
        if watchedDevice != 0 {
            for var a in volumeAddresses(watchedDevice) {
                AudioObjectRemovePropertyListenerBlock(watchedDevice, &a, .main, volumeListener)
            }
        }
        watchedDevice = id
        for var a in volumeAddresses(id) {
            AudioObjectAddPropertyListenerBlock(id, &a, .main, volumeListener)
        }
        lastVolume = readVolume()
    }

    private func readVolume() -> (Float, Bool)? {
        var volume: Float32 = 0
        var muted: UInt32 = 0
        var got = false
        for var a in volumeAddresses(watchedDevice) {
            if a.mSelector == kAudioDevicePropertyVolumeScalar {
                var size = UInt32(MemoryLayout<Float32>.size)
                got = AudioObjectGetPropertyData(watchedDevice, &a, 0, nil, &size, &volume) == noErr
            } else {
                var size = UInt32(MemoryLayout<UInt32>.size)
                AudioObjectGetPropertyData(watchedDevice, &a, 0, nil, &size, &muted)
            }
        }
        return got ? (volume, muted != 0) : nil
    }

    private func volumeChanged() {
        guard let v = readVolume() else { return }
        if let last = lastVolume, abs(last.0 - v.0) < 0.001, last.1 == v.1 { return }
        lastVolume = v
        onVolume?(v.0, v.1)
    }
}

// MARK: Brightness

/// Built-in display brightness via the public IOKit display API (works on Intel Macs).
/// Samples only after a brightness key press (no polling while idle), so changes made from
/// Control Center or auto-brightness do not show a HUD. The display service is looked up once.
final class BrightnessMonitor {
    private let onChange: (Double) -> Void
    private let isEnabled: () -> Bool
    private var last: Double?
    private var monitor: Any?
    private var service: io_service_t = 0
    private var paused = false

    private(set) var isAvailable = false

    init(isEnabled: @escaping () -> Bool, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        self.isEnabled = isEnabled
        service = Self.findService()
        last = read()
        isAvailable = last != nil
        guard isAvailable else { return } // Apple Silicon: IODisplay brightness is not readable.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8 else { return }
            let key = (event.data1 & 0xFFFF0000) >> 16
            if key == 2 || key == 3 { // NX_KEYTYPE_BRIGHTNESS_UP / DOWN
                // The display ramps to the new level; read once early and once when settled.
                for delay in [0.05, 0.3] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.sample() }
                }
            }
        }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.paused = true
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.paused = false
            self?.last = self?.read()
        }
    }

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    private func sample() {
        guard !paused, isEnabled(), let value = read() else { return }
        if let last, abs(last - value) < 0.004 { return }
        last = value
        onChange(value)
    }

    private func read() -> Double? {
        guard service != 0 else { return nil }
        var value: Float = 0
        let result = IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value)
        return result == kIOReturnSuccess ? Double(value) : nil
    }

    /// First display service that reports brightness (retained; released in deinit).
    private static func findService() -> io_service_t {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else { return 0 }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            var value: Float = 0
            if IODisplayGetFloatParameter(service, 0, kIODisplayBrightnessKey as CFString, &value) == kIOReturnSuccess {
                return service
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return 0
    }
}
