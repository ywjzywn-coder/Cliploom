import AppKit
import ImageIO
import SwiftUI

struct ClipboardRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onToggleFavorite: () -> Void
    @State private var isHovering = false
    private let previewSize: CGFloat = 42

    var body: some View {
        HStack(spacing: 10) {
            preview

            VStack(alignment: .leading, spacing: 4) {
                Text(item.summary)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(item.filesAreAvailable ? .primary : .secondary)

                HStack(spacing: 5) {
                    Image(systemName: item.kind.symbolName)
                    Text(String(localized: String.LocalizationValue(item.kind.localizedKey)))
                    if !item.filesAreAvailable {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Text("•")
                    Text(
                        item.updatedAt.formatted(
                            .dateTime
                                .year()
                                .month(.twoDigits)
                                .day(.twoDigits)
                                .hour(.twoDigits(amPM: .abbreviated))
                        )
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if item.isFavorite || isHovering || isSelected {
                Button(action: onToggleFavorite) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .symbolRenderingMode(.hierarchical)
                        .font(.callout)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .pasteBoxHoverButtonStyle(
                    tint: item.isFavorite ? Color.yellow : Color.accentColor,
                    cornerRadius: 7,
                    isSelected: item.isFavorite
                )
                .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary)
                .help(item.isFavorite ? "action.unfavorite" : "action.favorite")
                .accessibilityLabel(
                    Text(item.isFavorite ? "action.unfavorite" : "action.favorite")
                )
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.5), lineWidth: 0.75)
            } else if isHovering {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 0.75)
            }
        }
        .onHover { isHovering = $0 }
        .animation(.snappy(duration: 0.16), value: isHovering)
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.15)
        }
        if isHovering {
            return Color.primary.opacity(0.055)
        }
        return .clear
    }

    @ViewBuilder
    private var preview: some View {
        if item.kind == .image,
           let path = item.imagePath,
           let image = ClipboardThumbnailCache.shared.thumbnail(
            for: path,
            targetSize: CGSize(width: previewSize, height: previewSize)
           ) {
            thumbnailContainer {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: previewSize, height: previewSize)
            }
        } else if item.kind == .file,
                  let path = item.filePaths.first,
                  FileManager.default.fileExists(atPath: path) {
            thumbnailContainer {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            }
        } else {
            thumbnailContainer {
                Image(systemName: item.kind.symbolName)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.1))
            }
        }
    }

    private func thumbnailContainer<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: previewSize, height: previewSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private final class ClipboardThumbnailCache {
    static let shared = ClipboardThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 160
        cache.totalCostLimit = 24 * 1024 * 1024
    }

    func thumbnail(for path: String, targetSize: CGSize) -> NSImage? {
        let url = URL(fileURLWithPath: path)
        guard let key = cacheKey(for: url, targetSize: targetSize) else { return nil }
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                imageSource,
                0,
                nil
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0,
              height > 0
        else { return nil }

        let scale = max(NSScreen.main?.backingScaleFactor ?? 2, 1)
        let targetPixels = max(targetSize.width, targetSize.height) * scale
        let requiredScale = max(targetPixels / width, targetPixels / height)
        let requiredMaxPixelSize = max(width, height) * min(requiredScale, 1)
        let maxPixelSize = max(targetPixels, min(requiredMaxPixelSize, 512))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelSize.rounded(.up))
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            imageSource,
            0,
            options as CFDictionary
        ) else { return nil }

        let image = NSImage(
            size: targetSize,
            flipped: false
        ) { rect in
            NSColor.clear.setFill()
            rect.fill()
            NSGraphicsContext.current?.imageInterpolation = .medium
            let source = NSImage(cgImage: cgImage, size: NSSize(
                width: cgImage.width,
                height: cgImage.height
            ))
            source.draw(
                in: Self.aspectFillRect(
                    contentSize: source.size,
                    container: rect
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            return true
        }
        image.cacheMode = .always
        cache.setObject(
            image,
            forKey: key as NSString,
            cost: Int(targetSize.width * targetSize.height * scale * scale * 4)
        )
        return image
    }

    private func cacheKey(for url: URL, targetSize: CGSize) -> String? {
        guard let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return nil }
        let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        let fileSize = values.fileSize ?? 0
        return [
            url.path,
            "\(fileSize)",
            "\(modifiedAt)",
            "\(Int(targetSize.width))x\(Int(targetSize.height))"
        ].joined(separator: "|")
    }

    private static func aspectFillRect(
        contentSize: CGSize,
        container: CGRect
    ) -> CGRect {
        guard contentSize.width > 0,
              contentSize.height > 0,
              container.width > 0,
              container.height > 0
        else { return container }

        let scale = max(
            container.width / contentSize.width,
            container.height / contentSize.height
        )
        let size = CGSize(
            width: contentSize.width * scale,
            height: contentSize.height * scale
        )
        return CGRect(
            x: container.midX - size.width / 2,
            y: container.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
