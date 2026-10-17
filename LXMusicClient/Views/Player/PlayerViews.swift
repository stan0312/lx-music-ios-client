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
                        CoverImage(url: player.currentSong?.albumPic, width: 44, cornerRadius: 8,
                                   fallbackTitle: player.currentSong?.name ?? "")
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

/// 纵向翻页切歌（仿真一页一页上下翻动）
/// 跟随手指位移，松手后弹跳到上一首/下一首。
struct CoverPager: View {
    @EnvironmentObject var player: PlayerManager
    @State private var dragOffset: CGFloat = 0

    private let size: CGFloat = 264
    private let spacing: CGFloat = 14

    var body: some View {
        ZStack {
            if dragOffset < 0, let ns = player.songAt(player.currentIndex + 1) {
                page(song: ns)
                    .scaleEffect(0.9)
                    .offset(y: size + spacing + dragOffset)
            } else if dragOffset > 0, let ps = player.songAt(player.currentIndex - 1) {
                page(song: ps)
                    .scaleEffect(0.9)
                    .offset(y: -(size + spacing) + dragOffset)
            }
            if let cs = player.currentSong {
                page(song: cs)
                    .offset(y: dragOffset)
            }
        }
        .frame(height: size + spacing)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in dragOffset = v.translation.height }
                .onEnded { v in
                    let dy = v.translation.height
                    if dy < -60 { commit(toNext: true) }
                    else if dy > 60 { commit(toNext: false) }
                    else { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { dragOffset = 0 } }
                }
        )
        .onChange(of: player.currentIndex) { _ in dragOffset = 0 }
    }

    private func commit(toNext: Bool) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            dragOffset = toNext ? -(size + spacing) : (size + spacing)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            if toNext { player.next() } else { player.previous() }
            dragOffset = 0
        }
    }

    private func page(song: Song) -> some View {
        CoverImage(url: song.albumPic, width: size, cornerRadius: 20, fallbackTitle: song.name)
            .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
    }
}

/// 全屏播放页（汽水音乐风格）
/// 中部：封面纵向翻页切歌 / 点击“歌词”进入歌词页；背景取封面氛围色；
/// 底部：喜欢 / 评论 / 定时 / 三点菜单 → 进度条 → 播放暂停 → 底部导航（推荐 | 我的）。
struct FullPlayerView: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var session: AppSession
    var onClose: () -> Void = {}
    var onNavigate: ((Int) -> Void)? = nil
    @State private var showLyricsPage = false
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
                Spacer(minLength: 6)
                centralArea
                Spacer(minLength: 4)
                songMeta
                actionRow
                progressBar
                playRow
                bottomTabBar
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

    /// 中部：封面翻页 或 歌词页（点击“歌词”进入）
    private var centralArea: some View {
        ZStack {
            if showLyricsPage {
                lyricsPage.transition(.opacity)
            } else {
                CoverPager()
                    .transition(.opacity)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showLyricsPage = true } }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showLyricsPage)
    }

    private var background: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemBackground)
                LinearGradient(colors: [bgColor.opacity(0.9), bgColor.opacity(0.55), .black],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(Color.black.opacity(0.2))
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
        .padding(.top, 8)
    }

    private var lyricsPage: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 22) {
                    ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { idx, line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(idx == player.activeLyricIndex ? .white : .white.opacity(0.4))
                            .fontWeight(idx == player.activeLyricIndex ? .semibold : .regular)
                            .id(idx)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 10).padding(.horizontal, 28)
            }
            .frame(height: 300)
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
                Button { withAnimation(.easeInOut(duration: 0.25)) { showLyricsPage.toggle() } } label: {
                    Label(showLyricsPage ? "封面" : "歌词", systemImage: showLyricsPage ? "photo" : "text.quote")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.white.opacity(0.18)).foregroundColor(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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
        .padding(.top, 6)
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
        .padding(.top, 8)
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
        .padding(.top, 6)
    }

    /// 主控制：中间播放 / 暂停（位于底部导航之上，与汽水音乐高度一致）
    private var playRow: some View {
        HStack {
            Spacer()
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 60)).foregroundColor(.white)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    /// 底部导航：推荐（左） | 我的（右）
    private var bottomTabBar: some View {
        HStack {
            tabButton(index: 0, title: "推荐", icon: "music.note.house.fill")
            Spacer()
            tabButton(index: 1, title: "我的", icon: "person.fill")
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 4)
        .background(GlassBackground())
    }

    private func tabButton(index: Int, title: String, icon: String) -> some View {
        Button { onNavigate?(index) } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 22))
                Text(title).font(.caption2)
            }
            .foregroundColor(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
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

    /// 背景氛围色：优先取封面主色，无封面时用歌名生成的氛围色
    private func extractDominantColor() {
        guard let song = player.currentSong else { return }
        let fallback = Color(hue: hueFrom(song.name), saturation: 0.72, brightness: 0.6)
        guard let pic = song.albumPic, let u = URL(string: pic) else {
            bgColor = fallback
            return
        }
        Task.detached(priority: .utility) {
            if let data = try? Data(contentsOf: u),
               let img = UIImage(data: data),
               let avg = UIImage.averageColor(img) {
                DispatchQueue.main.async { bgColor = Color(uiColor: avg) }
            } else {
                DispatchQueue.main.async { bgColor = fallback }
            }
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
                CoverImage(url: song?.albumPic, width: 140, cornerRadius: 16, fallbackTitle: song?.name ?? "")
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
