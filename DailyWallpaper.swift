import AppKit
import CoreImage
import Darwin
import Foundation

struct Wallpaper: Codable {
    let fileName: String
    let url: URL
    let date: String
    let region: String
    let desc: String

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case url, date, region, desc
    }
}

struct CachedWallpaper: Codable {
    let wallpaper: Wallpaper
    let originalName: String
    let darkName: String
    let refreshedAt: Date

    func imageURL(in directory: URL, dark: Bool) -> URL {
        directory.appendingPathComponent(dark ? darkName : originalName)
    }
}

enum WallpaperError: Error {
    case invalidHTTPResponse
    case httpStatus(Int)
    case invalidImage
}

enum WallpaperStore {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DailyWallpaper", isDirectory: true)

    static func fetch(in directory: URL, now: Date = Date()) async throws -> CachedWallpaper {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(string: "https://bing.wdbyte.com/today")!
        components.queryItems = [URLQueryItem(name: "date", value: formatter.string(from: now))]
        let wallpaper = try JSONDecoder().decode(Wallpaper.self, from: await download(components.url!))
        let data = try await download(wallpaper.url)
        return try prepare(wallpaper, data: data, in: directory, now: now)
    }

    static func download(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 60)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw WallpaperError.invalidHTTPResponse
        }
        guard (200...299).contains(response.statusCode) else {
            throw WallpaperError.httpStatus(response.statusCode)
        }
        return data
    }

    static func prepare(_ wallpaper: Wallpaper, data: Data, in directory: URL,
                        now: Date) throws -> CachedWallpaper {
        guard let image = CIImage(data: data, options: [.applyOrientationProperty: true]),
              !image.extent.isEmpty, !image.extent.isInfinite else {
            throw WallpaperError.invalidImage
        }
        let dark = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
            "inputHighlightAmount": 0.65, "inputShadowAmount": 0.0
        ]).applyingFilter("CIExposureAdjust", parameters: ["inputEV": -0.65])
        guard let darkData = CIContext().jpegRepresentation(of: dark,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.95]) else {
            throw WallpaperError.invalidImage
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 每次更新使用独立文件名，避免桌面继续显示系统缓存中的旧图片。
        let identifier = UUID().uuidString
        let originalName = "\(identifier)-original.\(wallpaper.url.pathExtension.lowercased() == "png" ? "png" : "jpg")"
        let darkName = "\(identifier)-dark.jpg"
        try data.write(to: directory.appendingPathComponent(originalName), options: .atomic)
        try darkData.write(to: directory.appendingPathComponent(darkName), options: .atomic)
        return CachedWallpaper(wallpaper: wallpaper, originalName: originalName,
                               darkName: darkName, refreshedAt: now)
    }

    static func refreshIsDue(lastRefresh: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastRefresh else { return true }
        guard let scheduled = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now) else { return false }
        return now >= scheduled && lastRefresh < scheduled
    }
}

@MainActor
final class WallpaperApplication: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let detailItem = NSMenuItem(title: "正在加载壁纸…", action: nil, keyEquivalent: "")
    private let modeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var refreshItem: NSMenuItem!
    private var appearanceObservation: NSKeyValueObservation?
    private var timer: Timer?
    private var current: CachedWallpaper?
    private var updating = false
    private var retryAfter = Date.distantPast
    private var needsRetry = false
    private var lastAppliedDark: Bool?
    private var lockDescriptor: Int32 = -1
    private let directory = WallpaperStore.directory
    private var manifestURL: URL { directory.appendingPathComponent("current.json") }
    private var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            lockDescriptor = open(directory.appendingPathComponent("application.lock").path,
                                  O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
            guard lockDescriptor >= 0 else { throw POSIXError(.EACCES) }
            guard flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                log("应用已在运行")
                NSApp.terminate(nil)
                return
            }
        } catch {
            log("启动失败：\(error)")
            NSApp.terminate(nil)
            return
        }
        configureMenu()
        if let data = try? Data(contentsOf: manifestURL),
           let cached = try? JSONDecoder().decode(CachedWallpaper.self, from: data),
           [false, true].allSatisfy({ FileManager.default.fileExists(atPath: cached.imageURL(in: directory, dark: $0).path) }) {
            current = cached
            applyCurrent()
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.applyCurrent() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceChanged),
            name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(workspaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(workspaceChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        timer = Timer(timeInterval: 60, target: self, selector: #selector(checkForUpdate), userInfo: nil, repeats: true)
        timer?.tolerance = 5
        RunLoop.main.add(timer!, forMode: .common)
        checkForUpdate()
    }

    private func configureMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "每日壁纸")
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.autoenablesItems = false
        detailItem.isEnabled = false
        modeItem.isEnabled = false
        menu.addItem(detailItem)
        menu.addItem(modeItem)
        menu.addItem(.separator())
        refreshItem = menu.addItem(withTitle: "立即更新壁纸", action: #selector(refreshNow), keyEquivalent: "")
        refreshItem.target = self
        menu.addItem(withTitle: "打开壁纸目录", action: #selector(openDirectory), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "关于每日壁纸", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "退出每日壁纸", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        updateMenu()
    }

    @objc private func refreshNow() { refresh() }
    @objc private func openDirectory() { NSWorkspace.shared.open(directory) }
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func workspaceChanged() {
        applyCurrent()
        checkForUpdate()
    }

    @objc private func checkForUpdate() {
        if lastAppliedDark != isDark { applyCurrent() }
        guard Date() >= retryAfter else { return }
        if needsRetry || WallpaperStore.refreshIsDue(lastRefresh: current?.refreshedAt, now: Date()) {
            refresh()
        }
    }

    private func refresh() {
        guard !updating else { return }
        updating = true
        refreshItem.isEnabled = false
        detailItem.title = "正在更新壁纸…"
        Task {
            defer {
                updating = false
                refreshItem.isEnabled = true
            }
            do {
                let directory = self.directory
                // 图片解码与渲染放在后台，避免阻塞菜单和系统外观事件。
                let cached = try await Task.detached(priority: .utility) {
                    try await WallpaperStore.fetch(in: directory)
                }.value
                try JSONEncoder().encode(cached).write(to: manifestURL, options: .atomic)
                current = cached
                needsRetry = false
                retryAfter = .distantPast
                applyCurrent()
                log("壁纸下载成功：\(cached.wallpaper.date) \(cached.wallpaper.desc)")
            } catch {
                needsRetry = true
                retryAfter = Date().addingTimeInterval(10 * 60)
                detailItem.title = "更新失败，10 分钟后重试"
                log("壁纸更新失败：\(error)")
            }
        }
    }

    private func applyCurrent() {
        updateMenu()
        guard let current else { return }
        let dark = isDark
        var succeeded = !NSScreen.screens.isEmpty
        for screen in NSScreen.screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(current.imageURL(in: directory, dark: dark),
                    for: screen, options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:])
            } catch {
                succeeded = false
                log("设置桌面失败：\(error)")
            }
        }
        lastAppliedDark = succeeded ? dark : nil
        if !succeeded { detailItem.title = "设置桌面失败，将自动重试" }
    }

    private func updateMenu() {
        modeItem.title = isDark ? "跟随系统：深色壁纸" : "跟随系统：原始壁纸"
        if let current {
            detailItem.title = "今日壁纸：\(current.wallpaper.date)"
            statusItem.button?.toolTip = current.wallpaper.desc
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        appearanceObservation?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        if lockDescriptor >= 0 { close(lockDescriptor) }
    }

    private func log(_ message: String) {
        print("[\(ISO8601DateFormatter().string(from: Date()))] \(message)")
        fflush(stdout)
    }
}

#if !WALLPAPER_TESTING
@main
struct DailyWallpaper {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = WallpaperApplication()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif
