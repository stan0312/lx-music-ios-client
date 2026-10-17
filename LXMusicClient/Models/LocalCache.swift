import Foundation
import UIKit

/// 本地缓存：图片（持久化到磁盘，重开 App 不再重复下载）+ 歌曲（可选开关，仿 lx-music Web 端“设置→缓存”）
/// - 图片缓存：始终开启，按 URL 哈希落盘，跨启动持久
/// - 歌曲缓存：`enableSongCache` 开关（对应 Web 端 cache.enableCache），开时把已播放歌曲流下载到本地，
///   再次播放同一首歌直接读本地文件，避免重复走网络
final class LocalCache {
    static let shared = LocalCache()

    private let fm = FileManager.default
    private var cacheRoot: URL {
        fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LXCache", isDirectory: true)
    }
    private var imageDir: URL { cacheRoot.appendingPathComponent("images", isDirectory: true) }
    private var songDir: URL { cacheRoot.appendingPathComponent("songs", isDirectory: true) }

    /// 歌曲缓存开关（对应 lx-music Web 端 cache.enableCache）
    static var enableSongCache: Bool {
        get { UserDefaults.standard.bool(forKey: "lx.enableSongCache") }
        set { UserDefaults.standard.set(newValue, forKey: "lx.enableSongCache") }
    }

    private init() {
        try? fm.createDirectory(at: imageDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: songDir, withIntermediateDirectories: true)
    }

    /// 稳定字符串哈希（64 位 FNV-1a，十六进制）
    private func key(for s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        return String(h, radix: 16)
    }

    // MARK: - 图片缓存

    func cachedImage(for url: String) -> UIImage? {
        let u = imageDir.appendingPathComponent(key(for: url) + ".img")
        guard let d = try? Data(contentsOf: u) else { return nil }
        return UIImage(data: d)
    }

    func saveImage(_ data: Data, for url: String) {
        let u = imageDir.appendingPathComponent(key(for: url) + ".img")
        try? data.write(to: u)
    }

    // MARK: - 歌曲缓存

    private func songFileURL(for song: Song) -> URL {
        // 同一首歌（id）固定缓存文件，扩展名统一用 .mp3（AVPlayer 按数据流播放不依赖扩展名）
        songDir.appendingPathComponent(key(for: song.id) + ".mp3")
    }

    /// 已缓存的本地歌曲文件（不存在返回 nil）
    func cachedSongURL(for song: Song) -> URL? {
        guard LocalCache.enableSongCache else { return nil }
        let u = songFileURL(for: song)
        return (try? u.checkResourceIsReachable()) == true ? u : nil
    }

    func saveSong(_ data: Data, for song: Song) {
        guard LocalCache.enableSongCache else { return }
        try? data.write(to: songFileURL(for: song))
    }

    /// 后台把音频流下载到本地缓存（幂等：已有缓存则跳过），供下次直接播放
    func cacheAudio(from url: URL, for song: Song) {
        guard LocalCache.enableSongCache else { return }
        guard cachedSongURL(for: song) == nil else { return }
        let fileURL = songFileURL(for: song)
        URLSession.shared.dataTask(with: url) { data, resp, err in
            guard let data, !data.isEmpty, err == nil else { return }
            if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) { return }
            try? data.write(to: fileURL)
        }.resume()
    }

    // MARK: - 统计与清理

    /// 总缓存大小（字节）
    func totalSizeBytes() -> Int {
        func dirSize(_ dir: URL) -> Int {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
            var sum = 0
            for f in files {
                sum += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
            return sum
        }
        return dirSize(imageDir) + dirSize(songDir)
    }

    func sizeText() -> String {
        let bytes = totalSizeBytes()
        if bytes >= 1024 * 1024 * 1024 { return String(format: "%.2f GB", Double(bytes) / 1_073_741_824) }
        if bytes >= 1024 * 1024 { return String(format: "%.1f MB", Double(bytes) / 1_048_576) }
        if bytes >= 1024 { return String(format: "%.0f KB", Double(bytes) / 1024) }
        return "0 B"
    }

    func clear() {
        try? fm.removeItem(at: cacheRoot)
        try? fm.createDirectory(at: imageDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: songDir, withIntermediateDirectories: true)
        URLCache.shared.removeAllCachedResponses()
    }
}
