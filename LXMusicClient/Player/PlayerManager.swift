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

    var currentSong: Song? {
        guard queue.indices.contains(currentIndex) else { return nil }
        return queue[currentIndex]
    }

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var lyricTask: Task<Void, Never>?
    private var api: LXAPIClient?
    private var quality: String = "128k"

    private init() {
        configureAudioSession()
        configureRemoteCommands()
    }

    /// 激活后台播放音频会话
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    func configure(api: LXAPIClient) {
        self.api = api
    }

    // MARK: - 队列控制

    /// 用一组歌曲开播
    func play(songs: [Song], startIndex: Int = 0) {
        guard !songs.isEmpty else { return }
        queue = songs
        currentIndex = min(max(startIndex, 0), songs.count - 1)
        loadCurrent()
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
    }

    func previous() {
        guard queue.count > 0 else { return }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        loadCurrent()
    }

    func togglePlayPause() {
        guard player != nil else { return }
        if isPlaying { player?.pause() } else { player?.play() }
    }

    func seek(to time: Double) {
        let cm = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
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

    private func loadCurrent() {
        guard let song = currentSong else { return }
        playError = nil
        // 清歌词
        lyrics = []
        activeLyricIndex = -1
        lyricTask?.cancel()

        let api = self.api
        let sid = song.id
        let quality = self.quality

        Task {
            do {
                guard let api else { throw LXError.noData }
                // 1. 解析播放直链
                let urlStr = try await api.musicURL(song: song, quality: quality)
                // 歌曲可能因解析变化，用返回 URL
                guard let url = URL(string: urlStr) else { throw LXError.invalidURL }
                self.preparePlayer(url: url)

                // 2. 拉歌词
                let lrc = try await api.lyric(song: Song(
                    id: sid, name: song.name, singer: song.singer, source: song.source,
                    albumPic: song.albumPic))
                if lrc.isEmpty { self.lyrics = []; return }
                self.lyrics = LyricLine.parse(lrc: lrc)
            } catch {
                self.playError = error.localizedDescription
                self.showingMiniError = true
            }
        }
    }

    private func preparePlayer(url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.volume = volume
        player.defaultRate = rate
        self.player = player
        player.play()
        isPlaying = true

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        if let old = timeObserver { player.removeTimeObserver(old) }
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let t = time.seconds
                self.currentTime = t
                if self.duration == 0, let dur = player.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
                    self.duration = dur
                }
                self.updateActiveLyric(at: t)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }

        configureRemoteCommands()
        updateNowPlayingInfo()
    }

    private func updateActiveLyric(at time: Double) {
        guard !lyrics.isEmpty else { activeLyricIndex = -1; return }
        var idx = 0
        for (i, line) in lyrics.enumerated() {
            if line.time <= time + 0.3 { idx = i }
        }
        activeLyricIndex = idx
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
}
