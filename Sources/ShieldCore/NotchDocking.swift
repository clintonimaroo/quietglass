//  Created by Clinton Imaro on 20/09/2026.

import Foundation
import CoreGraphics

public enum NotchEdge: String, CaseIterable {
    case floating, bottom, left, right
    public var isVertical: Bool { self == .left || self == .right }
}

public enum NotchDocking {
    private static func highestAnchor(in screen: CGRect) -> CGFloat {
        screen.maxY - min(120, screen.height * 0.25)
    }

    public static func allowsPlacement(at point: CGPoint, in screen: CGRect) -> Bool {
        point.y <= highestAnchor(in: screen)
    }

    public static func popupBounds(in visibleFrame: CGRect, bottom: CGFloat) -> CGRect {
        CGRect(x: visibleFrame.minX, y: bottom, width: visibleFrame.width,
               height: max(0, visibleFrame.maxY - bottom))
    }

    public static func edge(near point: CGPoint, in screen: CGRect, bottom: CGFloat,
                            retaining current: NotchEdge = .floating) -> NotchEdge {
        let sideReach: CGFloat = current.isVertical ? 100 : 64
        let middleReach = max(100, screen.height * 0.22)
        if abs(point.y - screen.midY) <= middleReach {
            if point.x <= screen.minX + sideReach { return .left }
            if point.x >= screen.maxX - sideReach { return .right }
        }
        if abs(point.x - screen.midX) <= 110, point.y <= bottom + 84 { return .bottom }
        return .floating
    }

    public static func anchor(for edge: NotchEdge, in screen: CGRect, bottom: CGFloat) -> CGPoint {
        switch edge {
        case .left: return CGPoint(x: screen.minX + 22, y: screen.midY + 34)
        case .right: return CGPoint(x: screen.maxX - 22, y: screen.midY + 34)
        case .bottom, .floating: return CGPoint(x: screen.midX, y: bottom + 20)
        }
    }

    public static func frame(anchor: CGPoint, vertical: Bool, expanded: Bool) -> CGRect {
        if !expanded {
            return CGRect(x: anchor.x - (vertical ? 15 : 26), y: anchor.y - (vertical ? 26 : 15),
                          width: vertical ? 30 : 52, height: vertical ? 52 : 30)
        }
        return vertical
            ? CGRect(x: anchor.x - 15, y: anchor.y - 92, width: 30, height: 116)
            : CGRect(x: anchor.x - 24, y: anchor.y - 15, width: 116, height: 30)
    }

    public static func constrain(_ anchor: CGPoint, in screen: CGRect, vertical: Bool) -> CGPoint {
        CGPoint(x: min(max(anchor.x, screen.minX + (vertical ? 22 : 32)), screen.maxX - (vertical ? 22 : 100)),
                y: min(max(anchor.y, screen.minY + (vertical ? 100 : 23)), highestAnchor(in: screen)))
    }
}
