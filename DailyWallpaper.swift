import AppKit
import Foundation

struct Wallpaper: Decodable {
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

enum WallpaperError: Error {
    case invalidHTTPResponse
    case httpStatus(Int)
    case invalidImage
}

@main
struct DailyWallpaper {
    @MainActor
    static func main() async {
        do {
            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.timeZone = .current
            dateFormatter.dateFormat = "yyyy-MM-dd"

            var components = URLComponents(
                string: "https://bing.wdbyte.com/today"
            )!
            components.queryItems = [
                URLQueryItem(
                    name: "date",
                    value: dateFormatter.string(from: Date())
                )
            ]
            let endpoint = components.url!

            var request = URLRequest(
                url: endpoint,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 30
            )

            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

            let (jsonData, response) = try await URLSession.shared.data(
                for: request
            )

            guard let httpResponse = response as? HTTPURLResponse else {
                throw WallpaperError.invalidHTTPResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw WallpaperError.httpStatus(httpResponse.statusCode)
            }

            let wallpaper = try JSONDecoder().decode(
                Wallpaper.self,
                from: jsonData
            )

            let (imageData, imageResponse) = try await URLSession.shared.data(
                from: wallpaper.url
            )

            guard
                let imageHTTPResponse = imageResponse as? HTTPURLResponse,
                (200...299).contains(imageHTTPResponse.statusCode)
            else {
                throw WallpaperError.invalidHTTPResponse
            }

            guard NSImage(data: imageData) != nil else {
                throw WallpaperError.invalidImage
            }

            let directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(
                    "Library/Application Support/DailyWallpaper",
                    isDirectory: true
                )

            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            // 防止接口中的文件名意外包含目录路径。
            let safeFileName = URL(fileURLWithPath: wallpaper.fileName)
                .lastPathComponent

            let imageURL = directory.appendingPathComponent(safeFileName)

            if !FileManager.default.fileExists(atPath: imageURL.path) {
                try imageData.write(to: imageURL, options: .atomic)
            }

            for screen in NSScreen.screens {
                let options =
                    NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]

                try NSWorkspace.shared.setDesktopImageURL(
                    imageURL,
                    for: screen,
                    options: options
                )
            }

            print("壁纸更新成功：\(wallpaper.date)")
            print(wallpaper.desc)
            print("保存位置：\(imageURL.path)")
        } catch {
            fputs("壁纸更新失败：\(error)\n", stderr)
            exit(1)
        }
    }
}
