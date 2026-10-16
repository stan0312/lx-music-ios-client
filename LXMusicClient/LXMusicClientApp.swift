import SwiftUI

@main
struct LXMusicClientApp: App {
    @StateObject private var session = AppSession()

    init() {
        // 全局外观：简洁、接近汽水音乐的白底/暗色自适应
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(PlayerManager.shared)
                .preferredColorScheme(session.colorScheme)
        }
    }
}
