import SwiftUI

/// 我的页（汽水音乐风格：个人区 + 功能入口）
struct MineView: View {
    @EnvironmentObject var session: AppSession
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                headerSection
                if session.isUserLoggedIn {
                    Section("我的歌单") {
                        NavigationLink {
                            UserPlaylistsView()
                        } label: {
                            Label("同步歌单与收藏", systemImage: "music.note.list")
                        }
                    }
                } else {
                    Section("我的歌单") {
                        Button {
                            path.append(true) // 提示去登录
                        } label: {
                            Label("登录用户后可同步歌单", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }
                Section("存储与缓存") {
                    NavigationLink {
                        CacheView()
                    } label: {
                        Label("缓存管理", systemImage: "externaldrive.fill")
                    }
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label("快照备份", systemImage: "arrow.clockwise.icloud")
                    }
                }
                Section("设置") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("播放与外观设置", systemImage: "gearshape.fill")
                    }
                }
                Section("服务器") {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("服务器信息", systemImage: "server.rack")
                    }
                }
            }
            .navigationDestination(for: Bool.self) { _ in LoginPromptView() }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(
                    LinearGradient(colors: [.accentColor, .accentColor.opacity(0.6)],
                                   startPoint: .top, endPoint: .bottom))
                Image(systemName: session.isUserLoggedIn ? "person.fill" : "person.crop.circle")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(.white)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.isUserLoggedIn ? (session.config?.username ?? "用户") : "未登录用户")
                    .font(.system(.title3, design: .rounded)).bold()
                Text(session.config?.displayHost ?? "")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Menu {
                Button("切换服务器 / 退出登录", role: .destructive) { session.logout() }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 10)
        .listRowSeparator(.hidden)
    }
}

/// 用户同步歌单（我的歌单 + 收藏）
struct UserPlaylistsView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var player: PlayerManager
    @State private var lists: [UserList] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isLoading {
                    LoadingView()
                } else if let error {
                    ErrorView(message: error) { Task { await load() } }
                } else if lists.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "music.note.list").font(.system(size: 44)).foregroundColor(.gray)
                        Text("暂无歌单，请在 LX Music 客户端同步后查看")
                            .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                        Button("刷新") { Task { await load() } }.buttonStyle(.bordered)
                    }.padding()
                } else {
                    List {
                        ForEach(lists) { list in
                            NavigationLink {
                                UserListSongsView(list: list, allLists: $lists)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(list.name).font(.headline)
                                    Text("\(list.songList?.count ?? 0) 首").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .navigationDestination(for: UserList.self) { list in
                        UserListSongsView(list: list, allLists: $lists)
                    }
                }
            }
            .navigationTitle("我的歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            lists = try await session.api?.getUserList() ?? []
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

/// 某个用户歌单的歌曲列表（可播放 / 移除）
struct UserListSongsView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var player: PlayerManager
    @State var list: UserList
    @Binding var allLists: [UserList]

    var body: some View {
        List {
            ForEach(list.songList ?? []) { us in
                let song = us.asSong()
                SongRow(song: song, onTap: {
                    player.play(songs: (list.songList ?? []).map { $0.asSong() },
                                startIndex: (list.songList ?? []).firstIndex(of: us) ?? 0)
                }) {
                    AnyView(Image(systemName: "play.circle")
                        .foregroundColor(.accentColor).font(.title3))
                }
                .swipeActions {
                    Button(role: .destructive) {
                        Task { await remove(us) }
                    } label: { Label("移除", systemImage: "trash") }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func remove(_ us: UserListSong) async {
        guard let api = session.api else { return }
        do {
            try await api.removeFromUserList(listId: list.id, songIds: [us.id])
            list.songList?.removeAll { $0.id == us.id }
            if let i = allLists.firstIndex(where: { $0.id == list.id }) { allLists[i] = list }
        } catch { }
    }
}
