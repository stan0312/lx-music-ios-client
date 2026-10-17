import Foundation

/// 下载管理器：把歌曲音频存到 文档/LXDownloads，文件名按模板（歌名/歌手），可选写 .lrc 歌词
enum DownloadManager {
    static var fileNameTemplate: String {
        get { UserDefaults.standard.string(forKey: "lx.downloadFileName") ?? "歌名 - 歌手" }
        set { UserDefaults.standard.set(newValue, forKey: "lx.downloadFileName") }
    }
    static var writeLyric: Bool {
        get { UserDefaults.standard.bool(forKey: "lx.downloadWriteLyric") }
        set { UserDefaults.standard.set(newValue, forKey: "lx.downloadWriteLyric") }
    }

    static var downloadsDir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LXDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func sizeText() -> String {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: downloadsDir,
                                                      includingPropertiesForKeys: [.fileSizeKey]) else { return "0 MB" }
        let total = items.reduce(Int64(0)) { sum, u in
            let size = (try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
        return ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
    }

    static func sanitize(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return s.components(separatedBy: invalid).joined(separator: "")
    }

    static func filename(for song: Song, ext: String) -> String {
        let t = fileNameTemplate
            .replacingOccurrences(of: "歌名", with: song.name.isEmpty ? "未知歌名" : song.name)
            .replacingOccurrences(of: "歌手", with: song.singer.isEmpty ? "未知歌手" : song.singer)
        return sanitize(t) + "." + ext
    }

    static func download(song: Song, url: URL, lyric: String?) async -> Result<String, Error> {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
            let fileURL = downloadsDir.appendingPathComponent(filename(for: song, ext: ext))
            try data.write(to: fileURL, options: .atomic)
            if writeLyric, let lyric, !lyric.isEmpty {
                let lrcURL = downloadsDir.appendingPathComponent(filename(for: song, ext: "lrc"))
                try lyric.data(using: .utf8)?.write(to: lrcURL, options: .atomic)
            }
            return .success(fileURL.lastPathComponent)
        } catch {
            return .failure(error)
        }
    }
}
