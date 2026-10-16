import Foundation

/// 服务器连接配置（持久化到 UserDefaults）
struct ServerConfig: Codable, Equatable {
    var baseURL: String = ""        // http://192.168.x.x:9527
    var playerPassword: String = "" // Web 播放器访问密码（可选）
    var username: String = ""       // 用户同步账号（可选）
    var password: String = ""       // 用户同步密码（可选）
    var userToken: String = ""      // 登录后获得的 x-user-token
    var playerPath: String = ""     // 播放器路径（默认根路径）
    var enableAuth: Bool = false    // 服务器是否开启了播放器密码认证

    var displayHost: String {
        guard let u = URL(string: baseURL) else { return baseURL }
        return u.host ?? baseURL
    }

    /// 归一化 baseURL：补全协议与端口缺省
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") {
            s = "http://" + s
        }
        return s
    }
}

final class ConfigStore {
    static let shared = ConfigStore()
    private let key = "lx.server.config.v1"

    private init() {}

    func load() -> ServerConfig? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ServerConfig.self, from: data)
    }

    func save(_ config: ServerConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
