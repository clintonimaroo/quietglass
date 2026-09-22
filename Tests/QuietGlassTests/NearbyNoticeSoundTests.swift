import AppKit
import XCTest
@testable import QuietGlass

final class NearbyNoticeSoundTests: XCTestCase {
    @MainActor func testCameraUpdatesAndHoverDoNotRepeatAnActiveWarning() {
        var plays = 0
        let sound = NearbyNoticeSound { plays += 1 }
        sound.update(needsAttention: true, visible: true, enabled: true)
        for _ in 0..<100 {
            sound.update(needsAttention: true, visible: true, enabled: true)
        }
        // Opening controls hides the notice, but does not end the warning.
        sound.update(needsAttention: true, visible: false, enabled: true)
        sound.update(needsAttention: true, visible: true, enabled: true)
        XCTAssertEqual(plays, 1)

        sound.update(needsAttention: false, visible: false, enabled: true)
        sound.update(needsAttention: true, visible: true, enabled: true)
        XCTAssertEqual(plays, 2, "A new warning must have its own sound")
    }

    @MainActor func testWarningsWaitUntilVisibleAndResolvedHiddenWarningsStaySilent() {
        var plays = 0
        let sound = NearbyNoticeSound { plays += 1 }
        sound.update(needsAttention: true, visible: false, enabled: true)
        XCTAssertEqual(plays, 0)
        sound.update(needsAttention: false, visible: false, enabled: true)
        sound.update(needsAttention: false, visible: true, enabled: true)
        XCTAssertEqual(plays, 0, "Do not announce a warning that cleared while controls were open")

        sound.update(needsAttention: true, visible: false, enabled: true)
        sound.update(needsAttention: true, visible: true, enabled: true)
        XCTAssertEqual(plays, 1)
    }

    @MainActor func testUnmutingDoesNotReplayAnAlreadyVisibleWarning() {
        var plays = 0
        let sound = NearbyNoticeSound { plays += 1 }
        sound.update(needsAttention: true, visible: true, enabled: false)
        sound.update(needsAttention: true, visible: true, enabled: true)
        XCTAssertEqual(plays, 0)
        sound.update(needsAttention: false, visible: false, enabled: true)
        sound.update(needsAttention: true, visible: true, enabled: true)
        XCTAssertEqual(plays, 1)
    }

    @MainActor func testBundledSoundCanBeDecodedWithoutPlayingIt() throws {
        let url = try XCTUnwrap(NearbyNoticeSound.resourceURL)
        let sound = try XCTUnwrap(NSSound(contentsOf: url, byReference: true))
        XCTAssertGreaterThan(sound.duration, 0.5)
        XCTAssertLessThan(sound.duration, 0.7)
    }
}
