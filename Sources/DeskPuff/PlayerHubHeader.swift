import AppKit
import SwiftUI

@MainActor struct PlayerHubHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var navigation: PlayerHubNavigation
    let balance: String

    private let violet = Color(red: 0.69, green: 0.32, blue: 1)
    private let lilac = Color(red: 0.89, green: 0.68, blue: 1)
    private let pink = Color(red: 1, green: 0.63, blue: 0.99)
    private let white = Color(red: 0.99, green: 0.95, blue: 1)
    private let ink = Color(red: 0.15, green: 0.108, blue: 0.21)

    private static let logoImage = loadArtwork("PlayerHubLogo")
    private static let smokeImage = loadArtwork("PlayerHubSmoke")

    private static func loadArtwork(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Resources") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        HStack(spacing: 15) {
            logo
            Rectangle().fill(lilac.opacity(0.25)).frame(width: 1, height: 46)
                .accessibilityHidden(true)
            tabs
            Spacer(minLength: 20)
            wallet
        }
        .padding(.horizontal, 25)
        .padding(.top, 51)
        .padding(.bottom, 12)
        .background {
            ZStack {
                backdrop
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                WindowDragArea()
                    .accessibilityHidden(true)
            }
        }
    }

    private var backdrop: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.18, green: 0.127, blue: 0.235),
                    Color(red: 0.135, green: 0.097, blue: 0.18)
                ], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [violet.opacity(0.14), .clear],
                               center: UnitPoint(x: 0.15, y: 0.63), startRadius: 0, endRadius: 315)
                RadialGradient(colors: [violet.opacity(0.09), .clear],
                               center: UnitPoint(x: 0.76, y: 0.80), startRadius: 0, endRadius: 255)
                if let smoke = Self.smokeImage {
                    Image(nsImage: smoke)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: min(570, width * 0.43), height: 100)
                        .opacity(0.33)
                        .blendMode(.screen)
                        .position(x: width * 0.735, y: height - 45)
                }
                rim(highlights: [0.19, 0.85])
                    .frame(maxHeight: .infinity, alignment: .top)
                rim(highlights: [0.53], baseOpacity: 0.27)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipped()
    }

    private func rim(highlights: [CGFloat], baseOpacity: Double = 0.52) -> some View {
        ZStack {
            Rectangle().fill(lilac.opacity(baseOpacity)).frame(height: 1)
            ForEach(highlights, id: \.self) { x in
                RadialGradient(colors: [violet.opacity(0.92), violet.opacity(0.36), .clear],
                               center: UnitPoint(x: x, y: 0.5), startRadius: 0, endRadius: 129)
                    .frame(height: 5)
                    .blur(radius: 4)
                RadialGradient(colors: [white, pink.opacity(0.75), .clear],
                               center: UnitPoint(x: x, y: 0.5), startRadius: 0, endRadius: 114)
                    .frame(height: 1)
            }
        }
        .frame(height: 1)
    }

    private var logo: some View {
        let outline = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Group {
            if let image = Self.logoImage {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "smoke.fill").resizable().scaledToFit().padding(15).foregroundStyle(lilac)
            }
        }
        .frame(width: 64, height: 64)
        .background(outline.fill(ink))
        .clipShape(outline)
        .overlay {
            outline.strokeBorder(
                LinearGradient(colors: [white.opacity(0.90), lilac.opacity(0.22), violet.opacity(0.40), pink.opacity(0.82)],
                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
        }
        .shadow(color: violet.opacity(0.67), radius: 9)
        .shadow(color: violet.opacity(0.35), radius: 16, y: 1)
        .overlay(alignment: .bottom) {
            Capsule().fill(pink.opacity(0.9)).frame(width: 19, height: 1.5)
                .shadow(color: pink, radius: 3)
        }
        .accessibilityLabel("DeskPuff")
        .allowsHitTesting(false)
    }

    private var tabs: some View {
        let tabs = PlayerHubTab.allCases
        let selectionIndex = tabs.firstIndex(of: navigation.selected) ?? 0
        return HStack(spacing: 0) {
            ForEach(tabs) { tab in
                let selected = navigation.selected == tab
                Button {
                    navigation.selected = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol).font(.system(size: 13, weight: .medium))
                            .accessibilityHidden(true)
                        Text(tr(tab.rawValue))
                            .font(.system(size: 13, weight: .medium))
                            .tracking(0.18)
                            .lineLimit(1).minimumScaleFactor(0.78)
                    }
                    .foregroundStyle(white.opacity(selected ? 1 : 0.86))
                    .frame(maxWidth: .infinity)
                    .frame(height: 35)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .overlay(alignment: .trailing) {
                    if tab != .recovery && !selected && navigation.selected != nextTab(after: tab) {
                        Rectangle().fill(lilac.opacity(0.26)).frame(width: 1, height: 14)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
            }
        }
        .background {
            GeometryReader { geometry in
                let segmentWidth = geometry.size.width / CGFloat(tabs.count)
                selectedTab
                    .frame(width: segmentWidth, height: geometry.size.height)
                    .offset(x: segmentWidth * CGFloat(selectionIndex))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: selectionIndex)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(2)
        .background {
            Capsule().fill(
                LinearGradient(colors: [Color(red: 0.24, green: 0.16, blue: 0.32), ink.opacity(0.78),
                                        Color(red: 0.20, green: 0.13, blue: 0.27)],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(colors: [lilac.opacity(0.57), lilac.opacity(0.27), violet.opacity(0.71)],
                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.85)
                .allowsHitTesting(false)
        }
        .frame(width: 428)
    }

    private func nextTab(after tab: PlayerHubTab) -> PlayerHubTab? {
        switch tab {
        case .rank: .inventory
        case .inventory: .store
        case .store: .recovery
        case .recovery: nil
        }
    }

    private var selectedTab: some View {
        Capsule().fill(
            LinearGradient(colors: [Color(red: 0.73, green: 0.48, blue: 0.95),
                                    Color(red: 0.54, green: 0.31, blue: 0.78),
                                    Color(red: 0.41, green: 0.22, blue: 0.60)],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay {
            Capsule().fill(
                LinearGradient(stops: [.init(color: lilac.opacity(0.36), location: 0),
                                       .init(color: .clear, location: 0.29),
                                       .init(color: .clear, location: 0.71),
                                       .init(color: pink.opacity(0.48), location: 1)],
                               startPoint: .top, endPoint: .bottom))
        }
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(colors: [white, lilac.opacity(0.73), lilac.opacity(0.30), pink],
                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        }
        .shadow(color: pink.opacity(0.56), radius: 3)
        .shadow(color: violet.opacity(0.66), radius: 10)
    }

    private var wallet: some View {
        HStack(spacing: 11) {
            Image(systemName: "creditcard.fill").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(lilac)
                .shadow(color: violet.opacity(0.7), radius: 5)
                .accessibilityHidden(true)
            Text(balance)
                .font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(
                    LinearGradient(colors: [Color(red: 1, green: 0.97, blue: 0.82),
                                            Color(red: 1, green: 0.76, blue: 0.44)],
                                   startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(red: 1, green: 0.50, blue: 0.22).opacity(0.55), radius: 5)
        }
        .padding(.horizontal, 17)
        .frame(minWidth: 120, minHeight: 45)
        .fixedSize()
        .background {
            Capsule().fill(ink)
            Capsule().fill(
                RadialGradient(colors: [violet.opacity(0.42), violet.opacity(0.12), .clear],
                               center: UnitPoint(x: 0.10, y: 0.17), startRadius: 0, endRadius: 76))
        }
        .overlay {
            Capsule().strokeBorder(
                LinearGradient(colors: [white.opacity(0.96), lilac.opacity(0.57), lilac.opacity(0.21)],
                               startPoint: .topLeading, endPoint: .trailing), lineWidth: 1)
            Capsule().strokeBorder(
                LinearGradient(colors: [.clear, .clear, pink.opacity(0.73), .clear],
                               startPoint: .top, endPoint: .bottomTrailing), lineWidth: 1.3)
        }
        .shadow(color: violet.opacity(0.28), radius: 9)
        .accessibilityLabel(tr("可用余额"))
        .accessibilityValue(balance)
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowDragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowDragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
