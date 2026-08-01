import SwiftData
import SwiftUI

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case recent
    case favorites
    case pdfs
    case recordings
    case notes

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All Resources"
        case .recent: "Recently Opened"
        case .favorites: "Favorites"
        case .pdfs: "PDFs"
        case .recordings: "Recordings"
        case .notes: "Notes"
        }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AcademicResource.updatedAt, order: .reverse) private var resources: [AcademicResource]
    @Query(sort: \StudyNote.updatedAt, order: .reverse) private var notes: [StudyNote]
    @Query(sort: \CourseRecording.updatedAt, order: .reverse) private var recordings: [CourseRecording]
    @State private var filter: LibraryFilter = .all
    @State private var searchText = ""
    @State private var importing = false
    @State private var selectedResource: AcademicResource?
    @State private var confirmationMessage: String?

    private var filteredResources: [AcademicResource] {
        resources.filter { resource in
            let matchesSearch = searchText.isEmpty || resource.title.localizedCaseInsensitiveContains(searchText) || resource.course?.name.localizedCaseInsensitiveContains(searchText) == true
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .recent: matchesFilter = resource.lastOpenedAt != nil
            case .favorites: matchesFilter = resource.isFavorite
            case .pdfs: matchesFilter = resource.resourceKind == .pdf
            case .recordings, .notes: matchesFilter = false
            }
            return matchesSearch && matchesFilter
        }
        .sorted {
            switch filter {
            case .recent:
                ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast)
            default:
                $0.updatedAt > $1.updatedAt
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                controls
                if filter == .notes {
                    NoteListView(notes: notes.filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) }, emptyTitle: "No notes") {
                        createLooseNote()
                    }
                } else if filter == .recordings {
                    RecordingListView(recordings: recordings.filter { searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText) })
                } else {
                    ResourceCollectionView(resources: filteredResources, emptyTitle: "No resources", importAction: { importing = true })
                }
            }
            .background(StudyDeskTheme.backgroundPrimary)
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem {
                    Button("Import File", systemImage: "square.and.arrow.down") {
                        importing = true
                    }
                }
            }
            .sheet(isPresented: $importing) {
                ResourceImportView { resource in
                    selectedResource = resource
                    confirmationMessage = "Resource imported"
                }
            }
            .navigationDestination(item: $selectedResource) { resource in
                ResourceDetailView(resource: resource)
            }
            .overlay(alignment: .bottom) {
                if let confirmationMessage {
                    Text(confirmationMessage)
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 18)
                        .task {
                            try? await Task.sleep(for: .seconds(2))
                            self.confirmationMessage = nil
                        }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Filter", selection: $filter) {
                    ForEach(LibraryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search library", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
            }
        }
        .padding()
    }

    private func createLooseNote() -> StudyNote {
        let note = StudyNote(title: "Untitled note")
        modelContext.insert(note)
        try? modelContext.save()
        return note
    }
}
