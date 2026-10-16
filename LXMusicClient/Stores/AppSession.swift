import SwiftUI
import Combine

/// 全局会话：服务器配置、登录状态、音质偏好、播放控制
@MainActor
final class AppSession: ObservableObject {
    @Published var config: ServerConfig?
    @Published var api: LXAPIClient?
    @Published var isLoggedIn = false
    @Published var isUserLoggedIn = false

    // 播放器设置（本地持久化）
    @AppStorage("lx.quality") var quality: String = "128k"
    @Published var isDark: Bool = UserDefaults.standard.bool(forKey: "lx.themeDark")

    // 连接状态
    @Published var isConnecting = false
    @Published var connectError: String?

    var colorScheme: ColorScheme? {
        isDark ? .dark : .light
    }

    func setDark(_ dark: Bool) {
        isDark = dark
        UserDefaults.standard.set(dark, forKey: "lx.themeDark")
    }

    func configure(_ cfg: ServerConfig, playerPassword: String = "", user: (String, String)? = nil) async {
        isConnecting = true
        connectError = nil
        do {
            let normalized = ServerConfig.normalize(cfg.baseURL)
            var c = cfg
            c.baseURL = normalized
            let client = LXAPIClient(baseURL: normalized)

            // 1. 读取播放器配置
            var enableAuth = false
            var playerPath = ""
            do {
                let conf = try await client.getPlayerConfig()
                enableAuth = (conf["player.enableAuth"] as? Bool)
                    ?? (conf["enableAuth"] as? Bool) ?? false
                playerPath = (conf["player.path"] as? String) ?? ""
            } catch {
                // 有些版本可能未开启 /api/music/config，忽略
            }

            // 2. 播放器密码认证
            let pass = !playerPassword.isEmpty ? playerPassword : c.playerPassword
            if enableAuth && !pass.isEmpty {
                try await client.playerAuth(password: pass)
            }

            // 3. 用户登录（可选）
            if let user {
                let token = try await client.login(username: user.0, password: user.1)
                c.username = user.0
                c.password = user.1
                c.userToken = token
                isUserLoggedIn = true
            } else if !c.username.isEmpty && !c.password.isEmpty {
                let token = try await client.login(username: c.username, password: c.password)
                c.userToken = token
                isUserLoggedIn = true
            }

            c.enableAuth = enableAuth
            c.playerPath = playerPath
            self.config = c
            self.api = client
            PlayerManager.shared.configure(api: client)
            PlayerManager.shared.setQuality(quality)
            ConfigStore.shared.save(c)
            isLoggedIn = true
        } catch {
            connectError = error.localizedDescription
        }
        isConnecting = false
    }

    func logout() {
        let t = config?.userToken
        if let api, !(t?.isEmpty ?? true) {
            Task { try? await api.logout() }
        }
        isLoggedIn = false
        isUserLoggedIn = false
        config = nil
        api = nil
        PlayerManager.shared.configure(api: nil)
        PlayerManager.shared.queue = []
        ConfigStore.shared.clear()
    }

    /// 尝试用持久化配置自动重连（启动时调用）
    func tryRestore() async {
        guard let cfg = ConfigStore.shared.load() else { return }
        await configure(cfg)
    }
}
