// Geometry from @hugeicons/core-free-icons 4.3.4 (MIT).
// Original SVGs and the required notice are in Resources/Hugeicons.
import AppKit
import SwiftUI

enum HugeIcon: CaseIterable {
    case view, viewOff, play, pause, cancel, airpods, chevronDown, drag

    var path: Path {
        var path = Path()
        switch self {
        case .view:
            path.move(to: CGPoint(x: 21.544, y: 11.045))
            path.addCurve(to: CGPoint(x: 22, y: 12), control1: CGPoint(x: 21.848, y: 11.4713), control2: CGPoint(x: 22, y: 11.6845))
            path.addCurve(to: CGPoint(x: 21.544, y: 12.955), control1: CGPoint(x: 22, y: 12.3155), control2: CGPoint(x: 21.848, y: 12.5287))
            path.addCurve(to: CGPoint(x: 12, y: 19), control1: CGPoint(x: 20.1779, y: 14.8706), control2: CGPoint(x: 16.6892, y: 19))
            path.addCurve(to: CGPoint(x: 2.45604, y: 12.955), control1: CGPoint(x: 7.31078, y: 19), control2: CGPoint(x: 3.8221, y: 14.8706))
            path.addCurve(to: CGPoint(x: 2, y: 12), control1: CGPoint(x: 2.15201, y: 12.5287), control2: CGPoint(x: 2, y: 12.3155))
            path.addCurve(to: CGPoint(x: 2.45604, y: 11.045), control1: CGPoint(x: 2, y: 11.6845), control2: CGPoint(x: 2.15201, y: 11.4713))
            path.addCurve(to: CGPoint(x: 12, y: 5), control1: CGPoint(x: 3.8221, y: 9.12944), control2: CGPoint(x: 7.31078, y: 5))
            path.addCurve(to: CGPoint(x: 21.544, y: 11.045), control1: CGPoint(x: 16.6892, y: 5), control2: CGPoint(x: 20.1779, y: 9.12944))
            path.closeSubpath()
            path.move(to: CGPoint(x: 15, y: 12))
            path.addCurve(to: CGPoint(x: 12, y: 9), control1: CGPoint(x: 15, y: 10.3431), control2: CGPoint(x: 13.6569, y: 9))
            path.addCurve(to: CGPoint(x: 9, y: 12), control1: CGPoint(x: 10.3431, y: 9), control2: CGPoint(x: 9, y: 10.3431))
            path.addCurve(to: CGPoint(x: 12, y: 15), control1: CGPoint(x: 9, y: 13.6569), control2: CGPoint(x: 10.3431, y: 15))
            path.addCurve(to: CGPoint(x: 15, y: 12), control1: CGPoint(x: 13.6569, y: 15), control2: CGPoint(x: 15, y: 13.6569))
            path.closeSubpath()
        case .viewOff:
            path.move(to: CGPoint(x: 22, y: 8))
            path.addCurve(to: CGPoint(x: 12, y: 14), control1: CGPoint(x: 22, y: 8), control2: CGPoint(x: 18, y: 14))
            path.addCurve(to: CGPoint(x: 2, y: 8), control1: CGPoint(x: 6, y: 14), control2: CGPoint(x: 2, y: 8))
            path.move(to: CGPoint(x: 15, y: 13.5))
            path.addLine(to: CGPoint(x: 16.5, y: 16))
            path.move(to: CGPoint(x: 20, y: 11))
            path.addLine(to: CGPoint(x: 22, y: 13))
            path.move(to: CGPoint(x: 2, y: 13))
            path.addLine(to: CGPoint(x: 4, y: 11))
            path.move(to: CGPoint(x: 9, y: 13.5))
            path.addLine(to: CGPoint(x: 7.5, y: 16))
        case .play:
            path.move(to: CGPoint(x: 18.8906, y: 12.846))
            path.addCurve(to: CGPoint(x: 13.5257, y: 17.0361), control1: CGPoint(x: 18.5371, y: 14.189), control2: CGPoint(x: 16.8667, y: 15.138))
            path.addCurve(to: CGPoint(x: 7.37983, y: 19.4196), control1: CGPoint(x: 10.296, y: 18.8709), control2: CGPoint(x: 8.6812, y: 19.7884))
            path.addCurve(to: CGPoint(x: 5.95624, y: 18.5787), control1: CGPoint(x: 6.8418, y: 19.2671), control2: CGPoint(x: 6.35159, y: 18.9776))
            path.addCurve(to: CGPoint(x: 5, y: 12), control1: CGPoint(x: 5, y: 17.6139), control2: CGPoint(x: 5, y: 15.7426))
            path.addCurve(to: CGPoint(x: 5.95624, y: 5.42132), control1: CGPoint(x: 5, y: 8.2574), control2: CGPoint(x: 5, y: 6.3861))
            path.addCurve(to: CGPoint(x: 7.37983, y: 4.58042), control1: CGPoint(x: 6.35159, y: 5.02245), control2: CGPoint(x: 6.8418, y: 4.73288))
            path.addCurve(to: CGPoint(x: 13.5257, y: 6.96393), control1: CGPoint(x: 8.6812, y: 4.21165), control2: CGPoint(x: 10.296, y: 5.12907))
            path.addCurve(to: CGPoint(x: 18.8906, y: 11.154), control1: CGPoint(x: 16.8667, y: 8.86197), control2: CGPoint(x: 18.5371, y: 9.811))
            path.addCurve(to: CGPoint(x: 18.8906, y: 12.846), control1: CGPoint(x: 19.0365, y: 11.7084), control2: CGPoint(x: 19.0365, y: 12.2916))
            path.closeSubpath()
        case .pause:
            path.move(to: CGPoint(x: 4, y: 7))
            path.addCurve(to: CGPoint(x: 4.43934, y: 4.43934), control1: CGPoint(x: 4, y: 5.58579), control2: CGPoint(x: 4, y: 4.87868))
            path.addCurve(to: CGPoint(x: 7, y: 4), control1: CGPoint(x: 4.87868, y: 4), control2: CGPoint(x: 5.58579, y: 4))
            path.addCurve(to: CGPoint(x: 9.56066, y: 4.43934), control1: CGPoint(x: 8.41421, y: 4), control2: CGPoint(x: 9.12132, y: 4))
            path.addCurve(to: CGPoint(x: 10, y: 7), control1: CGPoint(x: 10, y: 4.87868), control2: CGPoint(x: 10, y: 5.58579))
            path.addLine(to: CGPoint(x: 10, y: 17))
            path.addCurve(to: CGPoint(x: 9.56066, y: 19.5607), control1: CGPoint(x: 10, y: 18.4142), control2: CGPoint(x: 10, y: 19.1213))
            path.addCurve(to: CGPoint(x: 7, y: 20), control1: CGPoint(x: 9.12132, y: 20), control2: CGPoint(x: 8.41421, y: 20))
            path.addCurve(to: CGPoint(x: 4.43934, y: 19.5607), control1: CGPoint(x: 5.58579, y: 20), control2: CGPoint(x: 4.87868, y: 20))
            path.addCurve(to: CGPoint(x: 4, y: 17), control1: CGPoint(x: 4, y: 19.1213), control2: CGPoint(x: 4, y: 18.4142))
            path.addLine(to: CGPoint(x: 4, y: 7))
            path.closeSubpath()
            path.move(to: CGPoint(x: 14, y: 7))
            path.addCurve(to: CGPoint(x: 14.4393, y: 4.43934), control1: CGPoint(x: 14, y: 5.58579), control2: CGPoint(x: 14, y: 4.87868))
            path.addCurve(to: CGPoint(x: 17, y: 4), control1: CGPoint(x: 14.8787, y: 4), control2: CGPoint(x: 15.5858, y: 4))
            path.addCurve(to: CGPoint(x: 19.5607, y: 4.43934), control1: CGPoint(x: 18.4142, y: 4), control2: CGPoint(x: 19.1213, y: 4))
            path.addCurve(to: CGPoint(x: 20, y: 7), control1: CGPoint(x: 20, y: 4.87868), control2: CGPoint(x: 20, y: 5.58579))
            path.addLine(to: CGPoint(x: 20, y: 17))
            path.addCurve(to: CGPoint(x: 19.5607, y: 19.5607), control1: CGPoint(x: 20, y: 18.4142), control2: CGPoint(x: 20, y: 19.1213))
            path.addCurve(to: CGPoint(x: 17, y: 20), control1: CGPoint(x: 19.1213, y: 20), control2: CGPoint(x: 18.4142, y: 20))
            path.addCurve(to: CGPoint(x: 14.4393, y: 19.5607), control1: CGPoint(x: 15.5858, y: 20), control2: CGPoint(x: 14.8787, y: 20))
            path.addCurve(to: CGPoint(x: 14, y: 17), control1: CGPoint(x: 14, y: 19.1213), control2: CGPoint(x: 14, y: 18.4142))
            path.addLine(to: CGPoint(x: 14, y: 7))
            path.closeSubpath()
        case .cancel:
            path.move(to: CGPoint(x: 18, y: 6))
            path.addLine(to: CGPoint(x: 6.00081, y: 17.9992))
            path.move(to: CGPoint(x: 17.9992, y: 18))
            path.addLine(to: CGPoint(x: 6, y: 6.00085))
        case .airpods:
            path.move(to: CGPoint(x: 7.32988, y: 10.8464))
            path.addCurve(to: CGPoint(x: 4.66667, y: 11.112), control1: CGPoint(x: 6.49701, y: 11.1966), control2: CGPoint(x: 5.56172, y: 11.2999))
            path.addCurve(to: CGPoint(x: 2, y: 8.05582), control1: CGPoint(x: 3.0702, y: 10.7768), control2: CGPoint(x: 2, y: 9.71696))
            path.addLine(to: CGPoint(x: 2, y: 6.12853))
            path.addCurve(to: CGPoint(x: 5.55556, y: 3.00027), control1: CGPoint(x: 2, y: 4.12164), control2: CGPoint(x: 3.52567, y: 2.97998))
            path.addCurve(to: CGPoint(x: 10.5, y: 7.50659), control1: CGPoint(x: 7.81057, y: 3.0228), control2: CGPoint(x: 10.5, y: 4.76372))
            path.addLine(to: CGPoint(x: 10.5, y: 19.4167))
            path.addCurve(to: CGPoint(x: 10.3969, y: 20.4423), control1: CGPoint(x: 10.5, y: 19.961), control2: CGPoint(x: 10.5, y: 20.2332))
            path.addCurve(to: CGPoint(x: 8.91667, y: 21), control1: CGPoint(x: 10.1069, y: 21.0304), control2: CGPoint(x: 9.48561, y: 21))
            path.addCurve(to: CGPoint(x: 7.43646, y: 20.4423), control1: CGPoint(x: 8.34772, y: 21), control2: CGPoint(x: 7.72646, y: 21.0304))
            path.addCurve(to: CGPoint(x: 7.33333, y: 19.4167), control1: CGPoint(x: 7.33333, y: 20.2332), control2: CGPoint(x: 7.33333, y: 19.961))
            path.addLine(to: CGPoint(x: 7.33333, y: 11.1048))
            path.addCurve(to: CGPoint(x: 7.32988, y: 10.8464), control1: CGPoint(x: 7.33333, y: 11.0161), control2: CGPoint(x: 7.33224, y: 10.93))
            path.closeSubpath()
            path.move(to: CGPoint(x: 7.32988, y: 10.8464))
            path.addLine(to: CGPoint(x: 7.33333, y: 10.845))
            path.move(to: CGPoint(x: 7.32988, y: 10.8464))
            path.addCurve(to: CGPoint(x: 6, y: 8.50004), control1: CGPoint(x: 7.29694, y: 9.68177), control2: CGPoint(x: 7, y: 8.50004))
            path.move(to: CGPoint(x: 16.6701, y: 10.8464))
            path.addCurve(to: CGPoint(x: 19.3333, y: 11.112), control1: CGPoint(x: 17.503, y: 11.1965), control2: CGPoint(x: 18.4383, y: 11.2999))
            path.addCurve(to: CGPoint(x: 22, y: 8.0558), control1: CGPoint(x: 20.9298, y: 10.7768), control2: CGPoint(x: 22, y: 9.71694))
            path.addLine(to: CGPoint(x: 22, y: 6.12851))
            path.addCurve(to: CGPoint(x: 18.4444, y: 3.00024), control1: CGPoint(x: 22, y: 4.12356), control2: CGPoint(x: 20.3874, y: 2.98083))
            path.addCurve(to: CGPoint(x: 13.5, y: 7.50656), control1: CGPoint(x: 16.1894, y: 3.02278), control2: CGPoint(x: 13.5, y: 4.7637))
            path.addLine(to: CGPoint(x: 13.5, y: 19.4167))
            path.addCurve(to: CGPoint(x: 13.6031, y: 20.4423), control1: CGPoint(x: 13.5, y: 19.961), control2: CGPoint(x: 13.5, y: 20.2332))
            path.addCurve(to: CGPoint(x: 15.0833, y: 21), control1: CGPoint(x: 13.8931, y: 21.0304), control2: CGPoint(x: 14.5144, y: 21))
            path.addCurve(to: CGPoint(x: 16.5635, y: 20.4423), control1: CGPoint(x: 15.6523, y: 21), control2: CGPoint(x: 16.2735, y: 21.0304))
            path.addCurve(to: CGPoint(x: 16.6667, y: 19.4167), control1: CGPoint(x: 16.6667, y: 20.2332), control2: CGPoint(x: 16.6667, y: 19.961))
            path.addLine(to: CGPoint(x: 16.6667, y: 11.1048))
            path.addCurve(to: CGPoint(x: 16.6701, y: 10.8464), control1: CGPoint(x: 16.6667, y: 11.0161), control2: CGPoint(x: 16.6678, y: 10.93))
            path.closeSubpath()
            path.move(to: CGPoint(x: 16.6701, y: 10.8464))
            path.addLine(to: CGPoint(x: 16.6667, y: 10.845))
            path.move(to: CGPoint(x: 16.6701, y: 10.8464))
            path.addCurve(to: CGPoint(x: 18, y: 8.50002), control1: CGPoint(x: 16.7031, y: 9.68175), control2: CGPoint(x: 17, y: 8.50002))
        case .chevronDown:
            path.move(to: CGPoint(x: 18, y: 9.00005))
            path.addCurve(to: CGPoint(x: 12, y: 15), control1: CGPoint(x: 18, y: 9.00005), control2: CGPoint(x: 13.5811, y: 15))
            path.addCurve(to: CGPoint(x: 6, y: 9), control1: CGPoint(x: 10.4188, y: 15), control2: CGPoint(x: 6, y: 9))
        case .drag:
            path.move(to: CGPoint(x: 16, y: 6))
            path.addCurve(to: CGPoint(x: 15, y: 7), control1: CGPoint(x: 16, y: 6.55228), control2: CGPoint(x: 15.5523, y: 7))
            path.addCurve(to: CGPoint(x: 14, y: 6), control1: CGPoint(x: 14.4477, y: 7), control2: CGPoint(x: 14, y: 6.55228))
            path.addCurve(to: CGPoint(x: 15, y: 5), control1: CGPoint(x: 14, y: 5.44772), control2: CGPoint(x: 14.4477, y: 5))
            path.addCurve(to: CGPoint(x: 16, y: 6), control1: CGPoint(x: 15.5523, y: 5), control2: CGPoint(x: 16, y: 5.44772))
            path.closeSubpath()
            path.move(to: CGPoint(x: 10, y: 6))
            path.addCurve(to: CGPoint(x: 9, y: 7), control1: CGPoint(x: 10, y: 6.55228), control2: CGPoint(x: 9.55228, y: 7))
            path.addCurve(to: CGPoint(x: 8, y: 6), control1: CGPoint(x: 8.44772, y: 7), control2: CGPoint(x: 8, y: 6.55228))
            path.addCurve(to: CGPoint(x: 9, y: 5), control1: CGPoint(x: 8, y: 5.44772), control2: CGPoint(x: 8.44772, y: 5))
            path.addCurve(to: CGPoint(x: 10, y: 6), control1: CGPoint(x: 9.55228, y: 5), control2: CGPoint(x: 10, y: 5.44772))
            path.closeSubpath()
            path.move(to: CGPoint(x: 16, y: 18))
            path.addCurve(to: CGPoint(x: 15, y: 19), control1: CGPoint(x: 16, y: 18.5523), control2: CGPoint(x: 15.5523, y: 19))
            path.addCurve(to: CGPoint(x: 14, y: 18), control1: CGPoint(x: 14.4477, y: 19), control2: CGPoint(x: 14, y: 18.5523))
            path.addCurve(to: CGPoint(x: 15, y: 17), control1: CGPoint(x: 14, y: 17.4477), control2: CGPoint(x: 14.4477, y: 17))
            path.addCurve(to: CGPoint(x: 16, y: 18), control1: CGPoint(x: 15.5523, y: 17), control2: CGPoint(x: 16, y: 17.4477))
            path.closeSubpath()
            path.move(to: CGPoint(x: 16, y: 12))
            path.addCurve(to: CGPoint(x: 15, y: 13), control1: CGPoint(x: 16, y: 12.5523), control2: CGPoint(x: 15.5523, y: 13))
            path.addCurve(to: CGPoint(x: 14, y: 12), control1: CGPoint(x: 14.4477, y: 13), control2: CGPoint(x: 14, y: 12.5523))
            path.addCurve(to: CGPoint(x: 15, y: 11), control1: CGPoint(x: 14, y: 11.4477), control2: CGPoint(x: 14.4477, y: 11))
            path.addCurve(to: CGPoint(x: 16, y: 12), control1: CGPoint(x: 15.5523, y: 11), control2: CGPoint(x: 16, y: 11.4477))
            path.closeSubpath()
            path.move(to: CGPoint(x: 10, y: 18))
            path.addCurve(to: CGPoint(x: 9, y: 19), control1: CGPoint(x: 10, y: 18.5523), control2: CGPoint(x: 9.55228, y: 19))
            path.addCurve(to: CGPoint(x: 8, y: 18), control1: CGPoint(x: 8.44772, y: 19), control2: CGPoint(x: 8, y: 18.5523))
            path.addCurve(to: CGPoint(x: 9, y: 17), control1: CGPoint(x: 8, y: 17.4477), control2: CGPoint(x: 8.44772, y: 17))
            path.addCurve(to: CGPoint(x: 10, y: 18), control1: CGPoint(x: 9.55228, y: 17), control2: CGPoint(x: 10, y: 17.4477))
            path.closeSubpath()
            path.move(to: CGPoint(x: 10, y: 12))
            path.addCurve(to: CGPoint(x: 9, y: 13), control1: CGPoint(x: 10, y: 12.5523), control2: CGPoint(x: 9.55228, y: 13))
            path.addCurve(to: CGPoint(x: 8, y: 12), control1: CGPoint(x: 8.44772, y: 13), control2: CGPoint(x: 8, y: 12.5523))
            path.addCurve(to: CGPoint(x: 9, y: 11), control1: CGPoint(x: 8, y: 11.4477), control2: CGPoint(x: 8.44772, y: 11))
            path.addCurve(to: CGPoint(x: 10, y: 12), control1: CGPoint(x: 9.55228, y: 11), control2: CGPoint(x: 10, y: 11.4477))
            path.closeSubpath()
        }
        return path
    }

    func image(size: CGFloat = 18) -> NSImage {
        let geometry = path.cgPath
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.scaleBy(x: bounds.width / 24, y: bounds.height / 24)
            context.addPath(geometry)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(2)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct HugeIconView: View {
    let icon: HugeIcon
    var size: CGFloat = 16
    var body: some View {
        icon.path
            .applying(CGAffineTransform(scaleX: size / 24, y: size / 24))
            .stroke(style: StrokeStyle(lineWidth: size / 12, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
