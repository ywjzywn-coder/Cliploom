import AppKit
import SwiftUI

struct ClipboardRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onToggleFavorite: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            preview
                .frame(width: 42, height: 42)

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
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
            }
        }
        .onHover { isHovering = $0 }
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
           let image = NSImage(contentsOfFile: path) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if item.kind == .file,
                  let path = item.filePaths.first,
                  FileManager.default.fileExists(atPath: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
                .padding(5)
        } else {
            Image(systemName: item.kind.symbolName)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Color.accentColor.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
        }
    }
}
