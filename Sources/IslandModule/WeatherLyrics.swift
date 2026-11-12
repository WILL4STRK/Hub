import CoreLocation
import Foundation

// MARK: Weather (Open-Meteo, free, no key)

struct WeatherNow: Codable, Equatable {
    let temperature: Double
    let code: Int
    let isDay: Bool
    let unit: String
    let fetched: Date

    var symbol: String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    var text: String { "\(Int(temperature.rounded()))°" }
}

/// Approximate location from CoreLocation, weather from Open-Meteo, cached for 30 minutes.
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var now: WeatherNow?
    @Published private(set) var status = "Off"

    private let settings: AppSettings
    private let manager = CLLocationManager()
    private let cacheKey = "weatherCache"
    private var inFlight = false
    static let maxAge: TimeInterval = 30 * 60

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(WeatherNow.self, from: data) {
            now = cached
        }
    }

    /// Fetches only when enabled and the cache is older than 30 minutes.
    func refreshIfStale() {
        guard settings.showWeather, !inFlight else { return }
        if let now, Date().timeIntervalSince(now.fetched) < Self.maxAge { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            status = "Waiting for location permission"
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            status = "Location access denied"
        default:
            inFlight = true
            status = "Locating…"
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .notDetermined, .denied, .restricted: break
        default: refreshIfStale()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { inFlight = false; return }
        fetch(latitude: c.latitude, longitude: c.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        inFlight = false
        status = "Location unavailable: \(error.localizedDescription)"
    }

    private func fetch(latitude: Double, longitude: Double) {
        let fahrenheit = Locale.current.measurementSystem == .us
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        // Rounded to ~1 km; Open-Meteo needs nothing finer.
        c.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        URLSession.shared.dataTask(with: c.url!) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight = false
                guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let current = json["current"] as? [String: Any],
                      let temp = (current["temperature_2m"] as? NSNumber)?.doubleValue else {
                    self.status = "Weather unavailable: \(error?.localizedDescription ?? "bad response")"
                    return
                }
                let w = WeatherNow(temperature: temp,
                                   code: (current["weather_code"] as? NSNumber)?.intValue ?? 3,
                                   isDay: (current["is_day"] as? NSNumber)?.intValue != 0,
                                   unit: fahrenheit ? "F" : "C",
                                   fetched: Date())
                self.now = w
                self.status = "Updated"
                if let data = try? JSONEncoder().encode(w) {
                    UserDefaults.standard.set(data, forKey: self.cacheKey)
                }
            }
        }.resume()
    }
}

// MARK: Lyrics (LRCLIB, free)

struct LyricLine: Equatable {
    let time: Double
    let text: String
}

/// Synced lyrics from LRCLIB, one lookup per track, with exponential backoff on provider errors.
final class LyricsService: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var status = "Idle"

    private let settings: AppSettings
    private var cache: [String: [LyricLine]] = [:]
    private var currentKey: String?
    private var backoff: TimeInterval = 30
    private var retryAfter = Date.distantPast

    init(settings: AppSettings) {
        self.settings = settings
    }

    func update(for info: NowPlayingInfo?) {
        guard settings.showLyrics, let info, !info.title.isEmpty else {
            if !lines.isEmpty { lines = [] }
            currentKey = nil
            return
        }
        let key = "\(info.artist)|\(info.title)"
        guard key != currentKey else { return }
        currentKey = key
        if let hit = cache[key] {
            lines = hit
            return
        }
        lines = []
        guard Date() >= retryAfter else {
            status = "Waiting after provider error"
            currentKey = nil // try again on a later update
            return
        }
        fetch(key: key, title: Self.clean(info.title), artist: Self.clean(info.artist),
              album: Self.clean(info.album), duration: info.duration)
    }

    /// Current line at a playback position.
    func line(at position: Double) -> String? {
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        guard let found else { return nil }
        let text = lines[found].text
        return text.isEmpty ? nil : text
    }

    /// Removes suffixes like " - Remastered 2011" or "(Live)" that break exact matches.
    static func clean(_ s: String) -> String {
        let words = "remaster|remastered|live|version|edit|mono|stereo|deluxe|mix|bonus|anniversary|feat\\.?|ft\\."
        var out = s
        for pattern in ["\\s+-\\s+[^-]*(\(words))[^-]*$", "\\s*[\\(\\[][^\\)\\]]*(\(words))[^\\)\\]]*[\\)\\]]"] {
            out = out.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    private func fetch(key: String, title: String, artist: String, album: String, duration: Double) {
        status = "Looking up lyrics"
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded()))),
        ]
        request(get.url!) { [weak self] result in
            guard let self else { return }
            switch result {
            case .found(let json):
                self.finish(key: key, synced: (json as? [String: Any])?["syncedLyrics"] as? String)
            case .notFound:
                // Exact match failed (often a duration mismatch); fall back to search.
                var search = URLComponents(string: "https://lrclib.net/api/search")!
                search.queryItems = [URLQueryItem(name: "track_name", value: title),
                                     URLQueryItem(name: "artist_name", value: artist)]
                self.request(search.url!) { result in
                    switch result {
                    case .found(let json):
                        let hit = (json as? [[String: Any]])?.first { ($0["syncedLyrics"] as? String)?.isEmpty == false }
                        self.finish(key: key, synced: hit?["syncedLyrics"] as? String)
                    case .notFound:
                        self.finish(key: key, synced: nil)
                    case .failed(let why):
                        self.failed(key: key, why: why)
                    }
                }
            case .failed(let why):
                self.failed(key: key, why: why)
            }
        }
    }

    private enum Result { case found(Any), notFound, failed(String) }

    private func request(_ url: URL, completion: @escaping (Result) -> Void) {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Awning/0.1.0 (macOS menu-bar app)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result: Result
            if code == 200, let data, let json = try? JSONSerialization.jsonObject(with: data) {
                result = .found(json)
            } else if code == 404 {
                result = .notFound
            } else {
                result = .failed(error?.localizedDescription ?? "HTTP \(code)")
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private func finish(key: String, synced: String?) {
        backoff = 30
        let parsed = synced.map(Self.parse) ?? []
        if cache.count >= 60 { cache.removeAll(keepingCapacity: true) } // bounded: about one listening session
        cache[key] = parsed
        status = parsed.isEmpty ? "No synced lyrics" : "Lyrics loaded"
        if key == currentKey { lines = parsed }
    }

    private func failed(key: String, why: String) {
        retryAfter = Date().addingTimeInterval(backoff)
        status = "Provider error (\(why)); retry in \(Int(backoff)) s"
        backoff = min(backoff * 2, 30 * 60)
        if key == currentKey { currentKey = nil }
    }

    /// Parses "[mm:ss.xx] text" lines.
    static func parse(_ lrc: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in lrc.split(separator: "\n") {
            let line = String(raw)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let stamp = line[line.index(after: line.startIndex)..<close]
            let parts = stamp.split(separator: ":")
            guard parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) else { continue }
            let text = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            out.append(LyricLine(time: m * 60 + s, text: text))
        }
        return out.sorted { $0.time < $1.time }
    }
}
