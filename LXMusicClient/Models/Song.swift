import Foundation

// MARK: - 通用 JSON 容错解码辅助
// lxserver 各平台返回结构不完全一致，这里统一做多路径容错提取。

func stringValue(_ d: Any?) -> String? {
    guard let d = d else { return nil }
    if let s = d as? String { return s }
    if let n = d as? Int { return String(n) }
    if let n = d as? Int64 { return String(n) }
    if let n = d as? Double { return String(n) }
    if let b = d as? Bool { return b ? "1" : "0" }
    return nil
}

func doubleValue(_ d: Any?) -> Double? {
    if let n = d as? Double { return n }
    if let n = d as? Int { return Double(n) }
    if let n = d as? Int64 { return Double(n) }
    if let s = d as? String { return Double(s) }
    return nil
}

func arrayValue(_ d: Any?) -> [Any]? {
    if let a = d as? [Any] { return a }
    return nil
}

/// 从嵌套字典中按 key 路径取值
func deepGet(_ obj: Any, _ path: [String]) -> Any? {
    var cur: Any = obj
    for key in path {
        guard let dict = cur as? [String: Any], let v = dict[key] else { return nil }
        cur = v
    }
    return cur
}

/// 从响应 JSON 中提取“歌曲数组”，兼容多种容器结构
func extractSongs(_ json: Any) -> [Song] {
    let candidates: [[String]] = [
        ["data", "list"], ["list"], ["songs"], ["data", "songs"],
        ["data", "musicList"], ["musicList"], ["result", "list"],
    ]
    for path in candidates {
        if let arr = arrayValue(deepGet(json, path)) {
            let songs = arr.compactMap { Song(json: $0) }
            if !songs.isEmpty { return songs }
        }
    }
    return []
}

// MARK: - 歌曲模型（LX Music 风格）

struct Song: Identifiable, Hashable {
    var id: String
    var name: String
    var singer: String
    var source: String      // kw/kg/tx/wy/mg/…
    var albumName: String?
    var albumPic: String?
    var interval: Double?   // 时长（秒）
    var quality: String?
    var size: String?
    var lrc: String?
    var url: String?        // 已解析直链
    var customFilename: String? // 自定义目录歌曲的相对路径（source == "custom" 时使用）
    // 各平台真实 ID（评论/播放/歌词需要完整 songInfo 才能命中）
    var songmid: String?
    var hash: String?
    var mid: String?
    var albumId: String?

    /// 是否为“自定义目录”歌曲（由本地服务器目录提供音频）
    var isCustom: Bool { source == "custom" }

    init(
        id: String, name: String, singer: String, source: String,
        albumName: String? = nil, albumPic: String? = nil,
        interval: Double? = nil, quality: String? = nil,
        size: String? = nil, lrc: String? = nil, url: String? = nil,
        customFilename: String? = nil,
        songmid: String? = nil, hash: String? = nil,
        mid: String? = nil, albumId: String? = nil
    ) {
        self.id = id; self.name = name; self.singer = singer
        self.source = source; self.albumName = albumName; self.albumPic = albumPic
        self.interval = interval; self.quality = quality
        self.size = size; self.lrc = lrc; self.url = url
        self.customFilename = customFilename
        self.songmid = songmid; self.hash = hash; self.mid = mid; self.albumId = albumId
    }

    /// 容错解析
    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        guard let rawName = stringValue(deepGet(d, ["name"])), !rawName.isEmpty else { return nil }

        var sid = stringValue(deepGet(d, ["id"]))
        // lxserver 榜单/歌单/搜索常用多种 ID，需逐个兜底
        if sid == nil { sid = stringValue(deepGet(d, ["songmid"])) }
        if sid == nil { sid = stringValue(deepGet(d, ["songId"])) }
        if sid == nil { sid = stringValue(deepGet(d, ["mid"])) }
        if sid == nil { sid = stringValue(deepGet(d, ["hash"])) }
        if sid == nil { sid = stringValue(deepGet(d, ["copyrightId"])) }
        if sid == nil { sid = stringValue(deepGet(d, ["strMediaMid"])) }
        // id 可能是数组（多 id 优先第一个）
        if sid == nil, let arr = arrayValue(d["id"]) {
            sid = arr.first.flatMap(stringValue)
        }
        guard let id = sid, !id.isEmpty else { return nil }

        self.id = id
        self.name = rawName
        if let singerArr = d["singer"] as? [Any] {
            self.singer = singerArr.compactMap(stringValue).joined(separator: " / ")
        } else {
            self.singer = stringValue(deepGet(d, ["singer"])) ?? stringValue(deepGet(d, ["artist"])) ?? "未知歌手"
        }
        self.source = stringValue(deepGet(d, ["source"])) ?? "tx"
        self.albumName = stringValue(deepGet(d, ["albumName"])) ?? stringValue(deepGet(d, ["album"]))
        // 封面图多路径
        self.albumPic = firstPic(d)
        self.interval = doubleValue(deepGet(d, ["interval"])) ?? doubleValue(deepGet(d, ["duration"]))
        self.quality = stringValue(deepGet(d, ["quality"]))
        self.size = stringValue(deepGet(d, ["size"]))
        self.lrc = stringValue(deepGet(d, ["lrc"]))
        self.url = stringValue(deepGet(d, ["url"]))
        self.customFilename = stringValue(deepGet(d, ["customFilename"]))
        self.songmid = stringValue(deepGet(d, ["songmid"]))
        self.hash = stringValue(deepGet(d, ["hash"]))
        self.mid = stringValue(deepGet(d, ["mid"])) ?? stringValue(deepGet(d, ["strMediaMid"]))
        self.albumId = stringValue(deepGet(d, ["albumId"])) ?? stringValue(deepGet(d, ["album_id"]))
    }

    /// 发送给 lxserver 的完整 songInfo（评论/播放/歌词需要全字段才能命中）
    func songInfoPayload() -> [String: Any] {
        var d: [String: Any] = ["id": id, "name": name, "singer": singer, "source": source]
        if let m = songmid { d["songmid"] = m }
        if let h = hash { d["hash"] = h }
        if let md = mid { d["mid"] = md }
        if let aid = albumId { d["albumId"] = aid }
        if let iv = interval { d["interval"] = iv }
        if let an = albumName { d["albumName"] = an }
        if let pic = albumPic { d["img"] = pic }
        // meta：服务端 normalizeSongInfo 会从 meta 反推 hash/strMediaMid/albumMid 等 SDK 必需字段
        var meta: [String: Any] = [:]
        if let h = hash { meta["hash"] = h }
        if let md = mid { meta["strMediaMid"] = md }
        if let sid = songmid { meta["songId"] = sid }
        if let aid = albumId { meta["albumId"] = aid }
        if let iv = interval { meta["interval"] = iv }
        if let pic = albumPic { meta["picUrl"] = pic }
        d["meta"] = meta
        return d
    }

    /// 持久化用
    func toJSON() -> [String: Any] {
        var d: [String: Any] = [
            "id": id, "name": name, "singer": singer, "source": source,
        ]
        if let albumName { d["albumName"] = albumName }
        if let albumPic { d["albumPic"] = albumPic }
        if let interval { d["interval"] = interval }
        if let quality { d["quality"] = quality }
        if let customFilename { d["customFilename"] = customFilename }
        if let songmid { d["songmid"] = songmid }
        if let hash { d["hash"] = hash }
        if let mid { d["mid"] = mid }
        if let albumId { d["albumId"] = albumId }
        return d
    }

    private func firstPic(_ d: [String: Any]) -> String? {
        for path in [["albumPic"], ["pic"], ["albumPicUrl"], ["cover"], ["coverImgUrl"], ["picUrl"]] {
            if let s = stringValue(deepGet(d, path)), !s.isEmpty { return s }
        }
        return nil
    }

    var durationText: String {
        guard let sec = interval, sec > 0 else { return "--:--" }
        let t = Int(sec)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    var sourceName: String {
        switch source {
        case "kw": return "酷我"
        case "kg": return "酷狗"
        case "tx": return "QQ"
        case "wy": return "网易"
        case "mg": return "咪咕"
        default: return source.uppercased()
        }
    }

    var displaySubtitle: String {
        var parts: [String] = []
        if !singer.isEmpty { parts.append(singer) }
        if let q = quality, !q.isEmpty { parts.append(q) }
        if let sz = size, !sz.isEmpty { parts.append(sz) }
        parts.append(sourceName)
        return parts.joined(separator: " · ")
    }
}

// MARK: - 歌单（网络歌单广场）

struct SongListInfo: Identifiable, Hashable {
    var id: String
    var name: String
    var cover: String?
    var creator: String?
    var playCount: Double?

    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        guard let name = stringValue(deepGet(d, ["name"])), !name.isEmpty else { return nil }
        var sid = stringValue(deepGet(d, ["id"]))
        if sid == nil, let arr = arrayValue(d["id"]) { sid = arr.first.flatMap(stringValue) }
        guard let id = sid, !id.isEmpty else { return nil }
        self.id = id
        self.name = name
        self.cover = stringValue(deepGet(d, ["coverImgUrl"])) ?? stringValue(deepGet(d, ["cover"]))
            ?? stringValue(deepGet(d, ["imgUrl"]))
        self.creator = stringValue(deepGet(d, ["creator"]))
        if self.creator == nil, let c = d["creator"] as? [String: Any] {
            self.creator = stringValue(c["name"])
        }
        self.playCount = doubleValue(deepGet(d, ["playCount"])) ?? doubleValue(deepGet(d, ["play_num"]))
    }

    var playCountText: String {
        guard let c = playCount else { return "" }
        if c >= 100_000_000 { return String(format: "%.1f亿", c / 100_000_000) }
        if c >= 10_000 { return String(format: "%.1f万", c / 10_000) }
        return "\(Int(c))"
    }
}

struct SongListTag: Identifiable, Hashable {
    var id: String { "\(category)-\(name)" }
    var category: String
    var name: String

    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        guard let name = stringValue(deepGet(d, ["name"])), !name.isEmpty else { return nil }
        self.name = name
        self.category = stringValue(deepGet(d, ["category"])) ?? "全部"
    }
}

// MARK: - 榜单

struct LeaderboardBoard: Identifiable, Hashable {
    var id: String { "\(platform)-\(idRaw)" }
    var idRaw: String
    var bangid: String   // 榜单详情接口所需参数（如 "8888"）
    var platform: String
    var name: String
    var cover: String?

    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        guard let idRaw = stringValue(deepGet(d, ["id"])) else { return nil }
        guard let name = stringValue(deepGet(d, ["name"])) else { return nil }
        self.idRaw = idRaw
        self.bangid = stringValue(deepGet(d, ["bangid"])) ?? idRaw
        self.name = name
        self.platform = stringValue(deepGet(d, ["platform"])) ?? "tx"
        self.cover = stringValue(deepGet(d, ["coverImgUrl"])) ?? stringValue(deepGet(d, ["cover"]))
    }
}

// MARK: - 歌手与专辑

struct Artist: Identifiable, Hashable {
    var id: String { "\(source)-\(idRaw)" }
    var idRaw: String
    var source: String
    var name: String
    var avatar: String?
    var desc: String?

    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        guard let name = stringValue(deepGet(d, ["name"])) else { return nil }
        let idRaw = stringValue(deepGet(d, ["id"]))
            ?? stringValue(deepGet(d, ["mid"]))
            ?? stringValue(deepGet(d, ["singerMid"]))
            ?? ""
        self.idRaw = idRaw
        self.source = stringValue(deepGet(d, ["source"])) ?? "tx"
        self.name = name
        self.avatar = stringValue(deepGet(d, ["avatar"])) ?? stringValue(deepGet(d, ["pic"]))
        self.desc = stringValue(deepGet(d, ["desc"])) ?? stringValue(deepGet(d, ["description"]))
    }
}

struct Album: Identifiable, Hashable {
    var id: String { "\(source)-\(idRaw)" }
    var idRaw: String
    var source: String
    var name: String
    var cover: String?
    var singer: String?

    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        guard let name = stringValue(deepGet(d, ["name"])) else { return nil }
        let idRaw = stringValue(deepGet(d, ["id"]))
            ?? stringValue(deepGet(d, ["mid"]))
            ?? stringValue(deepGet(d, ["albumMid"]))
            ?? ""
        self.idRaw = idRaw
        self.source = stringValue(deepGet(d, ["source"])) ?? "tx"
        self.name = name
        self.cover = stringValue(deepGet(d, ["picUrl"])) ?? stringValue(deepGet(d, ["cover"]))
        self.singer = stringValue(deepGet(d, ["singer"]))
    }
}

// MARK: - 歌词

struct LyricLine: Identifiable, Equatable {
    let id = UUID()
    var time: Double
    var text: String

    static func parse(lrc: String) -> [LyricLine] {
        var result: [LyricLine] = []
        let lines = lrc.components(separatedBy: .newlines)
        let timeRegex = try? NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]", options: [])
        for line in lines {
            guard let regex = timeRegex else { break }
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, options: [], range: nsRange)
            guard !matches.isEmpty else { continue }
            let text = regex.stringByReplacingMatches(
                in: line, options: [], range: nsRange, withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            for m in matches {
                guard let r1 = Range(m.range(at: 1), in: line),
                      let r2 = Range(m.range(at: 2), in: line),
                      let min = Int(line[r1]), let sec = Int(line[r2]) else { continue }
                let ms: Double = {
                    guard m.numberOfRanges > 3, let r3 = Range(m.range(at: 3), in: line) else { return 0 }
                    let val = line[r3]
                    // 毫秒或百分秒
                    return (Double(val) ?? 0) / (val.count == 2 ? 100 : 1000)
                }()
                let time = Double(min * 60) + Double(sec) + ms
                result.append(LyricLine(time: time, text: text))
            }
        }
        return result.sorted { $0.time < $1.time }
    }
}

// MARK: - 缓存

struct CacheStats: Codable {
    var fileCount: Int?
    var totalSize: Int64?
    var lyricCount: Int?

    var sizeText: String {
        guard let s = totalSize else { return "未知" }
        return ByteCountFormatter.string(fromByteCount: s, countStyle: .file)
    }
}

struct CacheItem: Identifiable, Hashable {
    var id: String
    var name: String
    var singer: String?
    var size: Int64?
    var source: String?

    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        guard let id = stringValue(deepGet(d, ["id"])) else { return nil }
        self.id = id
        self.name = stringValue(deepGet(d, ["name"])) ?? "未知歌曲"
        self.singer = stringValue(deepGet(d, ["singer"]))
        self.size = (doubleValue(deepGet(d, ["size"]))).map { Int64($0) }
        self.source = stringValue(deepGet(d, ["source"]))
    }
}

// MARK: - 用户同步列表（LX Music 收藏列表结构）

struct UserList: Identifiable, Hashable {
    var id: String
    var name: String
    var songList: [UserListSong]?
    var location: Int?

    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        guard let id = stringValue(deepGet(d, ["id"])), !id.isEmpty else { return nil }
        self.id = id
        self.name = stringValue(deepGet(d, ["name"])) ?? "未命名歌单"
        self.location = doubleValue(deepGet(d, ["location"])).map { Int($0) }
        if let arr = arrayValue(d["songList"]) {
            self.songList = arr.compactMap { UserListSong(json: $0) }
        }
    }

    /// 编码用（POST 全量覆盖），此处做简单序列化
    func toJSON() -> [String: Any] {
        var obj: [String: Any] = ["id": id, "name": name]
        if let loc = location { obj["location"] = loc }
        if let songs = songList {
            obj["songList"] = songs.map { $0.toJSON() }
        }
        return obj
    }
}

struct UserListSong: Identifiable, Hashable {
    var id: String
    var name: String
    var singer: String
    var source: String?
    var interval: Double?
    var albumPic: String?

    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        guard let id = stringValue(deepGet(d, ["id"])) else { return nil }
        self.id = id
        self.name = stringValue(deepGet(d, ["name"])) ?? "未知"
        self.singer = stringValue(deepGet(d, ["singer"])) ?? ""
        self.source = stringValue(deepGet(d, ["source"]))
        self.interval = doubleValue(deepGet(d, ["interval"]))
        self.albumPic = stringValue(deepGet(d, ["albumPic"])) ?? stringValue(deepGet(d, ["pic"]))
    }

    func toJSON() -> [String: Any] {
        var obj: [String: Any] = ["id": id, "name": name, "singer": singer]
        if let s = source { obj["source"] = s }
        if let i = interval { obj["interval"] = i }
        if let p = albumPic { obj["albumPic"] = p }
        return obj
    }

    func asSong() -> Song {
        Song(id: id, name: name, singer: singer, source: source ?? "tx",
             albumPic: albumPic, interval: interval)
    }
}

// MARK: - 评论

struct SongComment: Identifiable, Hashable {
    var id: String
    var author: String
    var content: String
    var time: String?
    var likes: Double?
    var avatar: String?

    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        guard let content = stringValue(deepGet(d, ["content"])) ?? stringValue(deepGet(d, ["text"])),
              !content.isEmpty else { return nil }
        self.content = content
        self.id = stringValue(deepGet(d, ["id"])) ?? UUID().uuidString
        self.author = stringValue(deepGet(d, ["nickname"])) ?? stringValue(deepGet(d, ["userName"]))
            ?? stringValue(deepGet(d, ["author"])) ?? "匿名"
        self.time = stringValue(deepGet(d, ["time"])) ?? stringValue(deepGet(d, ["createTime"]))
        self.likes = doubleValue(deepGet(d, ["likedCount"])) ?? doubleValue(deepGet(d, ["likeCount"]))
        self.avatar = stringValue(deepGet(d, ["avatar"])) ?? stringValue(deepGet(d, ["pic"]))
    }
}

// MARK: - 自定义音乐目录（lxserver /api/music/custom/*）

/// 服务端本地音乐目录中的一首歌曲
struct CustomSong: Identifiable, Hashable {
    var id: String
    var filename: String      // 相对目录路径，如 "歌手 - 歌名.mp3" 或 "子目录/歌名.mp3"
    var name: String
    var singer: String
    var source: String
    var interval: Double?
    var hasLyric: Bool

    init?(json: Any) {
        guard let d = json as? [String: Any] else { return nil }
        guard let filename = stringValue(deepGet(d, ["filename"])), !filename.isEmpty else { return nil }
        let songInfo = (d["songInfo"] as? [String: Any]) ?? d
        self.filename = filename
        self.name = stringValue(deepGet(songInfo, ["name"])) ?? stringValue(deepGet(d, ["name"]))
            ?? filename.components(separatedBy: "/").last ?? filename
        self.singer = stringValue(deepGet(songInfo, ["singer"])) ?? stringValue(deepGet(d, ["singer"])) ?? "本地音乐"
        self.source = stringValue(deepGet(songInfo, ["source"])) ?? "custom"
        self.interval = doubleValue(deepGet(songInfo, ["interval"])) ?? doubleValue(deepGet(d, ["interval"]))
        self.hasLyric = (deepGet(d, ["hasLyric"]) as? Bool) ?? false
        self.id = stringValue(deepGet(songInfo, ["songmid"])) ?? stringValue(deepGet(songInfo, ["id"]))
            ?? stringValue(deepGet(d, ["id"])) ?? filename
    }

    /// 转为可播放的 Song（source = "custom"，携带 filename 与封面）
    func asSong(coverURL: String? = nil) -> Song {
        Song(id: id, name: name, singer: singer, source: "custom",
             albumPic: coverURL, interval: interval, customFilename: filename)
    }
}
