import SwiftUI

/// 搜索页：联想提示 + 热搜 + 多源结果
struct SearchView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var player: PlayerManager
    var initialKeyword: String = ""

    @State private var keyword = ""
    @State private var source: String? = nil
    @State private var results: [Song] = []
    @State private var tips: [String] = []
    @State private var hotSearches: [String] = []
    @State private var isLoading = false
    @State private var searched = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private let sources: [String?] = [nil, "kw", "kg", "tx", "wy", "mg"]

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            sourceChips
            content
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if keyword.isEmpty && !initialKeyword.isEmpty {
                keyword = initialKeyword
                await search()
            }
            if hotSearches.isEmpty, let h = try? await session.api?.hotSearch() {
                hotSearches = Array(h.prefix(12))
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索歌曲、歌手", text: $keyword)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .textInputAutocapitalization(.never)
                if !keyword.isEmpty {
                    Button {
                        keyword = ""
                        results = []
                        searched = false
                    } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onChange(of: keyword) { new in
                Task { await loadTips(new) }
            }
            if focused {
                Button("取消") { focused = false; keyword = ""; results = [] }
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var sourceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sources, id: \.self) { s in
                    Button {
                        source = s
                        if searched { Task { await search() } }
                    } label: {
                        Text(s == nil ? "全部" : sourceName(s!))
                            .font(.subheadline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(source == s ? Color.accentColor : Color(.secondarySystemBackground))
                            .foregroundColor(source == s ? .white : .primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var content: some View {
        if keyword.isEmpty && !searched {
            // 热搜
            VStack(alignment: .leading, spacing: 12) {
                Text("热门搜索").font(.headline).padding(.horizontal, 16).padding(.top, 8)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(hotSearches.enumerated()), id: \.element) { idx, kw in
                            Button {
                                keyword = kw
                                Task { await search() }
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(idx + 1)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(idx < 3 ? .red.opacity(0.85) : .secondary)
                                        .frame(width: 22)
                                    Text(kw).font(.subheadline).foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        } else if !tips.isEmpty && keyword.count > 0 && !searched {
            // 联想提示
            List {
                ForEach(tips, id: \.self) { tip in
                    Button {
                        keyword = tip
                        Task { await search() }
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                            Text(tip).foregroundColor(.primary)
                        }
                    }
                }
            }
            .listStyle(.plain)
        } else if isLoading {
            LoadingView()
        } else if let error {
            ErrorView(message: error) { Task { await search() } }
        } else if results.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "music.quarternote.3").font(.system(size: 40)).foregroundColor(.gray)
                Text("没有找到相关歌曲").font(.subheadline).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(results) { song in
                    SongRow(song: song, onTap: {
                        player.play(songs: results, startIndex: results.firstIndex(of: song) ?? 0)
                    }) {
                        AnyView(Image(systemName: "play.circle")
                            .foregroundColor(.accentColor).font(.title3))
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func loadTips(_ kw: String) async {
        guard !kw.isEmpty, !searched else { return }
        if let t = try? await session.api?.tipSearch(keyword: kw) {
            tips = t
        }
    }

    private func search() async {
        guard !keyword.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        focused = false
        tips = []
        searched = true
        isLoading = true
        error = nil
        do {
            if let s = source, !s.isEmpty {
                results = try await session.api?.search(keyword: keyword, source: s) ?? []
            } else {
                // “全部”：多音源并发合并，避免单一音源不可用导致空结果
                results = try await session.api?.searchAll(keyword: keyword) ?? []
            }
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}
