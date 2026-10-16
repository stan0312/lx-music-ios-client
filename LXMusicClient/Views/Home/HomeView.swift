import SwiftUI

/// 推荐页（汽水音乐风格首页：搜索入口 + 热搜 + 排行榜 + 歌单）
struct HomeView: View {
    @EnvironmentObject var session: AppSession
    @State private var hotSearches: [String] = []
    @State private var boards: [LeaderboardBoard] = []
    @State private var platform = "tx"
    @State private var isLoading = false
    @State private var error: String?
    @State private var path = NavigationPath()

    // 歌单（并入推荐页）
    @State private var tags: [SongListTag] = []
    @State private var lists: [SongListInfo] = []
    @State private var selectedTag: String? = nil
    @State private var listLoading = false

    private let platforms = ["tx", "wy", "kw", "kg", "mg"]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if isLoading {
                        LoadingView().frame(height: 220)
                    } else if let error {
                        ErrorView(message: error) { Task { await load() } }
                            .frame(height: 220)
                    } else {
                        hotSection
                        leaderboardSection
                        songlistSection
                    }
                }
                .padding(.bottom, 30)
            }
            .background(Color(.systemBackground))
            .navigationDestination(for: String.self) { keyword in
                SearchView(initialKeyword: keyword)
            }
            .navigationDestination(for: LeaderboardBoard.self) { board in
                BoardSongListView(board: board)
            }
            .navigationDestination(for: SongListInfo.self) { info in
                SongListDetailView(songList: info)
            }
            .navigationDestination(for: Song.self) { _ in EmptyView() }
        }
        .task { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LX 音乐").font(.system(.title, design: .rounded)).bold()
                if let host = session.config?.displayHost, !host.isEmpty {
                    Text(host).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            // 搜索入口
            Button {
                path.append("")
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var hotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "热门搜索")
            if hotSearches.isEmpty {
                Text("暂无热搜").font(.footnote).foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(hotSearches.prefix(10), id: \.self) { kw in
                            Button {
                                path.append(kw)
                            } label: {
                                Text("\(kw)")
                                    .font(.subheadline)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "排行榜")
            if boards.isEmpty {
                EmptyView().frame(height: 60)
            } else {
                // 平台切换
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(platforms, id: \.self) { p in
                            Button {
                                platform = p
                                Task { await loadBoards() }
                            } label: {
                                Text(sourceName(p))
                                    .font(.subheadline.weight(platform == p ? .semibold : .regular))
                                    .padding(.horizontal, 14).padding(.vertical, 7)
                                    .background(platform == p ? Color.accentColor : Color(.secondarySystemBackground))
                                    .foregroundColor(platform == p ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                // 榜单横向
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(boards) { b in
                            Button {
                                path.append(b)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    CoverImage(url: b.cover, width: 132, cornerRadius: 12)
                                    Text(b.name)
                                        .font(.subheadline).fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    /// 歌单（并入推荐页）
    private var songlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "歌单")
            // 歌单标签
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags) { tag in
                        Button {
                            selectedTag = tag.name
                            Task { await loadLists() }
                        } label: {
                            Text(tag.name)
                                .font(.subheadline)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(selectedTag == tag.name ? Color.accentColor : Color(.secondarySystemBackground))
                                .foregroundColor(selectedTag == tag.name ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            if listLoading {
                LoadingView().frame(height: 220)
            } else if lists.isEmpty {
                Text("暂无歌单").font(.footnote).foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 18) {
                    ForEach(lists) { info in
                        Button {
                            path.append(info)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .bottomLeading) {
                                    CoverImage(url: info.cover, width: 170, cornerRadius: 12)
                                    if let pc = info.playCount, pc > 0 {
                                        Text("▶ \(info.playCountText)")
                                            .font(.caption2)
                                            .padding(4)
                                            .background(.black.opacity(0.45))
                                            .foregroundColor(.white)
                                            .clipShape(Capsule())
                                            .padding(6)
                                    }
                                }
                                .frame(width: 170, height: 170, alignment: .top)
                                Text(info.name)
                                    .font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
                                    .lineLimit(2, reservesSpace: true)
                                if let c = info.creator {
                                    Text(c).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func load() async {
        isLoading = true
        error = nil
        let hs = (try? await session.api?.hotSearch()) ?? []
        let bs = (try? await session.api?.leaderboardBoards(platform: platform)) ?? []
        hotSearches = hs
        boards = bs
        isLoading = false
        if tags.isEmpty {
            tags = (try? await session.api?.songListTags()) ?? []
        }
        await loadLists()
    }

    private func loadBoards() async {
        if let b = try? await session.api?.leaderboardBoards(platform: platform) {
            boards = b
        }
    }

    private func loadLists() async {
        listLoading = true
        if let l = try? await session.api?.songListList(tag: selectedTag, page: 1) {
            lists = l
        }
        listLoading = false
    }
}

/// 榜单歌曲列表
struct BoardSongListView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var player: PlayerManager
    let board: LeaderboardBoard
    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else {
                ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                    SongRow(song: song, showCover: false, onTap: {
                        player.play(songs: songs, startIndex: idx)
                    }) {
                        AnyView(
                            HStack {
                                Text("\(idx + 1)")
                                    .font(.footnote.monospacedDigit())
                                    .foregroundColor(idx < 3 ? .red.opacity(0.85) : .secondary)
                                    .frame(width: 24)
                            }
                        )
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(board.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            songs = try await session.api?.leaderboardList(platform: board.platform, bangid: board.bangid) ?? []
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
