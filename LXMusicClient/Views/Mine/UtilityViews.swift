import SwiftUI

/// 缓存管理
struct CacheView: View {
    @EnvironmentObject var session: AppSession
    @State private var stats: CacheStats?
    @State private var items: [CacheItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var showClearConfirm = false

    var body: some View {
        List {
            if let stats {
                Section("统计") {
                    HStack {
                        Label("缓存文件", systemImage: "externaldrive")
                        Spacer()
                        Text("\(stats.fileCount ?? 0) 个").foregroundColor(.secondary)
                    }
                    HStack {
                        Label("占用空间", systemImage: "internaldrive")
                        Spacer()
                        Text(stats.sizeText).foregroundColor(.secondary)
                    }
                }
            }
            Section("操作") {
                Button(role: .destructive) { showClearConfirm = true } label: {
                    Label("清空全部缓存", systemImage: "trash")
                }
            }
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if items.isEmpty {
                Text("暂无缓存文件").font(.footnote).foregroundColor(.secondary)
                    .listRowSeparator(.hidden)
            } else {
                Section("文件列表（\(items.count)）") {
                    ForEach(items) { item in
                        HStack {
                            Text(item.name).font(.subheadline).lineLimit(1)
                            if let s = item.singer { Text("· \(s)").font(.caption).foregroundColor(.secondary).lineLimit(1) }
                            Spacer()
                            if let size = item.size {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("缓存管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .alert("清空缓存", isPresented: $showClearConfirm) {
            Button("清空", role: .destructive) { Task { await clear() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除服务器上该用户的所有缓存文件（歌词与音频）。")
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            if let api = session.api {
                stats = try await api.cacheStats()
                items = try await api.cacheList()
            }
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func clear() async {
        try? await session.api?.cacheClear()
        items = []
        stats = nil
        await load()
    }
}

/// 快照备份
struct BackupView: View {
    @EnvironmentObject var session: AppSession
    @State private var snapshots: [String] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
            } else if let error {
                ErrorView(message: error) { Task { await load() } }
            } else if snapshots.isEmpty {
                VStack(spacing: 10) {
                    Text("暂无快照").font(.subheadline).foregroundColor(.secondary)
                    Text("快照用于备份与恢复你的歌单数据，可在 LX Music 客户端触发。")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding().listRowSeparator(.hidden)
            } else {
                Section("已有快照（\(snapshots.count)）") {
                    ForEach(snapshots, id: \.self) { s in
                        HStack {
                            Text(s).font(.subheadline)
                            Spacer()
                            Button("恢复") {
                                Task { try? await session.api?.restoreSnapshot(id: s); await load() }
                            }.font(.subheadline).foregroundColor(.accentColor)
                            Button("删除", role: .destructive) {
                                Task { try? await session.api?.deleteSnapshot(id: s); await load() }
                            }.font(.subheadline)
                        }
                    }
                }
            }
            Section("操作") {
                Button {
                    Task { try? await session.api?.uploadSnapshot(); await load() }
                } label: {
                    Label("立即上传当前快照", systemImage: "arrow.up.icloud")
                }
            }
        }
        .navigationTitle("快照备份")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            snapshots = try await session.api?.snapshots() ?? []
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }
}

/// 播放与外观设置
struct SettingsView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var player: PlayerManager
    @AppStorage("lx.quality") var quality: String = "128k"
    @State private var cacheSizeText = LocalCache.shared.sizeText()
    @State private var showDiagnosis = false
    @AppStorage("lx.downloadFileName") private var downloadFileName = "歌名 - 歌手"
    @AppStorage("lx.downloadWriteLyric") private var downloadWriteLyric = true
    @State private var downloadSize = DownloadManager.sizeText()
    @State private var shareItems: [URL] = []
    @State private var showShare = false

    private let qualities = ["128k", "320k", "flac", "flac24bit", "master"]

    var body: some View {
        Form {
            Section("播放音质") {
                Picker("默认音质", selection: $quality) {
                    ForEach(qualities, id: \.self) { q in
                        Text(qualityName(q)).tag(q)
                    }
                }
                .pickerStyle(.inline)
                .onChange(of: quality) { new in
                    player.setQuality(new)
                }
                Text("切换后下一首播放生效")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("外观") {
                Toggle("深色模式", isOn: Binding(
                    get: { session.isDark },
                    set: { session.setDark($0) }
                ))
            }
            Section("缓存") {
                Toggle("启用歌曲缓存", isOn: Binding(
                    get: { LocalCache.enableSongCache },
                    set: { LocalCache.enableSongCache = $0 }
                ))
                LabeledContent("已用缓存", value: cacheSizeText)
                Button("清除缓存") {
                    LocalCache.shared.clear()
                    cacheSizeText = LocalCache.shared.sizeText()
                }
            }
            Section("下载") {
                TextField("文件名模板", text: $downloadFileName)
                    .autocorrectionDisabled()
                Text("用 歌名 / 歌手 作占位，如：歌名 - 歌手。")
                    .font(.caption).foregroundColor(.secondary)
                Toggle("同时写入 .lrc 歌词", isOn: $downloadWriteLyric)
                LabeledContent("已下载", value: downloadSize)
                Button("打开下载文件夹") { openDownloads() }
            }
            Section("关于") {
                Button("在线音源诊断") { showDiagnosis = true }
                    .foregroundColor(.accentColor)
                LabeledContent("客户端", value: "LX 音乐 iOS 客户端")
                LabeledContent("服务器", value: session.config?.displayHost ?? "-")
                if let p = session.config?.playerPath {
                    LabeledContent("播放器路径", value: p.isEmpty ? "/" : p)
                }
            }
            Section {
                Button("退出登录", role: .destructive) { session.logout() }
            }
        }
        .sheet(isPresented: $showDiagnosis) { SourceDiagnosisView() }
        .sheet(isPresented: $showShare) { ActivityView(items: shareItems) }
        .onAppear {
            cacheSizeText = LocalCache.shared.sizeText()
            downloadSize = DownloadManager.sizeText()
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    func qualityName(_ q: String) -> String {
        switch q {
        case "128k": return "标准 128K"
        case "320k": return "高品质 320K"
        case "flac": return "无损 FLAC"
        case "flac24bit": return "Hi-Res FLAC 24bit"
        case "master": return "母带"
        default: return q
        }
    }

    private func openDownloads() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: DownloadManager.downloadsDir,
                                                 includingPropertiesForKeys: nil,
                                                 options: [.skipsHiddenFiles])) ?? []
        if files.isEmpty {
            if let root = rootViewController() {
                let alert = UIAlertController(title: "下载文件夹", message: "还没有下载的文件", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "好", style: .default))
                root.present(alert, animated: true)
            }
        } else {
            shareItems = files
            showShare = true
        }
    }

    private func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
            .first?.rootViewController
    }
}

/// 服务器信息
struct AboutView: View {
    @EnvironmentObject var session: AppSession
    @State private var config: [String: Any] = [:]

    var body: some View {
        List {
            Section("连接信息") {
                LabeledContent("服务器", value: session.config?.displayHost ?? "-")
                LabeledContent("用户名", value: session.config?.username.isEmpty ?? true ? "未登录" : session.config!.username)
                LabeledContent("播放器认证", value: session.config?.enableAuth == true ? "已开启" : "未开启")
            }
            if !config.isEmpty {
                Section("服务器配置") {
                    ForEach(Array(config.keys).sorted(), id: \.self) { key in
                        LabeledContent(key) {
                            Text(String(describing: config[key] ?? "")).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("服务器信息")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            config = (try? await session.api?.getPlayerConfig()) ?? [:]
        }
    }
}

/// 提示去登录用户账号
struct LoginPromptView: View {
    @EnvironmentObject var session: AppSession
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 46)).foregroundColor(.accentColor)
            Text("登录用户账号后可使用同步歌单、收藏与缓存功能")
                .font(.headline).multilineTextAlignment(.center)
            Text("当前以游客身份浏览。请重新配置连接并勾选“登录用户账号”。")
                .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
            Button("重新配置连接") { session.logout() }
                .buttonStyle(.borderedProminent).tint(.accentColor)
        }
        .padding(24)
    }
}

/// 在线音源诊断：逐音源探测服务端在线源是否可用（帮助定位“推荐/搜索/评论为什么空”）
struct SourceDiagnosisView: View {
    @EnvironmentObject var session: AppSession
    @State private var results: [SourceDiagnosis] = []
    @State private var isLoading = false
    @State private var note = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            List {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden)
                } else {
                    ForEach(results, id: \.source) { r in
                        HStack {
                            Text(sourceName(r.source)).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(r.detail).font(.caption).foregroundColor(.secondary)
                            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(r.ok ? .green : .red)
                        }
                    }
                    Section {
                        Text(note).font(.footnote).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("在线音源诊断")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { await run() }
    }

    private func run() async {
        guard let api = session.api else { note = "未连接服务器"; return }
        isLoading = true
        results = await api.diagnoseSources()
        isLoading = false
        let okCount = results.filter(\.ok).count
        note = okCount == 0
            ? "所有在线音源均不可用——推荐/排行榜/搜索/评论都会是空的。请检查服务器能否访问对应平台（看服务端 debug.txt）。"
            : "\(okCount)/\(results.count) 个音源可用。可用音源的推荐/搜索/评论可正常使用；自定义目录歌曲没有评论数据。"
    }
}

/// UIActivityViewController 包装（分享/打开下载文件）
struct ActivityView: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
