import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: AppSession
    @EnvironmentObject var player: PlayerManager
    @State private var showFullPlayer = false
    @State private var showQueue = false
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if session.isLoggedIn {
                main
            } else {
                ServerSetupView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isLoggedIn)
        .task {
            // 启动时尝试用已保存配置自动连接
            if !session.isLoggedIn && !session.isConnecting {
                await session.tryRestore()
            }
        }
    }

    private var main: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem { Label("推荐", systemImage: "music.note.house.fill") }
                    .tag(0)
                MineView()
                    .tabItem { Label("我的", systemImage: "person.fill") }
                    .tag(1)
            }
            .tint(.accentColor)

            // 底部迷你播放条（有播放时显示）
            if player.currentSong != nil {
                MiniPlayerView { showFullPlayer = true }
                    .padding(.bottom, 2)
            }
        }
        .overlay {
            if showFullPlayer {
                FullPlayerView(onClose: { showFullPlayer = false },
                                onNavigate: { tab in
                                    selectedTab = tab
                                    showFullPlayer = false
                                })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .onAppear { autoResumeOnLaunch() }
    }

    /// 启动即播放：恢复到上次歌曲并打开播放页（汽水音乐风格）
    private func autoResumeOnLaunch() {
        guard session.isLoggedIn, player.currentSong == nil, player.hasSavedState else { return }
        player.restoreAndPlay()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.3)) { showFullPlayer = true }
        }
    }
}

/// 服务器连接设置页（首次进入）
struct ServerSetupView: View {
    @EnvironmentObject var session: AppSession
    @State private var url = ""
    @State private var playerPassword = ""
    @State private var username = ""
    @State private var userPassword = ""
    @State private var useUserLogin = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer().frame(height: 20)
                // 应用 Logo
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 92, height: 92)
                    Image(systemName: "music.note")
                        .font(.system(size: 42, weight: .medium))
                        .foregroundColor(.white)
                }
                .shadow(color: Color.accentColor.opacity(0.35), radius: 18, y: 10)

                VStack(spacing: 4) {
                    Text("LX 音乐").font(.system(.title2, design: .rounded)).bold()
                    Text("连接你的 lxserver 私有音乐服务")
                        .font(.subheadline).foregroundColor(.secondary)
                }

                // 服务器地址
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("服务器地址")
                    HStack {
                        Image(systemName: "server.rack")
                            .foregroundColor(.secondary)
                        TextField("http://192.168.1.100:9527", text: $url)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                    }
                    .modifier(InputField())
                }

                // 播放器访问密码
                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("播放器访问密码（可选）")
                    HStack {
                        Image(systemName: "lock.fill").foregroundColor(.secondary)
                        SecureField("服务器开启播放器密码认证时填写", text: $playerPassword)
                    }
                    .modifier(InputField())
                }

                // 用户同步登录
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $useUserLogin.animation()) {
                        fieldLabel("登录用户账号（用于歌单/收藏/缓存）")
                    }
                    .tint(.accentColor)
                    if useUserLogin {
                        HStack {
                            Image(systemName: "person.fill").foregroundColor(.secondary)
                            TextField("用户名", text: $username)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                        }
                        .modifier(InputField())
                        HStack {
                            Image(systemName: "key.fill").foregroundColor(.secondary)
                            SecureField("密码", text: $userPassword)
                        }
                        .modifier(InputField())
                    }
                }

                if let err = session.connectError {
                    Text(err).font(.footnote).foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }

                Button {
                    connect()
                } label: {
                    HStack {
                        if session.isConnecting { ProgressView().tint(.white) }
                        Text(session.isConnecting ? "连接中…" : "连接")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isConnecting || url.trimmingCharacters(in: .whitespaces).isEmpty)

                Text("提示：连接地址即 lxserver 的访问地址（默认端口 9527）。")
                    .font(.caption2).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            if let cfg = session.config { url = cfg.baseURL; playerPassword = cfg.playerPassword }
        }
        .onDisappear { focused = false }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(.subheadline).fontWeight(.medium)
    }

    private func connect() {
        focused = false
        let user: (String, String)? = useUserLogin
            ? (username.trimmingCharacters(in: .whitespaces), userPassword)
            : nil
        var cfg = ServerConfig()
        cfg.baseURL = ServerConfig.normalize(url)
        cfg.playerPassword = playerPassword
        Task {
            await session.configure(cfg, playerPassword: playerPassword, user: user)
        }
    }
}

struct InputField: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
