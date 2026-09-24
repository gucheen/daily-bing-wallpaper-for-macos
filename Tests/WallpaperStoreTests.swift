import AppKit
import CoreImage
import Foundation

@main
struct WallpaperStoreTests {
    static func main() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        func date(_ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        }
        func due(_ last: Date?, _ now: Date) -> Bool {
            WallpaperStore.refreshIsDue(lastRefresh: last, now: now, calendar: calendar)
        }
        precondition(due(nil, date(21, 8)))
        precondition(!due(date(20, 9), date(21, 8)))
        precondition(due(date(20, 9), date(21, 9)))
        precondition(due(date(21, 8), date(21, 9)))
        precondition(!due(date(21, 9), date(21, 18)))
        precondition(due(date(19, 9), date(21, 18)))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = CIContext()
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let source = CIImage(color: CIColor(red: 0.9, green: 0.8, blue: 0.7))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 32))
        let data = context.pngRepresentation(of: source, format: .RGBA8, colorSpace: colorSpace)!
        let wallpaper = Wallpaper(fileName: "../../outside.png", url: URL(string: "https://example.com/test.png")!,
                                  date: "2026-09-21", region: "cn", desc: "Test")
        let cached = try WallpaperStore.prepare(wallpaper, data: data, in: directory, now: date(21, 9))
        let savedOriginal = try Data(contentsOf: cached.imageURL(in: directory, dark: false))
        precondition(savedOriginal == data)
        let dark = CIImage(contentsOf: cached.imageURL(in: directory, dark: true))!
        precondition(dark.extent.size == source.extent.size)
        func pixel(_ image: CIImage) -> [UInt8] {
            var result = [UInt8](repeating: 0, count: 4)
            context.render(image, toBitmap: &result, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: colorSpace)
            return result
        }
        let originalPixel = pixel(source)
        let darkPixel = pixel(dark)
        precondition((0..<3).allSatisfy { darkPixel[$0] < originalPixel[$0] && darkPixel[$0] > 0 })
        let restored = try JSONDecoder().decode(CachedWallpaper.self, from: JSONEncoder().encode(cached))
        precondition(restored.originalName == cached.originalName && restored.refreshedAt == cached.refreshedAt)
        precondition(!cached.originalName.contains("/"))
        do {
            _ = try WallpaperStore.prepare(wallpaper, data: Data("invalid".utf8), in: directory, now: Date())
            fatalError("Invalid image was accepted")
        } catch WallpaperError.invalidImage { }
        func remote(_ day: String, name: String = "../../outside.png",
                    url: String = "https://example.com/test.png") -> Wallpaper {
            Wallpaper(fileName: name, url: URL(string: url)!, date: day, region: "cn", desc: "Updated")
        }
        var requests: [URL] = []
        let evening = date(21, 18)
        func fetch(_ wallpaper: Wallpaper, current: CachedWallpaper? = cached,
                   now: Date = evening, imageData: Data = data) async throws -> CachedWallpaper {
            requests = []
            return try await WallpaperStore.fetch(in: directory, current: current, now: now,
                                                 calendar: calendar) { url in
                requests.append(url)
                if url.host == "bing.wdbyte.com" {
                    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
                    precondition(query.first?.value == (now == date(22, 9) ? "2026-09-22" : "2026-09-21"))
                    return try JSONEncoder().encode(wallpaper)
                }
                return imageData
            }
        }
        for staleDate in ["2026-09-20", "invalid", "2026-09-31", "2026-9-22"] {
            do {
                _ = try await fetch(remote(staleDate))
                fatalError("Stale or invalid date was accepted")
            } catch WallpaperError.wallpaperNotUpdated { }
            precondition(requests.count == 1)
        }
        let unchanged = try await fetch(remote("2026-09-21"))
        precondition(requests.count == 1)
        precondition(unchanged.originalName == cached.originalName && unchanged.darkName == cached.darkName)
        precondition(unchanged.refreshedAt == date(21, 18) && unchanged.wallpaper.desc == "Updated")
        do {
            _ = try await fetch(remote("2026-09-22"), now: date(22, 9))
            fatalError("Changed date with old photo was accepted")
        } catch WallpaperError.wallpaperNotUpdated { }
        precondition(requests.count == 1)
        do {
            _ = try await fetch(remote("2026-09-22", name: "new.png", url: "https://example.com/new.png"),
                                now: date(22, 9))
            fatalError("Changed URL with identical old image was accepted")
        } catch WallpaperError.wallpaperNotUpdated { }
        precondition(requests.count == 2)
        precondition(cached.refreshedAt == date(21, 9) && due(cached.refreshedAt, date(22, 9)))
        let newSource = CIImage(color: CIColor(red: 0.2, green: 0.5, blue: 0.8))
            .cropped(to: source.extent)
        let newData = context.pngRepresentation(of: newSource, format: .RGBA8, colorSpace: colorSpace)!
        let early = try await fetch(remote("2026-09-23", name: "early.png", url: "https://example.com/early.png"),
                                    imageData: newData)
        precondition(requests.count == 2 && early.originalName != cached.originalName)
        precondition(early.wallpaper.date == "2026-09-23" && early.refreshedAt == evening)
        for now in [evening, date(22, 9)] {
            let reused = try await fetch(early.wallpaper, current: early, now: now, imageData: newData)
            precondition(requests.count == 1 && reused.originalName == early.originalName)
            precondition(reused.refreshedAt == now)
        }
        let earlyMoved = try await fetch(remote("2026-09-23", name: "moved.png", url: "https://example.com/moved.png"),
                                         current: early, imageData: newData)
        precondition(requests.count == 2 && earlyMoved.originalName == early.originalName)
        for olderDate in ["2026-09-21", "2026-09-22"] {
            do {
                _ = try await fetch(remote(olderDate), current: early)
                fatalError("Earlier wallpaper replaced a future wallpaper")
            } catch WallpaperError.wallpaperNotUpdated { }
            precondition(requests.count == 1)
        }
        let earlyFirst = try await fetch(early.wallpaper, current: nil, imageData: newData)
        precondition(requests.count == 2 && earlyFirst.wallpaper.date == "2026-09-23")
        try FileManager.default.removeItem(at: early.imageURL(in: directory, dark: true))
        let earlyRepaired = try await fetch(early.wallpaper, current: early, imageData: newData)
        precondition(requests.count == 2 && earlyRepaired.originalName != early.originalName)
        precondition(FileManager.default.fileExists(atPath: earlyRepaired.imageURL(in: directory, dark: true).path))
        let updated = try await fetch(remote("2026-09-22", name: "new.png", url: "https://example.com/new.png"),
                                      now: date(22, 9), imageData: newData)
        precondition(requests.count == 2 && updated.originalName != cached.originalName)
        precondition(updated.wallpaper.date == "2026-09-22" && updated.refreshedAt == date(22, 9))
        let first = try await fetch(remote("2026-09-21"), current: nil)
        precondition(requests.count == 2 && first.wallpaper.date == "2026-09-21")
        let moved = try await fetch(remote("2026-09-21", url: "https://example.com/moved.png"))
        precondition(requests.count == 2 && moved.originalName == cached.originalName)
        try FileManager.default.removeItem(at: cached.imageURL(in: directory, dark: true))
        let repaired = try await fetch(remote("2026-09-21"))
        precondition(requests.count == 2 && repaired.originalName != cached.originalName)
        precondition(FileManager.default.fileExists(atPath: repaired.imageURL(in: directory, dark: true).path))
        print("PASS: scheduling, rendering, cache, invalid image, date validation, photo comparison, cache repair")
    }
}
