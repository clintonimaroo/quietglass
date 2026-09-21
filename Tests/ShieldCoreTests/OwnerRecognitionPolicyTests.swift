import XCTest
@testable import ShieldCore

final class OwnerRecognitionPolicyTests: XCTestCase {
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
        for pose in [center, turn, center, closed, center] {
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

    func testOneClosedEyeCannotSatisfyBothEyesPrompt() {
        var challenge = OwnerChallenge(turnPositive: true)
        var time = 1.0
        for pose in [center, turn, center] {
            for _ in 0..<5 { _ = challenge.observe(pose, openEyes: 0.3, at: time); time += 0.1 }
        }
        XCTAssertEqual(challenge.stage, .closeEyes)
        for _ in 0..<6 {
            _ = challenge.observe(OwnerPose(yaw: 0, eyes: 0.05, widestEye: 0.3), openEyes: 0.3, at: time)
            time += 0.1
        }
        XCTAssertEqual(challenge.stage, .closeEyes)
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
        for pose in [center, turn, center, closed, center] {
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
}
