import AppKit

/// Announce each warning once, when it first becomes visible beside the notch.
@MainActor
final class NearbyNoticeSound {
    private let play: () -> Void
    private var announced = false

    static var resourceURL: URL? {
        Bundle.main.url(forResource: "NearbyAlert", withExtension: "mp3")
            ?? Bundle.module.url(forResource: "NearbyAlert", withExtension: "mp3")
    }

    convenience init() {
        let sound = Self.resourceURL.flatMap { NSSound(contentsOf: $0, byReference: true) }
        sound?.volume = 0.5
        sound?.loops = false
        self.init {
            sound?.stop()
            sound?.play()
        }
    }

    init(play: @escaping () -> Void) { self.play = play }

    func update(needsAttention: Bool, visible: Bool, enabled: Bool) {
        guard needsAttention else { announced = false; return }
        guard visible, !announced else { return }
        // Hover, layout updates, and changing the sound setting must not replay
        // a warning that has already appeared, including one shown while muted.
        announced = true
        if enabled { play() }
    }
}
