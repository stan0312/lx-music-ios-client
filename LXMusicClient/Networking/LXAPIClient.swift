import Foundation

enum LXError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case noData
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "服务器地址无效"
        case .http(let code, let msg):
            return msg.isEmpty ? "请求失败（\(code)）" : msg
        case .noData: return "没有返回数据"
        case .notLoggedIn: return "请先登录"
        }
    }
}

/// lxserver 的 REST API 客户端（JSON + Cookie 会话 + x-user-token 鉴权）
final class LXAPIClient {
    private let baseURL: String
    private let session: URLSession
    private var token: String = ""

    init(baseURL: String) {
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.httpCookieAcceptPolicy = .always
        // 使用共享 Cookie 存储，自动携带 lx_player_session 等 Cookie
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        self.session = URLSession(configuration: cfg)
    }

    func setToken(_ t: String) { token = t }

    private func url(_ path: String, query: [String: String] = [:]) throws -> URL {
        guard var comps = URLComponents(string: baseURL + path) else { throw LXError.invalidURL }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let u = comps.url else { throw LXError.invalidURL }
        return u
    }

    // MARK: - 底层请求

    private func request(_ url: URL, method: String = "GET", body: Any? = nil,
                         useToken: Bool = true) async throws -> Any {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if useToken && !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "x-user-token")
        }
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LXError.noData }

        // 允许跨域（与 Web 端一致，此处非浏览器，无需处理 CORS）
        if !(200...299).contains(http.statusCode) {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["message"] as? String } ?? ""
            throw LXError.http(http.statusCode, msg)
        }
        if data.isEmpty { return [:] }
        return try JSONSerialization.jsonObject(with: data)
    }

    // MARK: - 认证与配置

    /// 公开配置
    struct PlayerConfig: Codable {
        var player_enableAuth: Bool?
        var playerPath: String?
        var enableAuth: Bool? { player_enableAuth }
    }

    func getPlayerConfig() async throws -> [String: Any] {
        let obj: Any = try await request(try url("/api/music/config"))
        if let d = obj as? [String: Any] { return d }
        return [:]
    }

    /// 校验播放器访问密码（写入 HttpOnly Cookie 会话）
    func playerAuth(password: String) async throws {
        _ = try await request(try url("/api/music/auth"), method: "POST",
                              body: ["password": password], useToken: false)
    }

    func playerAuthVerify() async throws -> Bool {
        let obj: Any = try await request(try url("/api/music/auth/verify"), useToken: false)
        if let d = obj as? [String: Any] { return (d["valid"] as? Bool) ?? (d["success"] as? Bool) ?? true }
        return true
    }

    func playerAuthLogout() async throws {
        _ = try await request(try url("/api/music/auth/logout"), method: "POST", useToken: false)
    }

    /// 用户登录，获取 x-user-token
    func login(username: String, password: String) async throws -> String {
        let obj: Any = try await request(try url("/api/user/login"), method: "POST",
                                         body: ["username": username, "password": password], useToken: false)
        if let d = obj as? [String: Any] {
            if let t = d["token"] as? String { setToken(t); return t }
            if let success = d["success"] as? Bool, !success {
                throw LXError.http(401, (d["message"] as? String) ?? "登录失败")
            }
        }
        throw LXError.http(401, "登录失败")
    }

    func logout() async throws {
        _ = try await request(try url("/api/user/logout"), method: "POST")
        token = ""
    }

    func authVerify() async throws -> Bool {
        let obj: Any = try await request(try url("/api/user/auth/verify"))
        if let d = obj as? [String: Any] { return (d["valid"] as? Bool) ?? (d["success"] as? Bool) ?? true }
        return true
    }

    // MARK: - 搜索 / 热搜 / 联想

    func search(keyword: String, source: String? = nil, page: Int = 1, limit: Int = 30) async throws -> [Song] {
        var q = ["name": keyword, "page": "\(page)", "limit": "\(limit)"]
        if let s = source, !s.isEmpty { q["source"] = s }
        let obj: Any = try await request(try url("/api/music/search", query: q))
        return extractSongs(obj)
    }

    /// 多音源并发搜索并合并去重（“全部”时用，任一音源可用即返回结果）
    func searchAll(keyword: String, limit: Int = 20) async throws -> [Song] {
        let sources = ["kw", "kg", "tx", "wy", "mg"]
        var merged: [Song] = []
        var seen = Set<String>()
        await withTaskGroup(of: [Song].self) { group in
            for s in sources {
                group.addTask {
                    (try? await self.search(keyword: keyword, source: s, page: 1, limit: limit)) ?? []
                }
            }
            for await list in group {
                for song in list where !seen.contains(song.id + "|" + song.source) {
                    seen.insert(song.id + "|" + song.source)
                    merged.append(song)
                }
            }
        }
        return merged
    }

    func tipSearch(keyword: String, source: String = "tx") async throws -> [String] {
        let obj: Any = try await request(try url("/api/music/tipSearch", query: ["name": keyword, "source": source]))
        if let d = obj as? [String: Any] {
            if let list = d["list"] as? [String] { return list }
            if let arr = arrayValue(d["list"] ?? d["data"]) {
                return arr.compactMap { stringValue($0) }
            }
        }
        if let arr = obj as? [Any] { return arr.compactMap { stringValue($0) } }
        return []
    }

    func hotSearch() async throws -> [String] {
        let obj: Any = try await request(try url("/api/music/hotSearch"))
        if let d = obj as? [String: Any] {
            if let list = d["list"] as? [String] { return list }
            if let arr = arrayValue(d["list"] ?? d["data"]) {
                return arr.compactMap { item -> String? in
                    if let s = item as? String { return s }
                    if let dd = item as? [String: Any] {
                        return stringValue(dd["name"]) ?? stringValue(dd["keyword"]) ?? stringValue(dd["title"])
                    }
                    return nil
                }
            }
        }
        return []
    }

    // MARK: - 歌单广场

    func songListTags() async throws -> [SongListTag] {
        let obj: Any = try await request(try url("/api/music/songList/tags"))
        if let d = obj as? [String: Any], let arr = arrayValue(d["list"] ?? d["data"]) {
            return arr.compactMap { SongListTag(json: $0) }
        }
        if let arr = obj as? [Any] { return arr.compactMap { SongListTag(json: $0) } }
        return []
    }

    func songListList(tag: String? = nil, page: Int = 1, limit: Int = 30) async throws -> [SongListInfo] {
        var q = ["page": "\(page)", "limit": "\(limit)", "sortId": "hot"]
        if let tag, !tag.isEmpty { q["tagId"] = tag }
        let obj: Any = try await request(try url("/api/music/songList/list", query: q))
        if let d = obj as? [String: Any], let arr = arrayValue(d["list"] ?? d["data"]) {
            return arr.compactMap { SongListInfo(json: $0) }
        }
        if let arr = obj as? [Any] { return arr.compactMap { SongListInfo(json: $0) } }
        return []
    }

    func songListDetail(id: String, page: Int = 1, limit: Int = 100) async throws -> [Song] {
        let obj: Any = try await request(try url("/api/music/songList/detail",
                                                 query: ["id": id, "page": "\(page)", "limit": "\(limit)"]))
        if let d = obj as? [String: Any], let arr = arrayValue(d["list"] ?? d["songs"]) {
            let songs = arr.compactMap { Song(json: $0) }
            if !songs.isEmpty { return songs }
        }
        return extractSongs(obj)
    }

    // MARK: - 榜单

    func leaderboardBoards(platform: String = "tx") async throws -> [LeaderboardBoard] {
        let obj: Any = try await request(try url("/api/music/leaderboard/boards",
                                                 query: ["source": platform]))
        if let d = obj as? [String: Any], let arr = arrayValue(d["list"] ?? d["data"]) {
            return arr.compactMap { LeaderboardBoard(json: $0) }
        }
        if let arr = obj as? [Any] { return arr.compactMap { LeaderboardBoard(json: $0) } }
        return []
    }

    // MARK: - 在线音源诊断

    /// 逐音源探测服务端在线源是否可用（走服务端 /api/music/leaderboard/boards，每个音源 6 秒超时）
    func diagnoseSources() async -> [SourceDiagnosis] {
        let sources = ["kw", "kg", "tx", "wy", "mg"]
        var out: [SourceDiagnosis] = []
        await withTaskGroup(of: SourceDiagnosis.self) { group in
            for s in sources {
                group.addTask { await self.probe(source: s) }
            }
            for await d in group { out.append(d) }
        }
        return out.sorted { $0.source < $1.source }
    }

    private func probe(source: String) async -> SourceDiagnosis {
        guard let u = try? url("/api/music/leaderboard/boards", query: ["source": source]) else {
            return SourceDiagnosis(source: source, ok: false, detail: "URL 构建失败")
        }
        var req = URLRequest(url: u)
        req.timeoutInterval = 6
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse {
                let ok = (200...299).contains(http.statusCode)
                return SourceDiagnosis(source: source, ok: ok, detail: "HTTP \(http.statusCode)")
            }
            return SourceDiagnosis(source: source, ok: false, detail: "无响应")
        } catch {
            return SourceDiagnosis(source: source, ok: false, detail: error.localizedDescription)
        }
    }

    func leaderboardList(platform: String, bangid: String, page: Int = 1) async throws -> [Song] {
        let obj: Any = try await request(try url("/api/music/leaderboard/list",
                                                 query: ["source": platform, "bangid": bangid, "page": "\(page)"]))
        return extractSongs(obj)
    }

    // MARK: - 歌手 / 专辑

    func artistDetail(source: String, id: String) async throws -> Artist? {
        let obj: Any = try await request(try url("/api/music/artistDetail",
                                                 query: ["source": source, "id": id]))
        return (obj as? [String: Any]).flatMap { Artist(json: $0) }
    }

    func artistAlbums(source: String, id: String, page: Int = 1) async throws -> [Album] {
        let obj: Any = try await request(try url("/api/music/artistAlbums",
                                                 query: ["source": source, "id": id, "page": "\(page)"]))
        if let d = obj as? [String: Any], let arr = arrayValue(d["list"] ?? d["data"] ?? d["albums"]) {
            return arr.compactMap { Album(json: $0) }
        }
        if let arr = obj as? [Any] { return arr.compactMap { Album(json: $0) } }
        return []
    }

    func artistSongs(source: String, id: String, page: Int = 1) async throws -> [Song] {
        let obj: Any = try await request(try url("/api/music/artistSongs",
                                                 query: ["source": source, "id": id, "page": "\(page)"]))
        return extractSongs(obj)
    }

    func albumSongs(source: String, id: String, page: Int = 1) async throws -> [Song] {
        let obj: Any = try await request(try url("/api/music/albumSongs",
                                                 query: ["source": source, "id": id, "page": "\(page)"]))
        return extractSongs(obj)
    }

    // MARK: - 播放 / 歌词 / 评论

    /// 解析播放直链（请求体需包一层 songInfo）
    func musicURL(song: Song, quality: String? = nil) async throws -> String {
        var body: [String: Any] = ["songInfo": song.songInfoPayload()]
        if let q = quality, !q.isEmpty { body["quality"] = q }

        let obj: Any = try await request(try url("/api/music/url"), method: "POST", body: body)
        if let s = obj as? String, !s.isEmpty { return s }
        if let d = obj as? [String: Any] {
            if let u = d["url"] as? String, !u.isEmpty { return u }
            if let url = d["url"] as? String { return url }
            if let data = d["data"] as? [String: Any], let u = data["url"] as? String, !u.isEmpty { return u }
        }
        throw LXError.noData
    }

    func lyric(song: Song) async throws -> String {
        let body: [String: Any] = ["songInfo": song.songInfoPayload()]
        let obj: Any = try await request(try url("/api/music/lyric"), method: "POST", body: body)
        if let s = obj as? String, !s.isEmpty { return s }
        if let d = obj as? [String: Any] {
            if let lrc = d["lrc"] as? String, !lrc.isEmpty { return lrc }
            if let data = d["data"] as? String, !data.isEmpty { return data }
            if let data = d["data"] as? [String: Any], let lrc = data["lrc"] as? String { return lrc }
        }
        return ""
    }

    func comment(song: Song, type: String = "hot", page: Int = 1, limit: Int = 20) async throws -> [SongComment] {
        let body: [String: Any] = ["songInfo": song.songInfoPayload(), "type": type, "page": page, "limit": limit]
        let obj: Any = try await request(try url("/api/music/comment"), method: "POST", body: body)
        if let d = obj as? [String: Any] {
            for key in ["comments", "list", "data"] {
                if let arr = arrayValue(d[key]) {
                    let cs = arr.compactMap { SongComment(json: $0) }
                    if !cs.isEmpty { return cs }
                }
            }
            if let data = d["data"] as? [String: Any],
               let arr = arrayValue(data["comments"]) {
                return arr.compactMap { SongComment(json: $0) }
            }
        }
        if let arr = obj as? [Any] { return arr.compactMap { SongComment(json: $0) } }
        return []
    }

    // MARK: - 黑名单（不喜欢 / 不推荐）lxserver /api/music/dislike/*

    /// 把当前歌曲加入“不喜欢/不推荐”黑名单（type=song，按歌名+歌手匹配）
    func dislikeAdd(song: Song) async throws {
        _ = try await request(try url("/api/music/dislike/add"), method: "POST",
                              body: dislikePayload(song))
    }

    /// 从黑名单移除当前歌曲
    func dislikeRemove(song: Song) async throws {
        _ = try await request(try url("/api/music/dislike/remove"), method: "POST",
                              body: dislikePayload(song))
    }

    /// 查询当前黑名单规则
    func dislikeList() async throws -> [String: Any] {
        let obj: Any = try await request(try url("/api/music/dislike"))
        return (obj as? [String: Any]) ?? [:]
    }

    private func dislikePayload(_ song: Song) -> [String: Any] {
        var body: [String: Any] = ["type": "song", "name": song.name, "singer": song.singer,
                                   "source": song.source, "id": song.id,
                                   "pic": song.albumPic ?? "", "interval": ""]
        if let iv = song.interval { body["interval"] = String(iv) }
        return body
    }

    /// 下载直链（服务器代理，自动注入 ID3）
    func downloadLink(song: Song) -> String {
        var q = "url=\(song.url?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        q += "&filename=\((song.name + " - " + song.singer).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        q += "&tag=1&name=\(song.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        q += "&singer=\(song.singer.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let album = song.albumName { q += "&album=\(album.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
        if let pic = song.albumPic { q += "&pic=\(pic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
        return baseURL + "/api/music/download?" + q
    }

    // MARK: - 用户列表（我的歌单 / 收藏）

    func getUserList() async throws -> [UserList] {
        let obj: Any = try await request(try url("/api/user/list"))
        if let d = obj as? [String: Any], let arr = arrayValue(d["list"] ?? d["data"]) {
            return arr.compactMap { UserList(json: $0) }
        }
        if let arr = obj as? [Any] { return arr.compactMap { UserList(json: $0) } }
        return []
    }

    /// 全量覆盖（会触发同步广播），传完整歌单数组
    func saveUserList(_ lists: [UserList]) async throws {
        let payload = lists.map { $0.toJSON() }
        _ = try await request(try url("/api/user/list"), method: "POST", body: payload)
    }

    func removeFromUserList(listId: String, songIds: [String]) async throws {
        _ = try await request(try url("/api/music/user/list/remove"), method: "POST",
                              body: ["listId": listId, "songIds": songIds])
    }

    // MARK: - 用户设置与音效

    func getUserSettings() async throws -> [String: Any] {
        let obj: Any = try await request(try url("/api/user/settings"))
        return (obj as? [String: Any]) ?? [:]
    }

    func saveUserSettings(_ settings: [String: Any]) async throws {
        _ = try await request(try url("/api/user/settings"), method: "POST", body: settings)
    }

    func getSoundEffects() async throws -> [String: Any] {
        let obj: Any = try await request(try url("/api/user/sound-effects"))
        return (obj as? [String: Any]) ?? [:]
    }

    func saveSoundEffects(_ effects: [String: Any]) async throws {
        _ = try await request(try url("/api/user/sound-effects"), method: "POST", body: effects)
    }

    // MARK: - 缓存管理

    func cacheStats() async throws -> CacheStats? {
        let obj: Any = try await request(try url("/api/music/cache/stats"))
        guard let d = obj as? [String: Any] else { return nil }
        return CacheStats(
            fileCount: (doubleValue(d["fileCount"] ?? d["file_num"])).map { Int($0) }
                ?? (doubleValue(d["count"])).map { Int($0) },
            totalSize: (doubleValue(d["totalSize"] ?? d["size"])).map { Int64($0) },
            lyricCount: (doubleValue(d["lyricCount"])).map { Int($0) }
        )
    }

    func cacheList() async throws -> [CacheItem] {
        let obj: Any = try await request(try url("/api/music/cache/list"))
        if let d = obj as? [String: Any], let arr = arrayValue(d["list"] ?? d["data"]) {
            return arr.compactMap { CacheItem(json: $0) }
        }
        if let arr = obj as? [Any] { return arr.compactMap { CacheItem(json: $0) } }
        return []
    }

    func cacheDownload(song: Song, streamURL: String, quality: String? = nil) async throws {
        var body: [String: Any] = ["songInfo": song.songInfoPayload(), "url": streamURL]
        if let q = quality, !q.isEmpty { body["quality"] = q }
        _ = try await request(try url("/api/music/cache/download"), method: "POST", body: body)
    }

    func cacheRemove(ids: [String]) async throws {
        _ = try await request(try url("/api/music/cache/remove"), method: "POST", body: ["ids": ids])
    }

    func cacheClear() async throws {
        _ = try await request(try url("/api/music/cache/clear"), method: "POST")
    }

    // MARK: - 自定义音乐目录（/api/music/custom/*）

    /// 获取自定义目录歌曲列表
    func customList() async throws -> [CustomSong] {
        let obj: Any = try await request(try url("/api/music/custom/list"))
        if let d = obj as? [String: Any], let arr = arrayValue(d["data"] ?? d["list"]) {
            return arr.compactMap { CustomSong(json: $0) }
        }
        if let arr = obj as? [Any] { return arr.compactMap { CustomSong(json: $0) } }
        return []
    }

    /// 触发服务器重新扫描自定义目录
    func customSync() async throws {
        _ = try await request(try url("/api/music/custom/sync"), method: "POST")
    }

    /// 自定义目录歌曲的流式播放直链（AVPlayer 直接可播，token 走 query）
    func customFileURL(filename: String, user: String) throws -> URL {
        try url("/api/music/custom/file", query: ["filename": filename, "user": user, "token": token])
    }

    /// 自定义目录歌曲的内嵌封面
    func customCoverURL(filename: String, user: String) throws -> URL {
        try url("/api/music/custom/cover", query: ["filename": filename, "user": user, "token": token])
    }

    /// 自定义目录歌曲的歌词：
    /// 1) 优先读音频内嵌歌词（GET /api/music/custom/embedLyric）
    /// 2) 取不到则尝试读取同目录外部 .lrc 文件
    func customLyric(filename: String, user: String) async throws -> String {
        // 1. 内嵌歌词
        if let u = try? customEmbedLyricURL(filename: filename, user: user) {
            if let d = try? await request(u) as? [String: Any],
               let lrc = d["lrc"] as? String, !lrc.isEmpty {
                return lrc
            }
        }
        // 2. 外部 .lrc（把音频扩展名换成 .lrc）
        let lrcRel = filename.components(separatedBy: ".")
        let lrcPath = lrcRel.count > 1
            ? (lrcRel.dropLast().joined(separator: ".") + ".lrc")
            : filename + ".lrc"
        if let u = try? customFileURL(filename: lrcPath, user: user) {
            if let raw = try? await rawGet(u), !raw.isEmpty, raw.contains("["), raw.contains("]") {
                return raw
            }
        }
        return ""
    }

    /// 读取音频内嵌歌词的地址
    func customEmbedLyricURL(filename: String, user: String) throws -> URL {
        try url("/api/music/custom/embedLyric",
               query: ["filename": filename, "user": user, "token": token])
    }

    /// 取原始文本响应（用于读取 .lrc 等非 JSON 内容）
    private func rawGet(_ url: URL) async throws -> String {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !token.isEmpty { req.setValue(token, forHTTPHeaderField: "x-user-token") }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LXError.http((resp as? HTTPURLResponse)?.statusCode ?? -1, "")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - 快照备份

    func snapshots() async throws -> [String] {
        let obj: Any = try await request(try url("/api/data/snapshots"))
        if let d = obj as? [String: Any], let arr = arrayValue(d["list"] ?? d["data"]) {
            return arr.compactMap { item -> String? in
                if let s = item as? String { return s }
                if let dd = item as? [String: Any] { return stringValue(dd["id"]) ?? stringValue(dd["time"]) ?? stringValue(dd["name"]) }
                return nil
            }
        }
        if let arr = obj as? [Any] { return arr.compactMap { $0 as? String } }
        return []
    }

    func restoreSnapshot(id: String) async throws {
        _ = try await request(try url("/api/data/restore-snapshot"), method: "POST", body: ["id": id])
    }

    func uploadSnapshot() async throws {
        _ = try await request(try url("/api/data/upload-snapshot"), method: "POST")
    }

    func deleteSnapshot(id: String) async throws {
        _ = try await request(try url("/api/data/delete-snapshot"), method: "POST", body: ["id": id])
    }

    // MARK: - 自定义源（供“设置”中查看/启停）

    func customSourceList() async throws -> [[String: Any]] {
        let obj: Any = try await request(try url("/api/custom-source/list"))
        if let arr = obj as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
        if let d = obj as? [String: Any], let arr = arrayValue(d["list"] ?? d["data"]) {
            return arr.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    func customSourceToggle(id: String, enabled: Bool) async throws {
        _ = try await request(try url("/api/custom-source/toggle"), method: "POST",
                              body: ["id": id, "enabled": enabled])
    }
}
