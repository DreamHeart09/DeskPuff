import SwiftUI

enum PlayerHubSurface {
    case panel, display, inset, item, active

    private var colors: [Color] {
        switch self {
        case .panel: [Color(red: 0.193, green: 0.138, blue: 0.265), Color(red: 0.105, green: 0.078, blue: 0.154)]
        case .display: [Color(red: 0.129, green: 0.087, blue: 0.184), Color(red: 0.080, green: 0.056, blue: 0.121)]
        case .inset: [Color(red: 0.080, green: 0.057, blue: 0.121), Color(red: 0.124, green: 0.090, blue: 0.169)]
        case .item: [Color(red: 0.270, green: 0.177, blue: 0.370), Color(red: 0.167, green: 0.116, blue: 0.238)]
        case .active: [Color(red: 0.57, green: 0.35, blue: 0.78), Color(red: 0.35, green: 0.18, blue: 0.53)]
        }
    }

    private var edgeOpacity: Double {
        switch self {
        case .panel: 0.35
        case .display: 0.25
        case .inset: 0.19
        case .item: 0.60
        case .active: 0.88
        }
    }

    func fill<S: InsettableShape>(_ shape: S, tint: Color) -> some View {
        ZStack {
            shape.fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            if self == .display {
                GeometryReader { geometry in
                    let spread = max(geometry.size.width, geometry.size.height)
                    ZStack {
                        shape.fill(RadialGradient(colors: [tint.opacity(0.27), tint.opacity(0.07), .clear],
                                                  center: UnitPoint(x: 0.5, y: 0.49), startRadius: 0, endRadius: spread * 0.66))
                        RadialGradient(colors: [tint.opacity(0.30), tint.opacity(0.10), .clear],
                                       center: .center, startRadius: 0, endRadius: geometry.size.width * 0.36)
                            .frame(width: geometry.size.width * 0.76, height: geometry.size.width * 0.76)
                            .scaleEffect(x: 1, y: 0.22)
                            .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.80)
                    }
                }
                .clipShape(shape)
            }
            if self == .active {
                shape.fill(LinearGradient(stops: [
                    .init(color: .white.opacity(0.22), location: 0),
                    .init(color: .clear, location: 0.26),
                    .init(color: .clear, location: 0.74),
                    .init(color: tint.opacity(0.34), location: 1)
                ], startPoint: .top, endPoint: .bottom))
            }
            shape.strokeBorder(LinearGradient(colors: [
                InventoryTheme.accentBright.opacity(edgeOpacity),
                tint.opacity(edgeOpacity * 0.34),
                tint.opacity(edgeOpacity * (self == .active ? 0.74 : 0.54))
            ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: self == .active || self == .item ? 1 : 0.75)
        }
    }
}

extension View {
    func playerHubSurface<S: InsettableShape>(_ surface: PlayerHubSurface, in shape: S,
                                               tint: Color = InventoryTheme.accent) -> some View {
        background {
            surface.fill(shape, tint: tint)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    func playerHubSurface(_ surface: PlayerHubSurface, radius: CGFloat,
                          tint: Color = InventoryTheme.accent) -> some View {
        playerHubSurface(surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous), tint: tint)
    }
}
