import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

// Shared runtime token owner for both native applications. See DESIGN.md.
enum BridgeTheme {
    static let ink = Color(red: 17/255, green: 30/255, blue: 68/255)
    static let accent: Color = {
        #if os(iOS)
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.56, green: 0.66, blue: 1, alpha: 1) : UIColor(red: 0.22, green: 0.36, blue: 0.85, alpha: 1) })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.56, green: 0.66, blue: 1, alpha: 1) : NSColor(red: 0.22, green: 0.36, blue: 0.85, alpha: 1)
        })
        #endif
    }()
    static let danger: Color = {
        #if os(iOS)
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.71, blue: 0.67, alpha: 1) : UIColor(red: 0.73, green: 0.10, blue: 0.10, alpha: 1) })
        #else
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 1, green: 0.71, blue: 0.67, alpha: 1) : NSColor(red: 0.73, green: 0.10, blue: 0.10, alpha: 1) })
        #endif
    }()
    static let spacing: CGFloat = 20
    static let radius: CGFloat = 22
    static let title: Font = .system(.largeTitle, design: .rounded, weight: .bold)
    static let utility: Font = .system(.caption, design: .monospaced)
    static var background: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    static var surface: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

struct BridgeCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(BridgeTheme.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BridgeTheme.surface, in: RoundedRectangle(cornerRadius: BridgeTheme.radius))
    }
}

struct BrandMark: View {
    var size: CGFloat = 48
    var body: some View {
        Group {
            #if os(iOS)
            Image("BrandMark").resizable()
            #else
            if let image = NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("BrandMark.png")) { Image(nsImage: image).resizable() }
            else { Image(systemName: "v.square.fill").resizable().foregroundStyle(BridgeTheme.accent) }
            #endif
        }
        .aspectRatio(contentMode: .fit).frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.23)).accessibilityHidden(true)
    }
}

extension String {
    var bridgeDate: Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: self) ?? ISO8601DateFormatter().date(from: self)
    }
}

extension Calendar {
    static var bridge: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_Hans_CN")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
}
