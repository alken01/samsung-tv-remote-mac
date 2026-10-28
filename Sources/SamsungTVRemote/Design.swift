import SwiftUI

/// Shared measurements and type, so every screen uses the same rhythm.
///
/// Shape language: circles and capsules are things you press; rounded rectangles are surfaces
/// and rows; an icon with no container is decoration. A static icon never sits in a glass circle.
enum Design {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
    }

    enum Radius {
        /// Standalone glass surfaces: cards, lists, shelves, fields.
        static let card: CGFloat = 20
        /// Rows inside a card, inset by `Space.xs` so their corners stay concentric with it.
        static let row: CGFloat = card - Space.xs
    }

    /// Diameters for round buttons.
    enum Control {
        static let small: CGFloat = 28
        static let regular: CGFloat = 32
        static let large: CGFloat = 36
    }

    static let panelWidth: CGFloat = 288
    static let rowHeight: CGFloat = 36

    enum Font {
        static let title = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let body = SwiftUI.Font.system(size: 13, weight: .medium)
        static let button = SwiftUI.Font.system(size: 13, weight: .semibold)
        static let label = SwiftUI.Font.caption.weight(.semibold)
        static let detail = SwiftUI.Font.caption
    }
}

/// Small grey label above a group of controls.
struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(Design.Font.label)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Design.Space.xs)
    }
}

/// A glass card holding rows, like a grouped list in System Settings.
struct ListCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0, content: content)
            .padding(Design.Space.xs)
            .frame(maxWidth: .infinity)
            .glassSurface(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
    }
}

/// Hairline between rows of a `ListCard`, aligned with the row text.
struct RowDivider: View {
    var inset: CGFloat = Design.Space.m - Design.Space.xs
    var body: some View {
        Rectangle().fill(.primary.opacity(0.08)).frame(height: 0.5).padding(.horizontal, inset)
    }
}

/// Row content: optional plain symbol, title, optional detail line, trailing accessory.
struct RowLabel<Trailing: View>: View {
    var symbol: String? = nil
    let title: String
    var detail: String? = nil
    var tint: Color? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Design.Space.m) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                    .frame(width: 20)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Design.Font.body)
                    .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                    .lineLimit(1)
                if let detail {
                    Text(detail).font(Design.Font.detail.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, Design.Space.m - Design.Space.xs)
        .frame(minHeight: Design.rowHeight)
        .padding(.vertical, detail == nil ? 0 : Design.Space.xs)
    }
}

extension RowLabel where Trailing == EmptyView {
    init(symbol: String? = nil, title: String, detail: String? = nil, tint: Color? = nil) {
        self.init(symbol: symbol, title: title, detail: detail, tint: tint) { EmptyView() }
    }
}

/// A pressable row inside a `ListCard`, with a hover wash matching the card's corners.
struct RowButton<Trailing: View>: View {
    var symbol: String? = nil
    let title: String
    var detail: String? = nil
    var tint: Color? = nil
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        Button(action: action) {
            RowLabel(symbol: symbol, title: title, detail: detail, tint: tint, trailing: trailing)
        }
        .buttonStyle(PressStyle(shape: AnyShape(RoundedRectangle(cornerRadius: Design.Radius.row, style: .continuous)),
                                pressScale: 0.98))
    }
}

extension RowButton where Trailing == EmptyView {
    init(symbol: String? = nil, title: String, detail: String? = nil, tint: Color? = nil, action: @escaping () -> Void) {
        self.init(symbol: symbol, title: title, detail: detail, tint: tint, action: action) { EmptyView() }
    }
}

/// Trailing chevron, with an optional value, for rows that open another screen.
struct Disclosure: View {
    var value: String? = nil
    var body: some View {
        HStack(spacing: Design.Space.s) {
            if let value { Text(value).font(Design.Font.detail).foregroundStyle(.secondary) }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }
}
