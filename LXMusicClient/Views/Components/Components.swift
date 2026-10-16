import SwiftUI

// MARK: - 封面图（兼容 http 内网地址）
struct CoverImage: View {
    let url: String?
    let width: CGFloat
    let cornerRadius: CGFloat

    init(url: String?, width: CGFloat, cornerRadius: CGFloat = 10) {
        self.url = url
        self.width = width
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                AsyncImage(url: u, transaction: Transaction(animation: .easeOut)) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        placeholder.opacity(0.6)
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: width)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: width * 0.3, weight: .light))
                .foregroundColor(.white.opacity(0.7))
        }
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
