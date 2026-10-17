import Foundation
import AVFoundation
import Combine
import MediaPlayer

/// 全局播放状态（队列、当前歌曲、进度、歌词）
@MainActor
final class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    @Published var queue: [Song] = []
    @Published var currentIndex: Int = -1
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var lyrics: [LyricLine] = []
    @Published var activeLyricIndex: Int = -1
    @Published var rate: Float = 1.0
    @Published var volume: Float = 1.0
    @Published var showingMiniError = false
    @Published var playError: String?
    @Published var sleepRemaining: TimeInterval?   // 播放自动停止倒计时（nil = 关闭）
    @Published var currentLyricOffset: Double = 0   // 当前歌曲歌词偏移（秒）

    var currentSong: Song? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    private var sleepTask: Task<Void, Never>?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endTimeObserver: NSObjectProtocol?
    private var pendingSeek: Double?
    private var lastPersist: Double = 0
    private var lyricTask: Task<Void, Never>?
    private var api: LXAPIClient?
    private var username: String?  // 用于自定义目录流媒体 URL 的 user 参数
    private var quality: String = "128k"

    private init() {
        likedIds = Set(UserDefaults.standard.stringArray(forKey: Self.likedKey) ?? [])
        configureAudioSession()
        configureRemoteCommands()
    }

    /// 激活后台播放音频会话
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    func configure(api: LXAPIClient?, username: String? = nil) {
        self.api = api
        self.username = username
    }

    // MARK: - 队列控制

    /// 用一组歌曲开播
    func play(songs: [Song], startIndex: Int = 0) {
        guard !songs.isEmpty else { return }
        queue = songs
        currentIndex = min(max(startIndex, 0), songs.count - 1)
        loadCurrent()
        persistState()
    }

    func playSong(_ song: Song, in list: [Song]? = nil) {
        if let list {
            play(songs: list, startIndex: max(0, list.firstIndex(of: song) ?? 0))
        } else {
            play(songs: [song])
        }
    }

    func addToQueue(_ song: Song) {
        if queue.isEmpty {
            play(songs: [song])
        } else {
            queue.append(song)
        }
    }

    func next() {
        guard queue.count > 0 else { return }
        currentIndex = (currentIndex + 1) % queue.count
        loadCurrent()
        persistState()
    }

    func previous() {
        guard queue.count > 0 else { return }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        loadCurrent()
        persistState()
    }

    /// 取队列中任意下标对应的歌（越界自动回绕；空队列返回 nil）
    func songAt(_ index: Int) -> Song? {
        guard !queue.isEmpty else { return nil }
        let n = queue.count
        return queue[((index % n) + n) % n]
    }

    func togglePlayPause() {
        guard player != nil else { return }
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true
        }
    }

    // MARK: - 删除当前歌曲（从队列移除，非破坏性）

    func removeCurrentFromQueue() {
        guard queue.indices.contains(currentIndex) else { return }
        queue.remove(at: currentIndex)
        if queue.isEmpty {
            currentIndex = -1
            player?.pause()
            isPlaying = false
            sleepTask?.cancel()
            sleepRemaining = nil
            persistState()
            return
        }
        currentIndex = min(currentIndex, queue.count - 1)
        loadCurrent()
        persistState()
    }

    // MARK: - 播放自动停止（睡眠定时器，本地）

    func startSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        guard minutes > 0 else { sleepRemaining = nil; return }
        sleepRemaining = TimeInterval(minutes * 60)
        let target = Date().addingTimeInterval(sleepRemaining!)
        sleepTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                let left = target.timeIntervalSinceNow
                if left <= 0 {
                    self.sleepTask?.cancel()
                    self.sleepTask = nil
                    self.player?.pause()
                    self.isPlaying = false
                    self.sleepRemaining = nil
                    return
                }
                self.sleepRemaining = left
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        sleepRemaining = nil
    }

    // MARK: - 喜欢（本地收藏，按歌曲 id 记忆）

    private static let likedKey = "lx.likedSongs"
    private var likedIds: Set<String> = []

    func isLiked(_ song: Song) -> Bool {
        likedIds.contains(song.id)
    }

    /// 切换喜欢状态，返回新的喜欢状态
    @discardableResult
    func toggleLike(_ song: Song) -> Bool {
        if likedIds.contains(song.id) {
            likedIds.remove(song.id)
        } else {
            likedIds.insert(song.id)
        }
        UserDefaults.standard.set(Array(likedIds), forKey: Self.likedKey)
        return likedIds.contains(song.id)
    }

    func seek(to time: Double) {
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func setRate(_ r: Float) {
        rate = r
        player?.defaultRate = r
        player?.rate = isPlaying ? r : 0
    }

    func setVolume(_ v: Float) {
        volume = v
        player?.volume = v
    }

    func setQuality(_ q: String) {
        quality = q
        loadCurrent()
    }

    // MARK: - 加载播放

    func loadCurrent() {
        guard let song = currentSong else { return }
        playError = nil
        // 清歌词
        lyrics = []
        activeLyricIndex = -1
        currentLyricOffset = lyricOffset(for: song)
        lyricTask?.cancel()

        let api = self.api
        let quality = self.quality
        let username = self.username
        let isCustom = song.isCustom
        let customFilename = song.customFilename

        Task {
            do {
                guard let api else { throw LXError.noData }
                // 1. 解析播放直链（自定义目录歌曲直接走服务器本地文件流，支持 Range）
                let urlStr: String
                if isCustom, let fn = customFilename, let user = username {
                    urlStr = try api.customFileURL(filename: fn, user: user).absoluteString
                } else {
                    urlStr = try await api.musicURL(song: song, quality: quality)
                }
                // 歌曲缓存：开缓存时若本地已有该歌副本 → 直接播本地文件
                let playURL: URL
                if let cached = LocalCache.shared.cachedSongURL(for: song) {
                    playURL = cached
                } else {
                    guard let remote = URL(string: urlStr) else { throw LXError.invalidURL }
                    playURL = remote
                    if LocalCache.enableSongCache {
                        // 后台缓存当前播放流，下次播放同一首直接本地读
                        LocalCache.shared.cacheAudio(from: remote, for: song)
                    }
                }
                self.preparePlayer(url: playURL)

                // 2. 拉歌词（在线歌传完整 songInfo，自定义歌读内嵌/外部歌词）
                let lrc: String
                if isCustom, let fn = customFilename, let user = username {
                    lrc = (try? await api.customLyric(filename: fn, user: user)) ?? ""
                } else {
                    lrc = try await api.lyric(song: song)
                }
                if lrc.isEmpty { self.lyrics = []; return }
                self.lyrics = LyricLine.parse(lrc: lrc)
            } catch {
                self.playError = error.localizedDescription
                self.showingMiniError = true
            }
        }
    }

    private func preparePlayer(url: URL) {
        // 必须先停掉旧播放器并从【旧播放器】移除其观察者，否则移除错误会闪退
        if let oldPlayer = self.player {
            if let obs = timeObserver { oldPlayer.removeTimeObserver(obs) }
            timeObserver = nil
            oldPlayer.pause()
        }
        if let endObs = endTimeObserver {
            NotificationCenter.default.removeObserver(endObs)
            endTimeObserver = nil
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = volume
        player.defaultRate = rate
        self.player = player
        player.play()
        isPlaying = true

        // 恢复上次播放位置
        if let ps = pendingSeek, ps.isFinite, ps > 0 {
            player.seek(to: CMTime(seconds: ps, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = ps
            pendingSeek = nil
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let s = self
            let t = time.seconds
            Task { @MainActor in
                s.currentTime = t
                if s.duration == 0, let dur = player.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
                    s.duration = dur
                }
                s.updateActiveLyric(at: t)
                if t - s.lastPersist > 5 {
                    s.persistState()
                    s.lastPersist = t
                }
            }
        }

        let endObs = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let s = self
            Task { @MainActor in s.next() }
        }
        endTimeObserver = endObs

        configureRemoteCommands()
        updateNowPlayingInfo()
    }

    private func updateActiveLyric(at time: Double) {
        guard !lyrics.isEmpty else { activeLyricIndex = -1; return }
        // 应用歌词偏移：offset>0 时按“更晚的播放时间”匹配 → 当前句提前高亮（歌词前移）
        let adjusted = time + currentLyricOffset
        var idx = 0
        for (i, line) in lyrics.enumerated() {
            if line.time <= adjusted + 0.3 { idx = i }
        }
        activeLyricIndex = idx
    }

    // MARK: - 歌词偏移（按歌本地记忆，不写回歌词文件）

    private static let lyricOffsetKey = "lx.lyricOffsets"
    private var lyricOffsets: [String: Double] = {
        guard let d = UserDefaults.standard.data(forKey: PlayerManager.lyricOffsetKey),
              let arr = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        var map: [String: Double] = [:]
        for (k, v) in arr {
            if let n = v as? Double { map[k] = n }
            else if let n = v as? Int { map[k] = Double(n) }
        }
        return map
    }()

    func lyricOffset(for song: Song) -> Double {
        lyricOffsets[song.id] ?? 0
    }

    func setLyricOffset(_ offset: Double, for song: Song) {
        lyricOffsets[song.id] = offset
        if let data = try? JSONSerialization.data(withJSONObject: lyricOffsets) {
            UserDefaults.standard.set(data, forKey: PlayerManager.lyricOffsetKey)
        }
        if song.id == currentSong?.id {
            currentLyricOffset = offset
        }
    }

    /// 歌词前移（offset +step 秒）→ 当前句提前高亮
    func shiftLyricForward(step: Double = 0.5) {
        guard let song = currentSong else { return }
        setLyricOffset(min(max(currentLyricOffset + step, -10), 10), for: song)
    }

    /// 歌词后移（offset -step 秒）
    func shiftLyricBackward(step: Double = 0.5) {
        guard let song = currentSong else { return }
        setLyricOffset(min(max(currentLyricOffset - step, -10), 10), for: song)
    }

    // MARK: - 锁屏控制

    private func configureRemoteCommands() {
        let cmd = MPRemoteCommandCenter.shared()
        cmd.playCommand.removeTarget(nil)
        cmd.pauseCommand.removeTarget(nil)
        cmd.nextTrackCommand.removeTarget(nil)
        cmd.previousTrackCommand.removeTarget(nil)
        cmd.playCommand.addTarget { [weak self] _ in self?.player?.play(); return .success }
        cmd.pauseCommand.addTarget { [weak self] _ in self?.player?.pause(); return .success }
        cmd.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        cmd.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
    }

    private func updateNowPlayingInfo() {
        guard let song = currentSong else { return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = song.name
        info[MPMediaItemPropertyArtist] = song.singer
        info[MPMediaItemPropertyAlbumTitle] = song.albumName
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        info[MPMediaItemPropertyPlaybackDuration] = duration
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - 上次播放记忆（启动自动续播）

    private static let lastKey = "lx.lastQueue"

    private func persistState() {
        let arr = queue.compactMap { $0.toJSON() }
        let payload: [String: Any] = ["queue": arr, "index": currentIndex, "time": currentTime]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            UserDefaults.standard.set(data, forKey: Self.lastKey)
        }
    }

    func saveLastTime() {
        persistState()
    }

    /// 是否有可恢复的播放状态
    var hasSavedState: Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.lastKey),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["queue"] as? [Any] else { return false }
        return arr.compactMap { Song(json: $0) }.isEmpty == false
    }

    /// 恢复上次播放并续播
    func restoreAndPlay() {
        guard let data = UserDefaults.standard.data(forKey: Self.lastKey),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["queue"] as? [Any] else { return }
        let songs = arr.compactMap { Song(json: $0) }
        guard !songs.isEmpty else { return }
        let idx = min(max((obj["index"] as? Int) ?? 0, 0), songs.count - 1)
        let t = (obj["time"] as? Double) ?? 0
        queue = songs
        currentIndex = idx
        pendingSeek = t
        loadCurrent()
    }
}
