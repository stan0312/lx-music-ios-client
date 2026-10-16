import SwiftUI
import UIKit

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
/// 顶栏：收起 + 标题 + 搜索；封面取色背景、上下滑切歌、点封面切歌词；
/// 底部：喜欢 / 评论 / 定时 / 三点菜单（删除、不喜欢），进度条，中间播放暂停。
struct FullPlayerView: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var session: AppSession
    var onClose: () -> Void = {}
    @State private var showLyrics = true
    @State private var showComment = false
    @State private var showSearch = false
    @State private var bgColor: Color = .accentColor
    @State private var commentCount: Int?
    @State private var toast: String?

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 10)
                coverView
                    .gesture(verticalSwipe)
                Spacer(minLength: 14)
                if showLyrics { lyricsView }
                songMeta
                actionRow
                progressBar
                playRow
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.black.opacity(0.6))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(.top, 60)
            }
        }
        .sheet(isPresented: $showComment) { CommentSheet(song: player.currentSong) }
        .fullScreenCover(isPresented: $showSearch) {
            NavigationStack {
                SearchView(initialKeyword: "")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { showSearch = false } }
                    }
            }
        }
        .task(id: player.currentSong?.id) {
            bgColor = .accentColor
            commentCount = nil
            extractDominantColor()
            loadCommentCount()
        }
    }

    /// 上下滑切歌（上一首 / 下一首）
    private var verticalSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dy = value.translation.height
                if dy < -60 { player.next() }
                else if dy > 60 { player.previous() }
            }
    }

    private var background: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemBackground)
                LinearGradient(colors: [bgColor.opacity(0.85), bgColor.opacity(0.55), .black],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(Color.black.opacity(0.22))
            .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { onClose() } label: {
                Image(systemName: "chevron.down").font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            Text("LX 音乐").font(.system(.headline, design: .rounded)).bold().foregroundColor(.white)
            Spacer()
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(.black.opacity(0.3))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    private var coverView: some View {
        VStack(spacing: 8) {
            CoverImage(url: player.currentSong?.albumPic, width: 268, cornerRadius: 20)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
            Text(showLyrics ? "轻点封面查看歌词" : "轻点封面查看封面")
                .font(.caption2).foregroundColor(.white.opacity(0.55))
                .padding(.top, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) { showLyrics.toggle() }
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
                .padding(.vertical, 8)
                .padding(.horizontal, 24)
            }
            .frame(maxHeight: 150)
            .onChange(of: player.activeLyricIndex) { idx in
                if idx >= 0 { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(idx, anchor: .center) } }
            }
            .overlay {
                if player.lyrics.isEmpty {
                    Text("暂无歌词").font(.footnote).foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }

    private var songMeta: some View {
        VStack(spacing: 6) {
            Text(player.currentSong?.name ?? "")
                .font(.system(.title2, design: .rounded)).bold().foregroundColor(.white)
                .lineLimit(1)
            Text(player.currentSong?.singer ?? "")
                .font(.subheadline).foregroundColor(.white.opacity(0.8)).lineLimit(1)
            HStack(spacing: 6) {
                if let q = player.currentSong?.quality, !q.isEmpty {
                    Text(q).font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.white.opacity(0.18)).foregroundColor(.white)
                        .clipShape(Capsule())
                }
                Text(player.currentSong?.sourceName ?? "")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.white.opacity(0.18)).foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(.top, 8)
    }

    /// 喜欢 / 评论 / 定时 / 三点菜单
    private var actionRow: some View {
        HStack(spacing: 0) {
            Button { toggleCurrentLike() } label: {
                imageWithLabel(currentSongIsLiked ? "heart.fill" : "heart",
                               currentSongIsLiked ? "已喜欢" : "喜欢")
                    .foregroundColor(currentSongIsLiked ? Color.pink : .white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Spacer()
            Button { showComment = true } label: {
                imageWithLabel("bubble.left", "评论").foregroundColor(.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Spacer()
            Menu {
                Button("关闭定时", action: { player.cancelSleepTimer() })
                Divider()
                Button("15 分钟") { player.startSleepTimer(minutes: 15) }
                Button("30 分钟") { player.startSleepTimer(minutes: 30) }
                Button("60 分钟") { player.startSleepTimer(minutes: 60) }
            } label: {
                imageWithLabel("clock", sleepTimerText).foregroundColor(.white.opacity(0.85))
            }

            Spacer()
            Menu {
                Button(role: .destructive) { dislikeCurrentSong() } label: {
                    Label("不喜欢 · 不推荐", systemImage: "hand.thumbsdown")
                }
                Divider()
                Button(role: .destructive) { player.removeCurrentFromQueue() } label: {
                    Label("删除这首歌曲", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var currentSongIsLiked: Bool {
        guard let s = player.currentSong, !s.id.isEmpty else { return false }
        return player.isLiked(s)
    }

    private func toggleCurrentLike() {
        guard let s = player.currentSong, !s.id.isEmpty else { return }
        player.toggleLike(s)
    }

    private var sleepTimerText: String {
        guard let r = player.sleepRemaining, r > 0 else { return "定时" }
        let t = Int(r)
        if t >= 60 { return "\(t / 60)分" }
        return "\(t)秒"
    }

    /// 把当前歌曲加入“不喜欢”黑名单并跳过
    private func dislikeCurrentSong() {
        guard let song = player.currentSong, let api = session.api else { return }
        Task {
            do {
                try await api.dislikeAdd(song: song)
                showToast("已加入“不喜欢”黑名单")
                player.removeCurrentFromQueue()
            } catch {
                showToast("操作失败：\(error.localizedDescription)")
            }
        }
    }

    private func showToast(_ msg: String) {
        toast = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if toast == msg { toast = nil }
        }
    }

    private var progressBar: some View {
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
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// 主控制：中间播放 / 暂停（无左右切歌按钮）
    private var playRow: some View {
        HStack {
            Spacer()
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 62)).foregroundColor(.white)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 2)
        .padding(.bottom, 14)
    }

    private func imageWithLabel(_ icon: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 20))
            Text(label).font(.caption2)
        }
    }

    private func timeText(_ t: Double) -> String {
        guard t.isFinite, t >= 0 else { return "00:00" }
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func extractDominantColor() {
        guard let pic = player.currentSong?.albumPic, let u = URL(string: pic) else { return }
        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: u),
                  let img = UIImage(data: data),
                  let avg = UIImage.averageColor(img) else { return }
            DispatchQueue.main.async { bgColor = Color(uiColor: avg) }
        }
    }

    private func loadCommentCount() {
        guard let song = player.currentSong else { return }
        Task {
            let list = (try? await session.api?.comment(song: song)) ?? []
            commentCount = list.count
        }
    }
}

// MARK: - 封面主色提取（汽水音乐式背景）
extension UIImage {
    /// 缩到 1x1 采样平均色
    static func averageColor(_ image: UIImage) -> UIColor? {
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        let color = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cg = color.cgImage, let provider = cg.dataProvider,
              let cf = provider.data else { return nil }
        let bytes = [UInt8](cf as Data)
        guard bytes.count >= 4 else { return nil }
        return UIColor(red: CGFloat(bytes[0]) / 255, green: CGFloat(bytes[1]) / 255,
                       blue: CGFloat(bytes[2]) / 255, alpha: 1)
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
            comments = (try? await session.api?.comment(song: song)) ?? []
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
                            do {
                                let u = try await api.musicURL(song: song, quality: session.quality)
                                try await api.cacheDownload(song: song, streamURL: u, quality: session.quality)
                            } catch { }
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
