import PDFKit
import SwiftUI

struct PDFKitReaderView: View {
    let url: URL
    let initialPage: Int
    let onPageChange: (Int, Int) -> Void
    @State private var document: PDFDocument?
    @State private var currentPage: Int
    @State private var pageCount = 1
    @State private var searchText = ""
    @State private var errorMessage: String?

    init(url: URL, initialPage: Int, onPageChange: @escaping (Int, Int) -> Void) {
        self.url = url
        self.initialPage = max(initialPage, 1)
        self.onPageChange = onPageChange
        _currentPage = State(initialValue: max(initialPage, 1))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let document {
                PlatformPDFView(document: document, currentPage: $currentPage, searchText: searchText, onPageChange: onPageChange)
                    .onChange(of: currentPage) { _, page in
                        onPageChange(page, pageCount)
                    }
            } else {
                EmptyStateView(title: "PDF unavailable", message: errorMessage ?? "This file cannot be opened as a PDF.", systemImage: "doc.richtext")
                    .padding()
            }
        }
        .onAppear(perform: loadDocument)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button("Previous", systemImage: "chevron.left") {
                currentPage = max(currentPage - 1, 1)
            }
            .labelStyle(.iconOnly)
            .disabled(currentPage <= 1)

            Text("\(currentPage) / \(pageCount)")
                .font(.callout.monospacedDigit())
                .frame(minWidth: 72)

            Button("Next", systemImage: "chevron.right") {
                currentPage = min(currentPage + 1, pageCount)
            }
            .labelStyle(.iconOnly)
            .disabled(currentPage >= pageCount)

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search PDF", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: 260)
            .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
            }
        }
        .padding(12)
        .background(StudyDeskTheme.surfacePrimary)
    }

    private func loadDocument() {
        guard document == nil else { return }
        guard let loaded = PDFDocument(url: url) else {
            errorMessage = "The PDF may be invalid, protected, or missing."
            return
        }
        document = loaded
        pageCount = max(loaded.pageCount, 1)
        currentPage = min(initialPage, pageCount)
        onPageChange(currentPage, pageCount)
    }
}

#if os(iOS)
struct PlatformPDFView: UIViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    let searchText: String
    let onPageChange: (Int, Int) -> Void

    func makeUIView(context: Context) -> PDFView {
        makePDFView(context: context)
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        updatePDFView(pdfView, context: context)
    }
}
#else
struct PlatformPDFView: NSViewRepresentable {
    let document: PDFDocument
    @Binding var currentPage: Int
    let searchText: String
    let onPageChange: (Int, Int) -> Void

    func makeNSView(context: Context) -> PDFView {
        makePDFView(context: context)
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        updatePDFView(pdfView, context: context)
    }
}
#endif

extension PlatformPDFView {
    func makeCoordinator() -> Coordinator {
        Coordinator(currentPage: $currentPage, onPageChange: onPageChange)
    }

    func makePDFView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: Notification.Name.PDFViewPageChanged,
            object: pdfView
        )
        if let page = document.page(at: max(currentPage - 1, 0)) {
            pdfView.go(to: page)
        }
        context.coordinator.pdfView = pdfView
        return pdfView
    }

    func updatePDFView(_ pdfView: PDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        if let page = document.page(at: max(currentPage - 1, 0)),
           pdfView.currentPage !== page {
            pdfView.go(to: page)
        }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pdfView.highlightedSelections = document.findString(searchText, withOptions: .caseInsensitive)
        } else {
            pdfView.highlightedSelections = nil
        }
    }

    final class Coordinator: NSObject {
        @Binding private var currentPage: Int
        private let onPageChange: (Int, Int) -> Void
        weak var pdfView: PDFView?

        init(currentPage: Binding<Int>, onPageChange: @escaping (Int, Int) -> Void) {
            _currentPage = currentPage
            self.onPageChange = onPageChange
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let index = document.index(for: page) + 1
            currentPage = index
            onPageChange(index, max(document.pageCount, 1))
        }
    }
}
