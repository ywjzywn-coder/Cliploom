import SwiftData
import SwiftUI

private enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case favorite
    case text
    case link
    case image
    case file

    var id: String { rawValue }

    var localizedKey: String {
        switch self {
        case .all: "category.all"
        case .text: "category.text"
        case .link: "category.links"
        case .image: "category.images"
        case .file: "category.files"
        case .favorite: "category.favorites"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "square.stack.3d.up"
        case .favorite: "star"
        case .text: ClipboardKind.text.symbolName
        case .link: ClipboardKind.link.symbolName
        case .image: ClipboardKind.image.symbolName
        case .file: ClipboardKind.file.symbolName
        }
    }
}

struct ClipboardPanelView: View {
    @EnvironmentObject private var controller: AppController
    @Query(sort: \ClipboardItem.updatedAt, order: .reverse) private var items: [ClipboardItem]
    @State private var filter: ClipboardFilter = .all
    @State private var searchText = ""
    @State private var selectedID: UUID?
    @FocusState private var searchIsFocused: Bool

    private var filteredItems: [ClipboardItem] {
        items.filter { item in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .favorite: matchesFilter = item.isFavorite
            case .text: matchesFilter = item.kind == .text
            case .link: matchesFilter = item.kind == .link
            case .image: matchesFilter = item.kind == .image
            case .file: matchesFilter = item.kind == .file
            }

            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || item.summary.localizedCaseInsensitiveContains(query)
                || (item.textContent?.localizedCaseInsensitiveContains(query) ?? false)
                || item.filePaths.contains { $0.localizedCaseInsensitiveContains(query) }
            return matchesFilter && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filters
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 440, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 0.5)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteBoxPanelWillShow)) { _ in
            searchText = ""
            filter = .all
            selectedID = filteredItems.first?.id
            DispatchQueue.main.async { searchIsFocused = true }
        }
        .onChange(of: filter) { _, _ in selectFirst() }
        .onChange(of: searchText) { _, _ in selectFirst() }
        .onChange(of: items.count) { _, _ in
            if selectedItem == nil { selectFirst() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteBoxMoveSelection)) { value in
            moveSelection(by: value.userInfo?["offset"] as? Int ?? 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteBoxConfirmSelection)) { _ in
            if let selectedItem { controller.paste(selectedItem) }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "clipboard")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text("sidebar.clipboard")
                        .font(.headline)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
                .overlay {
                    WindowDragRegion()
                }

                Button {
                    controller.isPaused.toggle()
                } label: {
                    Image(
                        systemName: controller.isPaused
                            ? "record.circle"
                            : "pause.circle"
                    )
                    .frame(width: 28, height: 28)
                }
                .pasteBoxHoverButtonStyle(
                    tint: controller.isPaused ? Color.orange : Color.accentColor,
                    cornerRadius: 7
                )
                .foregroundStyle(controller.isPaused ? Color.orange : Color.secondary)
                .help(controller.isPaused ? "menu.resume" : "menu.pause")

                Button {
                    controller.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 28, height: 28)
                }
                .pasteBoxHoverButtonStyle(cornerRadius: 7)
                .foregroundStyle(.secondary)
                .help("menu.settings")
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("search.placeholder", text: $searchText)
                    .textFieldStyle(.plain)
                    .focused($searchIsFocused)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(width: 22, height: 22)
                    }
                    .pasteBoxHoverButtonStyle(tint: .secondary, cornerRadius: 6)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var filters: some View {
        HStack(spacing: 3) {
            ForEach(ClipboardFilter.allCases) { value in
                Button {
                    filter = value
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: value.symbolName)
                        Text(String(localized: String.LocalizationValue(value.localizedKey)))
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .padding(.horizontal, 7)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
                }
                .pasteBoxHoverCapsuleButtonStyle(isSelected: filter == value)
                .foregroundStyle(filter == value ? Color.primary : Color.secondary)
                .help(
                    "\(String(localized: String.LocalizationValue(value.localizedKey))) · \(count(for: value))"
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "empty.title" : "empty.search.title",
                systemImage: searchText.isEmpty ? filter.symbolName : "magnifyingglass",
                description: Text(
                    searchText.isEmpty ? "empty.description" : "empty.search.description"
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(filteredItems) { item in
                            ClipboardRowView(
                                item: item,
                                isSelected: selectedID == item.id,
                                onToggleFavorite: {
                                    controller.toggleFavorite(item)
                                }
                            )
                                .id(item.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { controller.paste(item) }
                                .onTapGesture { selectedID = item.id }
                                .contextMenu { contextMenu(for: item) }
                        }
                    }
                    .padding(8)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.32))
                .onChange(of: selectedID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.snappy(duration: 0.18)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            KeyHint(keys: "↑↓", label: "panel.select")
            KeyHint(keys: "↩", label: "action.paste")
            Spacer()
            Text("\(filteredItems.count)")
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func contextMenu(for item: ClipboardItem) -> some View {
        Button {
            controller.paste(item)
        } label: {
            Label("action.paste", systemImage: "arrow.turn.down.left")
        }
        Button {
            controller.copyOnly(item)
        } label: {
            Label("action.copy", systemImage: "doc.on.doc")
        }
        Button {
            controller.toggleFavorite(item)
        } label: {
            Label(
                item.isFavorite ? "action.unfavorite" : "action.favorite",
                systemImage: item.isFavorite ? "star.slash" : "star"
            )
        }
        if item.kind == .file {
            Button {
                controller.revealInFinder(item)
            } label: {
                Label("action.reveal", systemImage: "folder")
            }
            .disabled(!item.filesAreAvailable)
        }
        Divider()
        Button(role: .destructive) {
            controller.delete(item)
        } label: {
            Label("action.delete", systemImage: "trash")
        }
    }

    private var selectedItem: ClipboardItem? {
        filteredItems.first { $0.id == selectedID }
    }

    private func count(for value: ClipboardFilter) -> Int {
        switch value {
        case .all: items.count
        case .favorite: items.filter(\.isFavorite).count
        case .text: items.filter { $0.kind == .text }.count
        case .link: items.filter { $0.kind == .link }.count
        case .image: items.filter { $0.kind == .image }.count
        case .file: items.filter { $0.kind == .file }.count
        }
    }

    private func selectFirst() {
        selectedID = filteredItems.first?.id
    }

    private func moveSelection(by offset: Int) {
        guard !filteredItems.isEmpty else { return }
        let currentIndex = filteredItems.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(currentIndex + offset, 0), filteredItems.count - 1)
        selectedID = filteredItems[next].id
    }
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

private struct KeyHint: View {
    let keys: String
    let label: LocalizedStringKey

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.caption2.weight(.medium).monospaced())
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
        }
    }
}
