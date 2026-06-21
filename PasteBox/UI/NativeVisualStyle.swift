import AppKit
import SwiftUI

struct PasteBoxHoverButtonStyle: ButtonStyle {
    enum Shape {
        case rounded(CGFloat)
        case capsule
    }

    var tint: Color = .accentColor
    var shape: Shape = .rounded(8)
    var isSelected = false

    func makeBody(configuration: Configuration) -> some View {
        PasteBoxHoverButtonBody(
            configuration: configuration,
            tint: tint,
            shape: shape,
            isSelected: isSelected
        )
    }
}

private struct PasteBoxHoverButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color
    let shape: PasteBoxHoverButtonStyle.Shape
    let isSelected: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        let shape = PasteBoxHoverShape(shape: shape)
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : (isHovering && isEnabled ? 1.045 : 1))
            .background(shape.fill(backgroundColor))
            .overlay {
                shape
                    .stroke(borderColor, lineWidth: isHovering && isEnabled ? 1 : 0)
            }
            .animation(.snappy(duration: 0.16), value: isHovering)
            .animation(.snappy(duration: 0.10), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return .clear
        }
        if configuration.isPressed {
            return tint.opacity(0.22)
        }
        if isSelected {
            return tint.opacity(isHovering ? 0.22 : 0.16)
        }
        return tint.opacity(isHovering ? 0.12 : 0)
    }

    private var borderColor: Color {
        isEnabled ? tint.opacity(isHovering ? 0.32 : 0) : .clear
    }
}

private struct PasteBoxHoverShape: InsettableShape {
    let shape: PasteBoxHoverButtonStyle.Shape
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        switch shape {
        case let .rounded(radius):
            return RoundedRectangle(cornerRadius: radius, style: .continuous)
                .path(in: rect)
        case .capsule:
            return Capsule().path(in: rect)
        }
    }

    func inset(by amount: CGFloat) -> PasteBoxHoverShape {
        PasteBoxHoverShape(shape: shape, insetAmount: insetAmount + amount)
    }
}

extension View {
    @ViewBuilder
    func pasteBoxGlass(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(
                Glass.regular.tint(tint).interactive(interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(.separator.opacity(0.45), lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder
    func pasteBoxPrimaryButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func pasteBoxGlassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    func pasteBoxHoverButtonStyle(
        tint: Color = .accentColor,
        cornerRadius: CGFloat = 8,
        isSelected: Bool = false
    ) -> some View {
        buttonStyle(
            PasteBoxHoverButtonStyle(
                tint: tint,
                shape: .rounded(cornerRadius),
                isSelected: isSelected
            )
        )
    }

    func pasteBoxHoverCapsuleButtonStyle(
        tint: Color = .accentColor,
        isSelected: Bool = false
    ) -> some View {
        buttonStyle(
            PasteBoxHoverButtonStyle(
                tint: tint,
                shape: .capsule,
                isSelected: isSelected
            )
        )
    }
}

struct ApplicationIconView: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
