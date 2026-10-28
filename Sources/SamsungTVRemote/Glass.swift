import SwiftUI

// Disambiguate the property wrapper from the newer SDK macro of the same name.
typealias NativeState<Value> = SwiftUI.State<Value>

extension View {
    /// Liquid Glass on macOS 26 and later, a quiet material surface on earlier systems.
    @ViewBuilder func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background {
                shape.fill(.regularMaterial)
                if let tint { shape.fill(tint.opacity(0.22)) }
            }
            .overlay { shape.stroke(.white.opacity(0.14), lineWidth: 0.5) }
        }
    }

    /// Capsule text button in the same style as the rest of the remote.
    func glassControl(prominent: Bool = false) -> some View {
        buttonStyle(CapsuleStyle(prominent: prominent))
    }
}

/// The accent fill shared by OK and prominent buttons.
struct AccentFill<S: Shape>: View {
    let shape: S
    var body: some View {
        shape.fill(LinearGradient(colors: [.accentColor.opacity(0.95), .accentColor.opacity(0.75)],
                                  startPoint: .top, endPoint: .bottom))
            .overlay { shape.stroke(.white.opacity(0.25), lineWidth: 0.5) }
    }
}

struct CapsuleStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleBody(configuration: configuration, prominent: prominent)
    }

    private struct CapsuleBody: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let label = configuration.label
                .labelStyle(.titleAndIcon)
                .font(Design.Font.button)
                .padding(.horizontal, Design.Space.l)
                .frame(minHeight: Design.Control.regular)
                .contentShape(Capsule())
            Group {
                if prominent {
                    label.foregroundStyle(.white).background { AccentFill(shape: Capsule()) }
                        .shadow(color: .accentColor.opacity(enabled ? 0.3 : 0), radius: 8, y: 2)
                } else {
                    label.foregroundStyle(configuration.role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                        .glassSurface(Capsule(), interactive: true)
                }
            }
            .opacity(enabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
        }
    }
}

/// Fades content that sits on interactive glass when its button is disabled.
struct EnabledFade: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View { content.opacity(enabled ? 1 : 0.35) }
}

/// A plain button with a soft hover wash and a small press-down, for controls drawn on top of glass.
struct PressStyle: ButtonStyle {
    var shape = AnyShape(Circle())
    var highlight = true
    var pressScale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, shape: shape, highlight: highlight, pressScale: pressScale)
    }

    private struct PressBody: View {
        let configuration: ButtonStyleConfiguration
        let shape: AnyShape
        let highlight: Bool
        let pressScale: CGFloat
        @Environment(\.isEnabled) private var enabled
        @NativeState private var hovering = false

        var body: some View {
            configuration.label
                .contentShape(shape)
                .background {
                    if highlight {
                        shape.fill(.primary.opacity(configuration.isPressed ? 0.14 : hovering ? 0.07 : 0))
                    }
                }
                .opacity(enabled ? 1 : 0.35)
                .scaleEffect(configuration.isPressed ? pressScale : 1)
                .animation(.snappy(duration: 0.18), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = enabled && $0 }
        }
    }
}

/// Round glass button holding a single SF Symbol.
struct GlassIconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = Design.Control.large
    var color: Color? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.36, weight: .semibold))
                .foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
                // Glass inside a container draws its own content, so fade the glyph itself.
                .opacity(enabled ? 1 : 0.35)
                .frame(width: size, height: size)
                .glassSurface(Circle(), interactive: true)
        }
        .buttonStyle(PressStyle(highlight: false))
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Grouped content on a rounded glass card.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = Design.Space.l
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.m, content: content)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface(RoundedRectangle(cornerRadius: Design.Radius.card, style: .continuous))
    }
}
