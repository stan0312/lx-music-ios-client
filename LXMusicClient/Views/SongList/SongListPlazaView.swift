import SwiftUI

/// 歌单广场（歌单 Tab）
struct SongListPlazaView: View {
    @EnvironmentObject var session: AppSession
    @State private var tags: [SongListTag] = []
    @State private var lists: [SongListInfo] = []
    @State private var selectedTag: String? = nil
    @State private var isLoading = true
    @State private var error: String?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("歌单广场")
                        .font(.system(.title, design: .rounded)).bold()
                        .padding(.horizontal, 16).padding(.top, 8)

                    tagChips
                    if isLoading {
                        LoadingView().frame(height: 260)
                    } else if let error {
                        ErrorView(message: error) { Task { await loadLists() } }
                            .frame(height: 220)
                    } else {
                        listGrid
                    }
                }
            }
            .navigationDestination(for: SongListInfo.self) { info in
                SongListDetailView(songList: info)
            }
        }
        .task {
            if tags.isEmpty {
                tags = try? await session.api?.songListTags() ?? []
            }
            await loadLists()
        }
    }

    private var tagChips: some View {
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
    }

    private var listGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 18) {
            ForEach(lists) { info in
                Button {
                    path.append(info)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack(alignment: .bottomLeading) {
                            CoverImage(url: info.cover, width: 170, cornerRadius: 12)
                            if info.playCount > 0 {
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

    private func loadLists() async {
        isLoading = true
        error = nil
        do {
            lists = try await session.api?.songListList(tag: selectedTag, page: 1) ?? []
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

/// 歌单详情
struct SongListDetailView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var player: PlayerManager
    let songList: SongListInfo
    @State private var songs: [Song] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            header
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else {
                ForEach(songs) { song in
                    SongRow(song: song, onTap: {
                        player.play(songs: songs, startIndex: songs.firstIndex(of: song) ?? 0)
                    }) {
                        AnyView(Image(systemName: "play.circle")
                            .foregroundColor(.accentColor).font(.title3))
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(songList.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            CoverImage(url: songList.cover, width: 96, cornerRadius: 12)
            VStack(alignment: .leading, spacing: 6) {
                Text(songList.name).font(.headline).lineLimit(2)
                if let c = songList.creator {
                    Text("创建者：\(c)").font(.caption).foregroundColor(.secondary)
                }
                Text("共 \(songs.count) 首").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .listRowSeparator(.hidden)
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            songs = try await session.api?.songListDetail(id: songList.id) ?? []
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
