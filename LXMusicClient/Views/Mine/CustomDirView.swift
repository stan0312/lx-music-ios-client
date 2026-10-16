import SwiftUI

/// 自定义音乐目录（lxserver /api/music/custom/*）
/// 直接播放 NAS 上挂载的本地音乐目录
struct CustomDirView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var player: PlayerManager
    @State private var songs: [CustomSong] = []
    @State private var isLoading = true
    @State private var isSyncing = false
    @State private var error: String?

    var body: some View {
        Group {
            if !(session.api != nil && session.isUserLoggedIn) {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 44)).foregroundColor(.gray)
                    Text("自定义目录需要登录用户账号")
                        .font(.subheadline).foregroundColor(.secondary)
                    Text("请在首页“连接服务器”时填写用户名与密码，或在设置中登录")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }.padding()
            } else if isLoading {
                LoadingView()
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else if songs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.questionmark").font(.system(size: 44)).foregroundColor(.gray)
                    Text("未发现自定义目录歌曲")
                        .font(.subheadline).foregroundColor(.secondary)
                    Text("请在 lxserver 用户管理中开启“自定义音乐目录”并设置目录路径，然后点击右上角“同步”")
                        .font(.caption).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                    Button("同步目录") { Task { await syncAndReload() } }.buttonStyle(.bordered)
                }.padding()
            } else {
                List {
                    ForEach(songs) { item in
                        SongRow(song: item.asSong(coverURL: coverURL(for: item)), onTap: {
                            playAll(startingAt: item)
                        }) {
                            AnyView(coverView(for: item))
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("自定义目录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if isSyncing {
                    ProgressView()
                } else {
                    Button {
                        Task { await syncAndReload() }
                    } label: { Label("同步", systemImage: "arrow.triangle.2.circlepath") }
                }
                Button {
                    Task { await load() }
                } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { await load() }
    }

    private func coverURL(for item: CustomSong) -> String? {
        guard let api = session.api, let user = session.config?.username else { return nil }
        return try? api.customCoverURL(filename: item.filename, user: user).absoluteString
    }

    private func coverView(for item: CustomSong) -> some View {
        CoverImage(url: coverURL(for: item), width: 46, cornerRadius: 8)
    }

    /// 整目录开播（每首歌附带内嵌封面，保证播放页取色 + 封面显示）
    private func playAll(startingAt target: CustomSong) {
        guard let api = session.api else { return }
        let user = session.config?.username ?? ""
        let queue = songs.map { c in
            let cover = (try? api.customCoverURL(filename: c.filename, user: user).absoluteString)
            return c.asSong(coverURL: cover)
        }
        player.play(songs: queue, startIndex: queue.firstIndex(where: { $0.id == target.id }) ?? 0)
    }

    private func load() async {
        guard let api = session.api else { return }
        isLoading = true
        error = nil
        do {
            songs = try await api.customList()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func syncAndReload() async {
        guard let api = session.api else { return }
        isSyncing = true
        do {
            try await api.customSync()
            songs = try await api.customList()
        } catch {
            self.error = error.localizedDescription
        }
        isSyncing = false
    }
}
