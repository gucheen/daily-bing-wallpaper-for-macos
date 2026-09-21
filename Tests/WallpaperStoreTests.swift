import AppKit
import CoreImage
import Foundation

@main
struct WallpaperStoreTests {
    static func main() throws {
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
        print("PASS: scheduling, dark rendering, original preservation, cache round trip, invalid image")
    }
}
