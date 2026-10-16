import SwiftUI

// Runtime token owner. DESIGN.md documents this native system; no parallel CSS theme exists.
enum BridgeTheme {
    static let accent = Color(red: 0.075, green: 0.36, blue: 0.33)
    static let spacing: CGFloat = 20
    static let radius: CGFloat = 18
    static let title: Font = .system(.largeTitle, design: .rounded, weight: .bold)
    static let utility: Font = .system(.caption, design: .monospaced)
}

struct BridgeCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .padding(BridgeTheme.spacing)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: BridgeTheme.radius))
    }
}
