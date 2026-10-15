import Combine
import Quartz
import SwiftUI

/// The state of the file in the preview pane. An object, not `@State`, as the rest of the app keeps view state
/// (`@State` needs a macro plugin that the checks' direct compile does not load).
@MainActor
final class FilePreviewModel: ObservableObject {
    @Published private(set) var state: FilePreviewState = .loading

    /// Loads `url`. Called from a `.task(id:)`, so a new selection cancels the read for the old file, and a result
    /// that arrives after its cancellation is dropped.
    func load(_ url: URL) async {
        state = .loading
        let result = await FilePreviewLoader.load(url)
        guard !Task.isCancelled else { return }
        state = result
    }
}

/// The selected file in the preview pane: a table for CSV and TSV, and Quick Look for everything else.
/// The read runs off the main actor.
struct FilePreviewView: View {
    /// The height of the preview, in points. The pane is narrow, so a fixed height keeps the card steady.
    static let height: CGFloat = 260

    let url: URL
    @StateObject private var model = FilePreviewModel()

    var body: some View {
        Group {
            switch model.state {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 60)
            case .quickLook(let file):
                QuickLookPreview(url: file)
                    .frame(height: Self.height)
            case .table(let table):
                DelimitedTableView(table: table)
                    .frame(height: Self.height)
            case .tooLarge:
                Text("This file is larger than 25 MB, so it is not previewed.", bundle: L10n.bundle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .unavailable:
                Text("This file can't be previewed.", bundle: L10n.bundle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            await model.load(url)
        }
    }
}

/// The system's Quick Look preview, embedded in the pane. It is the same view the clipboard preview's panel uses.
struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url { view.previewItem = url as NSURL }
    }

    /// Closes the preview when it leaves the screen, so the file is released.
    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}

/// A CSV or TSV table: the header as column titles, then the rows. Long text is cut to one line, and the table
/// scrolls both ways. A note says when the file was cut short.
struct DelimitedTableView: View {
    let table: DelimitedTable

    var body: some View {
        let widest = max(table.headers.count, table.rows.map(\.count).max() ?? 0)
        let columns = min(widest, FilePreviewLoader.maxShownColumns)
        VStack(alignment: .leading, spacing: 6) {
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            Text(Self.cell(table.headers, column))
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                    }
                    GridRow {
                        Divider().gridCellColumns(max(columns, 1))
                    }
                    ForEach(table.rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(0..<columns, id: \.self) { column in
                                Text(Self.cell(table.rows[row], column))
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(2)
            }
            if table.truncated {
                Text("Showing the first \(DelimitedParser.defaultMaxRows) rows and the first 64 KB. The rest of the file is not shown.",
                     bundle: L10n.bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if widest > columns {
                Text("Showing the first \(columns) columns.", bundle: L10n.bundle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The text of one cell. A row shorter than the table shows empty cells at its end.
    private static func cell(_ row: [String], _ column: Int) -> String {
        column < row.count ? row[column] : ""
    }
}
