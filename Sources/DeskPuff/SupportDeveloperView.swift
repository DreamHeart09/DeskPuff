import AppKit
import SwiftUI

@MainActor struct SupportDeveloperView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text(tr("如果 DeskPuff 为你的桌面带来了一点乐趣，欢迎自愿支持项目的持续开发。"))
                .font(.system(size: 13))
                .foregroundStyle(InventoryTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 16) {
                SupportPaymentCard(title: tr("微信赞赏"), imageName: "WeChatQR", imageExtension: "JPG")
                SupportPaymentCard(title: tr("支付宝支持"), imageName: "AlipayQR", imageExtension: "PNG")
            }
            .frame(maxWidth: .infinity)

            Text(tr("纯自愿支持 · 不影响游戏功能"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(InventoryTheme.secondaryText.opacity(0.88))
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(width: 720)
        .foregroundStyle(InventoryTheme.primaryText)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LinearGradient(colors: [InventoryTheme.panelTop, InventoryTheme.backgroundBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topLeading) {
                    Circle().fill(InventoryTheme.accent.opacity(0.13))
                        .frame(width: 260, height: 150).blur(radius: 46).offset(x: -95, y: -90)
                        .allowsHitTesting(false)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .environment(\.colorScheme, .dark)
        .tint(InventoryTheme.accentBright)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(InventoryTheme.gold)
                .frame(width: 52, height: 52)
                .background(InventoryTheme.accent.opacity(0.17), in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 3) {
                Text(tr("请开发者喝杯咖啡"))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text(tr("支持 DeskPuff"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(InventoryTheme.secondaryText)
            }
            Spacer()
        }
    }
}

private struct SupportPaymentCard: View {
    let title: String
    let imageName: String
    let imageExtension: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(InventoryTheme.primaryText)

            if let image = qrImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 218, height: 218)
                    .padding(7)
                    .background(.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .accessibilityLabel(tr("{{0}}收款二维码", title))
            } else {
                ContentUnavailableView(tr("收款码暂不可用"), systemImage: "qrcode")
                    .frame(width: 218, height: 218)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(11)
        .background(InventoryTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(InventoryTheme.outline, lineWidth: 0.8)
        }
    }

    private var qrImage: NSImage? {
        guard let url = Bundle.module.url(forResource: imageName,
                                          withExtension: imageExtension,
                                          subdirectory: "Resources/Support") else { return nil }
        return NSImage(contentsOf: url)
    }
}
