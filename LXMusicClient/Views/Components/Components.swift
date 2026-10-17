import SwiftUI

// MARK: - 可靠封面加载（URLSession + 磁盘缓存，替换 AsyncImage 解决 LAN 封面加载不稳定）
struct RemoteImage: View {
    let url: URL?
    var fallback: AnyView?

    @State private var ui: UIImage?
    @State private var loading = true

    var body: some View {
        Group {
            if let ui {
                Image(uiImage: ui).resizable().scaledToFill()
            } else if loading {
                ZStack {
                    Color.gray.opacity(0.12)
                    ProgressView().tint(.white.opacity(0.6))
                }
            } else {
                fallback ?? AnyView(EmptyView())
            }
        }
        .task(id: url?.absoluteString) { load() }
    }

    private func load() {
        guard let url else { loading = false; ui = nil; return }
        let req = URLRequest(url: url)
        if let cached = URLCache.shared.cachedResponse(for: req)?.data,
           let img = UIImage(data: cached) {
            ui = img; loading = false
            return
        }
        loading = true
        URLSession.shared.dataTask(with: req) { data, resp, err in
            DispatchQueue.main.async {
                loading = false
                if let data, let img = UIImage(data: data) {
                    ui = img
                    if let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                        URLCache.shared.storeCachedResponse(
                            CachedURLResponse(response: http, data: data), for: req)
                    }
                }
            }
        }.resume()
    }
}

// MARK: - 封面图（兼容 http 内网地址；无图时用歌名生成氛围渐变兜底）
struct CoverImage: View {
    let url: String?
    let width: CGFloat
    let cornerRadius: CGFloat
    let fallbackTitle: String

    init(url: String?, width: CGFloat, cornerRadius: CGFloat = 10, fallbackTitle: String = "") {
        self.url = url
        self.width = width
        self.cornerRadius = cornerRadius
        self.fallbackTitle = fallbackTitle
    }

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                RemoteImage(url: u, fallback: AnyView(fallback))
            } else {
                fallback
            }
        }
        .frame(width: width, height: width)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder private var fallback: some View {
        if fallbackTitle.isEmpty {
            ZStack {
                LinearGradient(
                    colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.12)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: width * 0.3, weight: .light))
                    .foregroundColor(.white.opacity(0.7))
            }
        } else {
            gradientFallback(title: fallbackTitle, width: width)
        }
    }
}

/// 由字符串确定性生成色相（0...1），保证同名歌曲恒定同色
func hueFrom(_ s: String) -> CGFloat {
    var h: UInt64 = 5381
    for b in s.utf8 { h = (h &* 33) &+ UInt64(b) }
    return CGFloat(h % 360) / 360
}

/// 歌名生成的氛围渐变封面（汽水音乐式：无内嵌封面时自动补一张）
func gradientFallback(title: String, width: CGFloat) -> some View {
    let hue = hueFrom(title)
    let c1 = Color(hue: hue, saturation: 0.72, brightness: 0.82)
    let c2 = Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.72, brightness: 0.55)
    return ZStack {
        LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
        Text(String(title.prefix(1)).uppercased())
            .font(.system(size: width * 0.32, weight: .bold))
            .foregroundColor(.white.opacity(0.9))
    }
}

// MARK: - 来源标签
struct SourceBadge: View {
    let source: String
    var body: some View {
        Text(sourceName(source))
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12))
            .foregroundColor(.accentColor)
            .clipShape(Capsule())
    }
}

func sourceName(_ s: String) -> String {
    switch s {
    case "kw": return "酷我"
    case "kg": return "酷狗"
    case "tx": return "QQ"
    case "wy": return "网易"
    case "mg": return "咪咕"
    default: return s.uppercased()
    }
}

// MARK: - 歌曲行
struct SongRow: View {
    let song: Song
    var showCover: Bool = true
    var onTap: (() -> Void)? = nil
    var trailing: (() -> AnyView)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 12) {
                if showCover {
                    CoverImage(url: song.albumPic, width: 46, cornerRadius: 8)
                } else {
                    Image(systemName: "music.note")
                        .font(.title3)
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 24)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.name)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(song.displaySubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let trailing {
                    trailing()
                } else {
                    Text(song.durationText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 区块标题
struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.title3, design: .rounded)).bold()
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - 空态 / 加载态
struct LoadingView: View {
    var body: some View {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 44)).foregroundColor(.gray)
            Text(message).font(.subheadline).foregroundColor(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal)
            if let retry {
                Button("重试", action: retry)
                    .buttonStyle(.borderedProminent).tint(.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 迷你毛玻璃背景
struct GlassBackground: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .ignoresSafeArea()
    }
}

// MARK: - 播放队列 Sheet
struct QueueSheet: View {
    @EnvironmentObject var player: PlayerManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                ForEach(Array(player.queue.enumerated()), id: \.element.id) { idx, song in
                    HStack {
                        Text("\(idx + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(idx == player.currentIndex ? .accentColor : .secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.name).font(.subheadline)
                                .foregroundColor(idx == player.currentIndex ? .accentColor : .primary)
                                .lineLimit(1)
                            Text(song.singer).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(song.durationText).font(.caption).foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.currentIndex = idx
                        player.loadCurrentPublic()
                        dismiss()
                    }
                }
                .onMove { from, to in
                    player.queue.move(fromOffsets: from, toOffset: to)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("播放队列（\(player.queue.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension PlayerManager {
    /// 供 QueueSheet 直接切换（MainActor 安全）
    func loadCurrentPublic() { loadCurrent() }
}
