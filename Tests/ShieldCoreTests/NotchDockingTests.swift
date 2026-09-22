//  Created by Clinton Imaro on 20/09/2026.

import XCTest
import CoreGraphics
@testable import ShieldCore

final class NotchDockingTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testSideDockingAndReturningToBottom() {
        XCTAssertEqual(NotchDocking.edge(near: CGPoint(x: 30, y: 500), in: screen, bottom: 96), .left)
        XCTAssertEqual(NotchDocking.edge(near: CGPoint(x: 1490, y: 500), in: screen, bottom: 96), .right)
        XCTAssertEqual(NotchDocking.edge(near: CGPoint(x: 760, y: 115), in: screen, bottom: 96, retaining: .right), .bottom)
        XCTAssertEqual(NotchDocking.edge(near: CGPoint(x: 600, y: 400), in: screen, bottom: 96, retaining: .left), .floating)
    }

    func testEdgeHysteresisAvoidsRotationChatter() {
        XCTAssertEqual(NotchDocking.edge(near: CGPoint(x: 80, y: 500), in: screen, bottom: 0), .floating)
        XCTAssertEqual(NotchDocking.edge(near: CGPoint(x: 80, y: 500), in: screen, bottom: 0, retaining: .left), .left)
        XCTAssertEqual(NotchDocking.edge(near: CGPoint(x: 110, y: 500), in: screen, bottom: 0, retaining: .left), .floating)
        XCTAssertEqual(NotchDocking.edge(near: CGPoint(x: 20, y: 50), in: screen, bottom: 0), .floating)
    }

    func testBothOrientationsKeepControlsInsideOffsetDisplays() {
        let external = CGRect(x: -1920, y: 130, width: 1920, height: 1080)
        for edge in [NotchEdge.left, .right, .bottom] {
            let point = NotchDocking.anchor(for: edge, in: external, bottom: external.minY)
            for expanded in [true, false] {
                XCTAssertTrue(external.contains(NotchDocking.frame(anchor: point, vertical: edge.isVertical, expanded: expanded)))
            }
            XCTAssertEqual(NotchDocking.edge(near: point, in: external, bottom: external.minY), edge)
        }
    }

    func testDockHiddenChangesOnlyBottomPosition() {
        let visible = NotchDocking.anchor(for: .bottom, in: screen, bottom: 100)
        let hidden = NotchDocking.anchor(for: .bottom, in: screen, bottom: 0)
        XCTAssertEqual(visible.x, hidden.x)
        XCTAssertEqual(visible.y - hidden.y, 100)
        XCTAssertEqual(NotchDocking.anchor(for: .right, in: screen, bottom: 100),
                       NotchDocking.anchor(for: .right, in: screen, bottom: 0))
    }

    func testTopPlacementIsRejectedAcrossDisplays() {
        let displays = [screen, CGRect(x: -1920, y: 130, width: 1920, height: 1080),
                        CGRect(x: 1512, y: -600, width: 1024, height: 768)]
        for display in displays {
            for x in [display.minX + 22, display.midX, display.maxX - 22] {
                XCTAssertFalse(NotchDocking.allowsPlacement(at: CGPoint(x: x, y: display.maxY - 20), in: display))
                XCTAssertFalse(NotchDocking.allowsPlacement(at: CGPoint(x: x, y: display.maxY - 119), in: display))
                XCTAssertTrue(NotchDocking.allowsPlacement(at: CGPoint(x: x, y: display.maxY - 120), in: display))
            }
            for edge in [NotchEdge.left, .right, .bottom] {
                let anchor = NotchDocking.anchor(for: edge, in: display, bottom: display.minY + 96)
                XCTAssertTrue(NotchDocking.allowsPlacement(at: anchor, in: display))
            }
        }
    }

    func testConstrainedPositionsCannotEnterTopArea() {
        for display in [screen, CGRect(x: -800, y: -400, width: 800, height: 360)] {
            for vertical in [true, false] {
                let anchor = NotchDocking.constrain(CGPoint(x: display.midX, y: display.maxY + 200),
                                                   in: display, vertical: vertical)
                XCTAssertTrue(NotchDocking.allowsPlacement(at: anchor, in: display))
                XCTAssertTrue(display.contains(NotchDocking.frame(anchor: anchor, vertical: vertical, expanded: true)))
            }
        }
    }

    func testPopupBoundsDiscardHiddenDockInset() {
        for display in [screen, CGRect(x: -1920, y: 130, width: 1920, height: 1080)] {
            let desktop = CGRect(x: display.minX, y: display.minY + 96,
                                 width: display.width, height: display.height - 120)
            XCTAssertEqual(NotchDocking.popupBounds(in: desktop, bottom: desktop.minY), desktop)
            let fullScreen = NotchDocking.popupBounds(in: desktop, bottom: display.minY)
            let anchor = NotchDocking.anchor(for: .bottom, in: display, bottom: display.minY)
            let controls = NotchDocking.frame(anchor: anchor, vertical: false, expanded: true)
            let popupY = max(fullScreen.minY + 8, controls.maxY + 8)
            XCTAssertEqual(popupY - controls.maxY, 8)
            XCTAssertEqual(fullScreen.maxY, desktop.maxY)
            XCTAssertEqual(fullScreen.minX, desktop.minX)
            XCTAssertEqual(fullScreen.width, desktop.width)
        }
    }

    func testProfilePopupStaysBesideTheVisibleControlsAcrossDockEdges() {
        for display in [screen, CGRect(x: -1920, y: 130, width: 1920, height: 1080)] {
            for edge in [NotchEdge.left, .right, .bottom] {
                let anchor = NotchDocking.anchor(for: edge, in: display, bottom: display.minY)
                let controls = NotchDocking.frame(anchor: anchor, vertical: edge.isVertical, expanded: true)
                let popup = NotchDocking.popupFrame(size: CGSize(width: 220, height: 240), controls: controls, edge: edge, in: display)
                XCTAssertTrue(display.contains(popup))
                switch edge {
                case .left: XCTAssertEqual(popup.minX - controls.maxX, 8)
                case .right: XCTAssertEqual(controls.minX - popup.maxX, 8)
                default: XCTAssertEqual(popup.minY - controls.maxY, 8)
                }
            }
        }
    }

    func testFloatingProfilePopupFlipsBelowWhenThereIsNoRoomAbove() {
        let controls = NotchDocking.frame(anchor: CGPoint(x: 700, y: 850), vertical: false, expanded: true)
        let popup = NotchDocking.popupFrame(size: CGSize(width: 220, height: 240), controls: controls, edge: .floating, in: screen)
        XCTAssertTrue(screen.contains(popup))
        XCTAssertEqual(controls.minY - popup.maxY, 8)
    }

    func testWarningStaysCenteredOnHandleRatherThanExpandedControls() {
        let size = CGSize(width: 312, height: 56)
        for display in [screen, CGRect(x: -1920, y: 130, width: 1920, height: 1080)] {
            for edge in [NotchEdge.left, .right, .bottom, .floating] {
                let anchor = NotchDocking.anchor(for: edge, in: display, bottom: display.minY + 96)
                let notice = NotchDocking.noticeFrame(size: size, anchor: anchor, edge: edge, in: display)
                XCTAssertTrue(display.contains(notice))
                if edge.isVertical {
                    XCTAssertEqual(notice.midY, anchor.y)
                    if edge == .left { XCTAssertEqual(notice.minX - anchor.x, 23) }
                    else { XCTAssertEqual(anchor.x - notice.maxX, 23) }
                } else {
                    XCTAssertEqual(notice.midX, anchor.x)
                    XCTAssertEqual(notice.minY - anchor.y, 23)
                }
            }
        }
    }
}
