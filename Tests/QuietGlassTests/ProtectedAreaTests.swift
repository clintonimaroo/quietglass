import AppKit
import XCTest
@testable import QuietGlass

@MainActor
final class ProtectedAreaTests: XCTestCase {
    func testClearScreenDiscardsAreasInsteadOfOnlyPausingThem() {
        let controller = PrivacyController()
        defer { controller.shutdown() }
        controller.requestEscape = { false }
        let window = ProtectedWindow(id: 99, owner: -1, name: "Sample")
        controller.protectArea(CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), in: window)
        XCTAssertEqual(controller.protectedAreas.count, 1)
        controller.pauseProtection()
        XCTAssertEqual(controller.protectedAreas.count, 1)
        XCTAssertTrue(controller.paused)
        controller.dismissAll()
        XCTAssertTrue(controller.protectedAreas.isEmpty)
        XCTAssertTrue(controller.paused)
        controller.resume()
        XCTAssertTrue(controller.protectedAreas.isEmpty)
    }

    func testRemoveOneAreaPreservesTheOtherUntilRemoveAll() {
        let controller = PrivacyController()
        defer { controller.shutdown() }
        controller.requestEscape = { false }
        let window = ProtectedWindow(id: 99, owner: -1, name: "Sample")
        controller.protectArea(CGRect(x: 0, y: 0, width: 0.4, height: 0.4), in: window)
        controller.protectArea(CGRect(x: 0.5, y: 0.5, width: 0.4, height: 0.4), in: window)
        let remaining = controller.protectedAreas[1].id
        controller.removeArea(controller.protectedAreas[0].id)
        XCTAssertEqual(controller.protectedAreas.map(\.id), [remaining])
        controller.removeAllAreas()
        XCTAssertTrue(controller.protectedAreas.isEmpty)
    }
}
