// Regenerate the fictional, local-only document used to demonstrate blur.
// Run from the repository root: swift scripts/render-preview.swift
import AppKit

let width = 1540, height = 1000
let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
    func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                green: Double((hex >> 8) & 255) / 255,
                blue: Double(hex & 255) / 255, alpha: 1)
    }
    func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ hex: UInt32, radius: CGFloat = 0) {
        color(hex).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: radius, yRadius: radius).fill()
    }
    func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
              _ hex: UInt32 = 0x2E303A, _ weight: NSFont.Weight = .regular) {
        (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color(hex)
        ])
    }
    func rule(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat) { fill(x, y, w, 2, 0xE4E4E9) }
    func checkbox(_ x: CGFloat, _ y: CGFloat, checked: Bool) {
        fill(x, y, 28, 28, checked ? 0xDCD7EF : 0xEDECF1, radius: 8)
        if checked { text("✓", x + 5, y + 1, 21, 0x6D608F, .semibold) }
    }

    fill(0, 0, 1540, 1000, 0xFAFAFC)
    fill(0, 0, 282, 1000, 0xECECF1)
    fill(282, 0, 1258, 118, 0xF5F5F8)
    rule(282, 117, 1258)
    for (i, shade) in [UInt32(0xE2A9AA), 0xE1CAA4, 0xB8CEB7].enumerated() {
        fill(38 + CGFloat(i) * 30, 44, 16, 16, shade, radius: 8)
    }
    text("Personal workspace", 626, 45, 26, 0x8D8D9A, .medium)
    text("WORKSPACE", 36, 168, 19, 0x9897A4, .semibold)
    fill(20, 223, 242, 62, 0xDDD8EC, radius: 12)
    text("Notes", 58, 237, 25, 0x64587C, .medium)
    text("Messages", 58, 321, 25, 0x777784)
    text("Documents", 58, 404, 25, 0x777784)
    rule(36, 488, 210)
    text("PINNED", 36, 532, 19, 0x9897A4, .semibold)
    text("Launch notes", 58, 591, 24, 0x777784)
    text("Reading list", 58, 670, 24, 0x9897A4)
    text("Ideas", 58, 749, 24, 0x9897A4)
    fill(40, 899, 44, 44, 0xD8D3E7, radius: 22)
    text("A", 54, 907, 22, 0x776A93, .medium)
    text("My workspace", 101, 909, 22, 0x858590)

    text("NOTES  /  PERSONAL", 358, 176, 20, 0x9594A1, .medium)
    text("Launch notes", 354, 238, 58, 0x30313B, .semibold)
    text("A few things to finish before we share.", 358, 330, 28, 0x858591)
    rule(358, 402, 1092)
    text("Keep it simple.", 358, 455, 32, 0x41424D, .semibold)
    text("Lead with what the app does and who it helps.", 358, 514, 27, 0x777984)
    text("Give people a clear way to try it for themselves.", 358, 559, 27, 0x777984)
    fill(356, 663, 1096, 256, 0xF0EEF6, radius: 20)
    text("Before sharing", 390, 691, 25, 0x625A77, .semibold)
    checkbox(390, 750, checked: true)
    text("Review the demo", 438, 749, 25, 0x787184)
    checkbox(390, 805, checked: true)
    text("Keep private details out", 438, 804, 25, 0x787184)
    checkbox(390, 860, checked: false)
    text("Send the draft for feedback", 438, 859, 25, 0x787184)
    return true
}
var rect = NSRect(x: 0, y: 0, width: width, height: height)
guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
      let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
    fatalError("Could not render the preview document")
}
try data.write(to: URL(fileURLWithPath: "Resources/Preview/BlurPreview.png"))
print("Rendered fictional preview document: \(cgImage.width) × \(cgImage.height)")
