import SwiftUI

/// 底部迷你播放条
struct MiniPlayerView: View {
    @EnvironmentObject var player: PlayerManager
    var onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Button(action: onTap) {
                    HStack(spacing: 12) {
                        CoverImage(url: player.currentSong?.albumPic, width: 44, cornerRadius: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.currentSong?.name ?? "")
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(.primary).lineLimit(1)
                            Text(player.currentSong?.singer ?? "")
                                .font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill").font(.system(size: 16)).foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(GlassBackground())
        }
    }
}

/// 全屏播放页（汽水音乐风格）
struct FullPlayerView: View {
    @EnvironmentObject var player: PlayerManager
    var onClose: () -> Void = {}
    @State private var showLyrics = true
    @State private var showQueue = false
    @State private var showComment = false
    @State private var showDownload = false

    var body: some View {
        ZStack {
            // 模糊封面背景
            background
            VStack(spacing: 0) {
                topBar
                Spacer()
                if showLyrics {
                    coverView
                    Spacer()
                    lyricsView
                } else {
                    coverView
                        .padding(.top, 20)
                    Spacer()
                }
                bottomControls
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .topTrailing) {
            if showLyrics {
                Button {
                    withAnimation { showLyrics.toggle() }
                } label: {
                    Image(systemName: "text.quote")
                        .font(.system(size: 15))
                        .padding(10)
                        .background(.black.opacity(0.35))
                        .clipShape(Circle())
                }
                .padding(.top, 54).padding(.trailing, 16)
            }
        }
        .sheet(isPresented: $showQueue) { QueueSheet() }
        .sheet(isPresented: $showComment) { CommentSheet(song: player.currentSong) }
        .sheet(isPresented: $showDownload) { DownloadSheet(song: player.currentSong) }
    }

    private var background: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemBackground)
                if let pic = player.currentSong?.albumPic, let u = URL(string: pic) {
                    AsyncImage(url: u) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Color.accentColor.opacity(0.3)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                } else {
                    LinearGradient(colors: [Color.accentColor.opacity(0.5), .black],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .blur(radius: 60, opaque: true)
            .overlay(Color.black.opacity(0.25))
            .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            Spacer()
            Capsule().fill(.white.opacity(0.4)).frame(width: 38, height: 5)
            Spacer()
            // 占位保持居中
            Color.clear.frame(width: 24, height: 24).padding(.trailing, 16)
        }
        .padding(.top, 12)
    }

    private var coverView: some View {
        VStack(spacing: 8) {
            CoverImage(url: player.currentSong?.albumPic, width: 260, cornerRadius: 18)
                .shadow(color: .black.opacity(0.5), radius: 22, y: 12)
            Text(player.currentSong?.name ?? "")
                .font(.system(.title2, design: .rounded)).bold().foregroundColor(.white)
            Text(player.currentSong?.singer ?? "")
                .font(.subheadline).foregroundColor(.white.opacity(0.8))
        }
    }

    private var lyricsView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { idx, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(idx == player.activeLyricIndex ? .white : .white.opacity(0.45))
                            .fontWeight(idx == player.activeLyricIndex ? .semibold : .regular)
                            .id(idx)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 60)
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 210)
            .onChange(of: player.activeLyricIndex) { idx in
                if idx >= 0 { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(idx, anchor: .center) } }
            }
            .overlay {
                if player.lyrics.isEmpty {
                    Text("暂无歌词")
                        .font(.footnote).foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 14) {
            // 进度
            VStack(spacing: 4) {
                Slider(value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ), in: 0...max(player.duration, 1))
                .tint(.white)
                HStack {
                    Text(timeText(player.currentTime)).font(.caption2.monospacedDigit()).foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text(player.currentSong?.durationText ?? "--:--").font(.caption2.monospacedDigit()).foregroundColor(.white.opacity(0.7))
                }
            }

            // 控制
            HStack {
                Button { showQueue = true } label: { Image(systemName: "list.bullet").font(.title3).foregroundColor(.white.opacity(0.85)) }
                Spacer()
                Button { player.previous() } label: { Image(systemName: "backward.fill").font(.system(size: 26)).foregroundColor(.white) }
                Spacer()
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 62)).foregroundColor(.white)
                }
                Spacer()
                Button { player.next() } label: { Image(systemName: "forward.fill").font(.system(size: 26)).foregroundColor(.white) }
                Spacer()
                Menu {
                    ForEach([1.0, 1.25, 1.5, 2.0], id: \.self) { r in
                        Button(String(format: "%.2gx", r)) {
                            player.setRate(Float(r))
                        }
                    }
                } label: {
                    Text(String(format: "%.2gx", player.rate))
                        .font(.footnote.weight(.semibold)).foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 24)

            // 次级控制
            HStack(spacing: 26) {
                Button { showComment = true } label: { imageWithLabel("bubble.left", "评论") }
                Spacer()
                Button { showDownload = true } label: { imageWithLabel("arrow.down.circle", "下载") }
                Spacer()
                Button { showLyrics.toggle() } label: { imageWithLabel("text.quote", showLyrics ? "封面" : "歌词") }
            }
            .padding(.horizontal, 32)
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 18)
    }

    private func imageWithLabel(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 20))
            Text(label).font(.caption2)
        }
        .foregroundColor(.white.opacity(0.85))
    }

    private func timeText(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "00:00" }
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// 评论面板
struct CommentSheet: View {
    @EnvironmentObject var session: AppSession
    let song: Song?
    @State private var comments: [SongComment] = []
    @State private var isLoading = true
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    LoadingView()
                } else if comments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left").font(.system(size: 40)).foregroundColor(.gray)
                        Text("暂无评论").foregroundColor(.secondary)
                    }
                } else {
                    List(comments) { c in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(c.author).font(.subheadline.weight(.medium))
                                Spacer()
                                if let likes = c.likes {
                                    Text("👍 \(Int(likes))").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Text(c.content).font(.subheadline).foregroundColor(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("评论 · \(song?.name ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            guard let song else { isLoading = false; return }
            comments = try? await session.api?.comment(song: song) ?? []
            isLoading = false
        }
    }
}

/// 下载面板（使用服务器代理下载，注入 ID3 标签）
struct DownloadSheet: View {
    let song: Song?
    @State private var downloading = false
    @State private var done = false
    @EnvironmentObject var session: AppSession
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 18) {
                CoverImage(url: song?.albumPic, width: 140, cornerRadius: 16)
                Text(song?.name ?? "").font(.headline)
                Text(song?.singer ?? "").font(.subheadline).foregroundColor(.secondary)
                if done {
                    Label("已加入服务器下载队列", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button {
                        guard let api = session.api, let song else { return }
                        downloading = true
                        Task {
                            try? await api.cacheDownload(song: song)
                            downloading = false
                            done = true
                        }
                    } label: {
                        HStack {
                            if downloading { ProgressView() }
                            Text(downloading ? "请求中…" : "下载到服务器")
                        }.frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent).tint(.accentColor)
                    .disabled(downloading)
                    Text("歌曲将缓存在你的 lxserver 服务器上，可通过“缓存管理”查看。")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(28)
            .navigationTitle("下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
