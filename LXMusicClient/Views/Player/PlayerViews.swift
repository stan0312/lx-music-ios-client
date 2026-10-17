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

/// 播放页内容翻页器：封面 + 歌词预览 + 歌曲信息 作为一个整体，
/// 在「播放进度条以上」的整块区域上下滑动，仿真一页一页翻动切歌。
struct PlayerPager: View {
    @EnvironmentObject var player: PlayerManager
    @Binding var showLyricsPage: Bool
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            ZStack {
                if dragOffset < 0, let ns = player.songAt(player.currentIndex + 1) {
                    block(song: ns).scaleEffect(0.94).offset(y: h + dragOffset)
                } else if dragOffset > 0, let ps = player.songAt(player.currentIndex - 1) {
                    block(song: ps).scaleEffect(0.94).offset(y: -h + dragOffset)
                }
                if let cs = player.currentSong {
                    block(song: cs).offset(y: dragOffset)
                }
            }
            .frame(height: h)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { v in dragOffset = v.translation.height }
                    .onEnded { v in
                        let dy = v.translation.height
                        if dy < -60 { commit(toNext: true, h: h) }
                        else if dy > 60 { commit(toNext: false, h: h) }
                        else { withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { dragOffset = 0 } }
                    }
            )
            .onChange(of: player.currentIndex) { _ in dragOffset = 0 }
        }
    }

    private func commit(toNext: Bool, h: CGFloat) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            dragOffset = toNext ? -h : h
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            if toNext { player.next() } else { player.previous() }
            dragOffset = 0
        }
    }

    /// 当前歌曲内容块：封面 + 歌词预览 + 歌曲信息
    private func block(song: Song) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 4)
            CoverImage(url: song.albumPic, width: 300, cornerRadius: 22, fallbackTitle: song.name)
                .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
            Spacer(minLength: 12)
            if song.id == player.currentSong?.id {
                lyricsPreview
            }
            Spacer(minLength: 8)
            songMetaText(song: song)
            Spacer(minLength: 4)
        }
        .frame(maxWidth: .infinity)
    }

    /// 封面下方直接显示的歌词预览（当前句 + 后两句）
    private var lyricsPreview: some View {
        let lines = previewLines()
        return VStack(spacing: 9) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Text(line.text.isEmpty ? " " : line.text)
                    .font(.system(.callout, design: .rounded))
                    .foregroundColor(i == player.activeLyricIndex ? .white : .white.opacity(0.5))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 30)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showLyricsPage = true } }
        .frame(maxHeight: 76, alignment: .top)
    }

    private func previewLines() -> [LyricLine] {
        guard !player.lyrics.isEmpty else { return [] }
        let idx = player.activeLyricIndex >= 0 ? player.activeLyricIndex : 0
        let start = min(idx, player.lyrics.count)
        let end = min(player.lyrics.count, start + 3)
        return Array(player.lyrics[start..<end])
    }

    private func songMetaText(song: Song) -> some View {
        ZStack {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(song.name)
                        .font(.system(.title3, design: .rounded)).bold().foregroundColor(.white)
                        .lineLimit(1)
                    Text(song.singer)
                        .font(.subheadline).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
            // 中间：音乐品质
            if let q = song.quality, !q.isEmpty {
                Text(q).font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.white.opacity(0.18)).foregroundColor(.white)
                    .clipShape(Capsule())
            }
        }
    }
}

/// 全屏播放页（汽水音乐风格）
/// 顶部栏 → 内容翻页（封面+歌词预览+歌曲信息，进度条以上整块上下滑切歌）→ 操作行 → 进度条 → 底部导航（推荐 | 播放/暂停 | 我的）。
/// 点击歌词预览进入歌词页，再次点击返回。
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
                Spacer(minLength: 2)
                ZStack {
                    if showLyricsPage {
                        lyricsPage
                            .transition(.opacity)
                    } else {
                        PlayerPager(showLyricsPage: $showLyricsPage)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: showLyricsPage)
                actionRow
                progressBar
                bottomBar
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
            Spacer()
            Button { showSearch = true } label: {
                Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    /// 歌词页（点击返回主界面；右下角可前后微调歌词偏移）
    private var lyricsPage: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 24) {
                        ForEach(Array(player.lyrics.enumerated()), id: \.element.id) { idx, line in
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(.body, design: .rounded))
                                .foregroundColor(idx == player.activeLyricIndex ? .white : .white.opacity(0.4))
                                .fontWeight(idx == player.activeLyricIndex ? .semibold : .regular)
                                .id(idx)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 12).padding(.horizontal, 30)
                }
                .onChange(of: player.activeLyricIndex) { idx in
                    if idx >= 0 { withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(idx, anchor: .center) } }
                }
                .overlay {
                    if player.lyrics.isEmpty {
                        Text("暂无歌词").font(.footnote).foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { showLyricsPage = false } }

            // 右下角：歌词前移 / 后移（按歌本地记忆偏移）
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    lyricOffsetControl
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 16)
        }
    }

    /// 歌词微调控件：〈 −0.5s | 当前偏移 | +0.5s 〉
    private var lyricOffsetControl: some View {
        HStack(spacing: 10) {
            Button { player.shiftLyricBackward() } label: {
                Image(systemName: "lessthan")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text(lyricOffsetText)
                .font(.caption.monospacedDigit())
                .foregroundColor(.white.opacity(0.85))
                .frame(minWidth: 64)
                .onTapGesture { player.setLyricOffset(0, for: player.currentSong ?? Song(id: "x", name: "", singer: "", source: "custom")) }

            Button { player.shiftLyricForward() } label: {
                Image(systemName: "greaterthan")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var lyricOffsetText: String {
        let v = player.currentLyricOffset
        if v == 0 { return "0s" }
        return String(format: "%+.1fs", v)
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
        .padding(.top, 6)
        .padding(.bottom, 2)
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
                Text(timeText(player.duration)).font(.caption2.monospacedDigit()).foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    /// 底部导航：推荐（左）| 播放/暂停（中）| 我的（右）
    private var bottomBar: some View {
        HStack {
            tabButton(index: 0, title: "推荐", icon: "music.note.house.fill")
            Spacer()
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 50)).foregroundColor(.white)
            }
            .buttonStyle(.plain)
            Spacer()
            tabButton(index: 1, title: "我的", icon: "person.fill")
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 2)
    }

    private func tabButton(index: Int, title: String, icon: String) -> some View {
        Button { onNavigate?(index) } label: {
            VStack(spacing: 2) {
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

    /// 背景氛围色：优先取封面主色（含缓存），无封面时用歌名生成的氛围色
    private func extractDominantColor() {
        guard let song = player.currentSong else { return }
        let fallback = Color(hue: hueFrom(song.name), saturation: 0.72, brightness: 0.6)
        guard let pic = song.albumPic, let u = URL(string: pic) else {
            bgColor = fallback
            return
        }
        Task.detached(priority: .utility) {
            var data: Data?
            if let cached = URLCache.shared.cachedResponse(for: URLRequest(url: u))?.data {
                data = cached
            } else {
                data = try? Data(contentsOf: u)
            }
            if let data, let img = UIImage(data: data), let avg = UIImage.averageColor(img) {
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
