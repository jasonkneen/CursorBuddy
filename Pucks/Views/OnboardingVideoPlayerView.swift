import SwiftUI
import AVFoundation
import AVKit

// MARK: - OnboardingVideoPlayerView

struct OnboardingVideoPlayerView: NSViewRepresentable {

    let hlsURL: String
    var onVideoEnded: (() -> Void)?

    func makeNSView(context: Context) -> AVPlayerNSView {
        let view = AVPlayerNSView()
        view.configure(hlsURLString: hlsURL)

        // Observe video end
        context.coordinator.setupEndObserver(for: view.player, onEnded: onVideoEnded)

        // Start background music
        context.coordinator.startBackgroundMusic()

        return view
    }

    func updateNSView(_ nsView: AVPlayerNSView, context: Context) {
        // No dynamic updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        var onboardingVideoEndObserver: NSObjectProtocol?
        var onboardingMusicPlayer: AVAudioPlayer?

        func setupEndObserver(for player: AVPlayer?, onEnded: (() -> Void)?) {
            guard let player = player else { return }

            onboardingVideoEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.stopBackgroundMusic()
                onEnded?()
            }
        }

        func startBackgroundMusic() {
            guard let musicURL = Bundle.main.url(forResource: "ff", withExtension: "mp3") else {
                print("[OnboardingVideoPlayer] Background music file 'ff.mp3' not found in bundle.")
                return
            }

            do {
                onboardingMusicPlayer = try AVAudioPlayer(contentsOf: musicURL)
                onboardingMusicPlayer?.numberOfLoops = -1 // Loop indefinitely
                onboardingMusicPlayer?.volume = 0.3
                onboardingMusicPlayer?.play()
                print("[OnboardingVideoPlayer] Background music started.")
            } catch {
                print("[OnboardingVideoPlayer] Failed to play background music: \(error)")
            }
        }

        func stopBackgroundMusic() {
            onboardingMusicPlayer?.stop()
            onboardingMusicPlayer = nil
            print("[OnboardingVideoPlayer] Background music stopped.")
        }

        deinit {
            if let observer = onboardingVideoEndObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            stopBackgroundMusic()
        }
    }
}

// MARK: - AVPlayerNSView

class AVPlayerNSView: NSView {

    private(set) var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    func configure(hlsURLString: String) {
        guard let url = URL(string: hlsURLString) else {
            print("[AVPlayerNSView] Invalid HLS URL: \(hlsURLString)")
            return
        }

        let playerItem = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: playerItem)
        self.player = player

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.cornerRadius = 12
        playerLayer.masksToBounds = true

        self.layer?.addSublayer(playerLayer)
        self.playerLayer = playerLayer

        player.play()
        print("[AVPlayerNSView] HLS playback started: \(hlsURLString)")
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }
}
