import XCTest
@testable import ShieldCore

final class OwnerRecognitionPolicyTests: XCTestCase {
    private func verifiedPresence() -> (OwnerPresence, Double) {
        var presence = OwnerPresence(turnPositive: true), time = 1.0
        for pose in [center, turn, center] {
            for _ in 0..<5 { presence.observe(matches: true, pose: pose, openEyes: 0.3, at: time); time += 0.1 }
        }
        XCTAssertFalse(presence.covered)
        return (presence, time)
    }

    func testContinuousLandmarkLossCoversThenRecoversWithoutAnotherTurn() {
        var (presence, time) = verifiedPresence()
        for _ in 0..<5 {
            presence.observe(matches: false, pose: nil, openEyes: 0.3, at: time, continuousFaceWithMissingLandmarks: true)
            time += 0.1
        }
        XCTAssertTrue(presence.covered); XCTAssertTrue(presence.recoveringLandmarks)
        for _ in 0..<4 { presence.observe(matches: true, pose: center, openEyes: 0.3, at: time); time += 0.1 }
        XCTAssertTrue(presence.covered, "A single recovered frame must not clear protection")
        for _ in 0..<3 { presence.observe(matches: true, pose: center, openEyes: 0.3, at: time); time += 0.1 }
        XCTAssertFalse(presence.covered)
    }

    func testMismatchMissingFaceAndExpiredRecoveryRequireFullChallenge() {
        for kind in 0..<3 {
            var (presence, time) = verifiedPresence()
            for _ in 0..<5 { presence.observe(matches: false, pose: nil, openEyes: 0.3, at: time, continuousFaceWithMissingLandmarks: true); time += 0.1 }
            if kind < 2 { presence.observe(matches: false, pose: kind == 0 ? center : nil, openEyes: 0.3, at: time); time += 0.1 }
            else { time += 2 }
            for _ in 0..<8 { presence.observe(matches: true, pose: center, openEyes: 0.3, at: time); time += 0.1 }
            XCTAssertTrue(presence.covered, "Recovery must not survive a replacement, missing face, or stale gap")
        }
    }

    func testNewFaceCannotBorrowLandmarkContinuity() {
        XCTAssertTrue(OwnerPresence.isContinuousFace(CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.4), CGRect(x: 0.31, y: 0.31, width: 0.3, height: 0.4)))
        XCTAssertFalse(OwnerPresence.isContinuousFace(CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.4), CGRect(x: 0.7, y: 0.3, width: 0.2, height: 0.3)))
        XCTAssertFalse(OwnerPresence.isContinuousFace(nil, .zero))
    }
    private let center = OwnerPose(yaw: 0, eyes: 0.3)
    private let turn = OwnerPose(yaw: 0.3, eyes: 0.3)
    private let closed = OwnerPose(yaw: 0, eyes: 0.07)
    private var vector: [Float] { [1] + Array(repeating: 0, count: 127) }

    func testTemplatesRejectMalformedAndIncompatibleEmbeddings() throws {
        let owner = OwnerTemplate(vectors: Array(repeating: vector, count: 5), openEyes: 0.3)
        XCTAssertTrue(owner.isValid)
        XCTAssertTrue(owner.matches(vector))
        XCTAssertFalse(owner.matches([0, 1] + Array(repeating: 0, count: 126)))
        XCTAssertNil(OwnerTemplate.normalize(Array(repeating: 0, count: 128)))
        XCTAssertNil(OwnerTemplate.normalize([.nan] + Array(repeating: 0, count: 127)))
        XCTAssertFalse(OwnerTemplate(vectors: [vector], openEyes: 0.3).isValid)
        XCTAssertFalse(OwnerTemplate(vectors: Array(repeating: vector, count: 5), openEyes: .infinity).isValid)
        let bad = String(data: try JSONEncoder().encode(owner), encoding: .utf8)!.replacingOccurrences(of: OwnerTemplate.modelID, with: "other-model")
        XCTAssertFalse(try JSONDecoder().decode(OwnerTemplate.self, from: Data(bad.utf8)).isValid)
    }

    func testCompleteFreshMatchingChallengeIsRequiredToClear() {
        var presence = OwnerPresence(turnPositive: true)
        var time = 1.0
        for pose in [center, turn, center] {
            for _ in 0..<4 {
                presence.observe(matches: true, pose: pose, openEyes: 0.3, at: time)
                time += 0.1
            }
        }
        XCTAssertFalse(presence.covered)
        presence.observe(matches: false, pose: center, openEyes: 0.3, at: time)
        XCTAssertFalse(presence.covered)
        presence.observe(matches: false, pose: center, openEyes: 0.3, at: time + 0.4)
        XCTAssertTrue(presence.covered)
        for i in 0..<30 { presence.observe(matches: false, pose: center, openEyes: 0.3, at: time + 0.5 + Double(i)*0.1) }
        XCTAssertTrue(presence.covered, "A replacement face must never clear protection")
    }

    func testStillPhotoAndWrongOrderCannotCompleteChallenge() {
        var presence = OwnerPresence(turnPositive: true)
        for i in 0..<100 { presence.observe(matches: true, pose: center, openEyes: 0.3, at: 1 + Double(i)*0.1) }
        XCTAssertTrue(presence.covered)
        var challenge = OwnerChallenge(turnPositive: true)
        var time = 1.0
        for pose in [closed, center, OwnerPose(yaw: -0.3, eyes: 0.3), closed, center] {
            for _ in 0..<5 { _ = challenge.observe(pose, openEyes: 0.3, at: time); time += 0.1 }
        }
        XCTAssertNotEqual(challenge.stage, .complete)
    }

    func testNaturalBlinkPausesReturnWithoutRestartingVerification() {
        var challenge = OwnerChallenge(turnPositive: true)
        var time = 1.0
        for pose in [center, turn] {
            for _ in 0..<5 { _ = challenge.observe(pose, openEyes: 0.3, at: time); time += 0.1 }
        }
        XCTAssertEqual(challenge.stage, .returnToCenter)
        _ = challenge.observe(center, openEyes: 0.3, at: time)
        _ = challenge.observe(closed, openEyes: 0.3, at: time + 0.1)
        XCTAssertEqual(challenge.stage, .returnToCenter, "A natural blink should not restart the head-turn sequence")
        XCTAssertFalse(challenge.observe(center, openEyes: 0.3, at: time + 0.2))
        XCTAssertTrue(challenge.observe(center, openEyes: 0.3, at: time + 0.5))
        XCTAssertEqual(challenge.stage, .complete, "Looking back completes verification without a deliberate eye-close step")
    }

    func testStaleDuplicateMissingAndInvalidSamplesCannotUnlock() {
        var presence = OwnerPresence(turnPositive: true)
        presence.observe(matches: true, pose: center, openEyes: 0.3, at: 1)
        presence.observe(matches: true, pose: center, openEyes: 0.3, at: 1.3)
        XCTAssertEqual(presence.challenge.stage, .turn)
        presence.observe(matches: true, pose: turn, openEyes: 0.3, at: 1.3)
        presence.observe(matches: true, pose: turn, openEyes: 0.3, at: 1)
        presence.observe(matches: true, pose: turn, openEyes: 0.3, at: .nan)
        XCTAssertEqual(presence.challenge.stage, .turn)
        presence.observe(matches: true, pose: turn, openEyes: 0.3, at: 3)
        XCTAssertEqual(presence.challenge.stage, .center)
        presence.observe(matches: true, pose: OwnerPose(yaw: .nan, eyes: 0.3), openEyes: 0.3, at: 3.1)
        presence.observe(matches: false, pose: nil, openEyes: 0.3, at: 3.5)
        XCTAssertTrue(presence.covered)
        presence.interrupt(turnPositive: false)
        XCTAssertTrue(presence.covered)
        XCTAssertEqual(presence.challenge.stage, .center)
    }

    func testEnrollmentRequiresSameFaceMultipleSamplesAndChallenge() {
        var enrollment = OwnerEnrollment(turnPositive: true)
        for i in 0..<5 { enrollment.observe(vector: vector, pose: center, faceCount: 1, at: 1 + Double(i)*0.3) }
        XCTAssertEqual(enrollment.vectors.count, 5)
        XCTAssertNil(enrollment.template)
        var time = 2.3
        for pose in [center, turn, center] {
            for _ in 0..<5 { enrollment.observe(vector: vector, pose: pose, faceCount: 1, at: time); time += 0.1 }
        }
        XCTAssertTrue(enrollment.template?.isValid == true)
        enrollment.observe(vector: vector, pose: center, faceCount: 2, at: time)
        XCTAssertNil(enrollment.template)
        XCTAssertTrue(enrollment.vectors.isEmpty)
        enrollment.observe(vector: vector, pose: center, faceCount: 1, at: time + 0.1)
        enrollment.observe(vector: [0, 1] + Array(repeating: 0, count: 126), pose: center, faceCount: 1, at: time + 0.4)
        XCTAssertTrue(enrollment.vectors.isEmpty)
    }

    func testMeasuredLeftAndRightTurnsDoNotEraseEnrollment() {
        // The previous landmark-only camera path reported +/- pi/4 for a
        // turn. These real detector values must not invalidate the whole face.
        for positive in [true, false] {
            var enrollment = OwnerEnrollment(turnPositive: positive)
            var time = 1.0
            for _ in 0..<5 {
                enrollment.observe(vector: vector, pose: center, faceCount: 1, at: time)
                time += 0.3
            }
            for _ in 0..<4 {
                enrollment.observe(vector: vector, pose: center, faceCount: 1, at: time)
                time += 0.1
            }
            XCTAssertEqual(enrollment.challenge.stage, .turn)
            let measuredTurn = OwnerPose(yaw: positive ? .pi / 4 : -.pi / 4, eyes: 0.3)
            for _ in 0..<4 {
                enrollment.observe(vector: vector, pose: measuredTurn, faceCount: 1, at: time)
                time += 0.1
            }
            XCTAssertEqual(enrollment.vectors.count, 5)
            XCTAssertEqual(enrollment.challenge.stage, .returnToCenter)
            XCTAssertNil(enrollment.template, "Turning alone must not complete setup")
        }
    }

    func testOvershootingAndWrongDirectionCannotCompleteTurn() {
        var challenge = OwnerChallenge(turnPositive: false)
        var time = 1.0
        for _ in 0..<4 { _ = challenge.observe(center, openEyes: 0.3, at: time); time += 0.1 }
        XCTAssertEqual(challenge.stage, .turn)
        for yaw in [0.8, -1.3] {
            for _ in 0..<5 {
                _ = challenge.observe(OwnerPose(yaw: yaw, eyes: 0.3), openEyes: 0.3, at: time)
                time += 0.1
            }
            XCTAssertEqual(challenge.stage, .turn)
        }
        for _ in 0..<4 {
            _ = challenge.observe(OwnerPose(yaw: -0.3, eyes: 0.3), openEyes: 0.3, at: time)
            time += 0.1
        }
        XCTAssertEqual(challenge.stage, .returnToCenter)
        XCTAssertFalse(OwnerPose(yaw: 2, eyes: 0.3).isValid)
    }

    func testTurnUsesHeadMotionWithoutRequiringFrontalEyeShape() {
        for positive in [true, false] {
            var presence = OwnerPresence(turnPositive: positive)
            var time = 1.0
            for _ in 0..<4 {
                presence.observe(matches: true, pose: center, openEyes: 0.3, at: time)
                time += 0.1
            }
            XCTAssertEqual(presence.challenge.stage, .turn)
            // Blinking/foreshortening while turning must not block head motion.
            let turning = OwnerPose(yaw: positive ? 0.4 : -0.4, eyes: 0.15)
            for _ in 0..<4 {
                presence.observe(matches: true, pose: turning, openEyes: 0.3, at: time)
                time += 0.1
            }
            XCTAssertEqual(presence.challenge.stage, .returnToCenter)
            XCTAssertTrue(presence.covered, "Passing the turn alone must never clear protection")
            for _ in 0..<6 {
                presence.observe(matches: true, pose: closed, openEyes: 0.3, at: time)
                time += 0.1
            }
            XCTAssertEqual(presence.challenge.stage, .returnToCenter, "A blink must not count as looking back at the camera")
            for _ in 0..<4 {
                presence.observe(matches: true, pose: center, openEyes: 0.3, at: time)
                time += 0.1
            }
            XCTAssertFalse(presence.covered, "Looking back should finish the check in either turn direction")
        }
    }

    func testBriefUnreadableFramePausesTurnWithoutErasingItsStage() {
        var presence = OwnerPresence(turnPositive: true)
        for time in [1.0, 1.1, 1.2, 1.3] { presence.observe(matches: true, pose: center, openEyes: 0.3, at: time) }
        XCTAssertEqual(presence.challenge.stage, .turn)
        presence.observe(matches: true, pose: turn, openEyes: 0.3, at: 1.4)
        presence.observe(matches: false, pose: nil, openEyes: 0.3, at: 1.5)
        XCTAssertTrue(presence.covered)
        XCTAssertEqual(presence.challenge.stage, .turn)
        presence.observe(matches: true, pose: turn, openEyes: 0.3, at: 1.6)
        presence.observe(matches: true, pose: turn, openEyes: 0.3, at: 1.7)
        XCTAssertEqual(presence.challenge.stage, .turn, "Missing frames cannot count toward the hold")
        presence.observe(matches: true, pose: turn, openEyes: 0.3, at: 1.9)
        XCTAssertEqual(presence.challenge.stage, .returnToCenter)
        presence.observe(matches: false, pose: center, openEyes: 0.3, at: 2.0)
        presence.observe(matches: false, pose: center, openEyes: 0.3, at: 2.4)
        XCTAssertEqual(presence.challenge.stage, .center, "Sustained identity loss must restart verification")
        XCTAssertTrue(presence.covered)
    }
}
