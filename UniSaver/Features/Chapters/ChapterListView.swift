import SwiftData
import SwiftUI

struct ChapterListView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var course: Course
    @Binding var quickAddTarget: QuickAddTarget?
    @State private var editingChapter: Chapter?
    @State private var deleteChapter: Chapter?
    @State private var showsDeleteConfirmation = false

    private var chapters: [Chapter] {
        course.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            if chapters.isEmpty {
                EmptyStateView(title: "No chapters", message: "Create the first chapter for this class.", systemImage: "list.number", actionTitle: "New Chapter") {
                    quickAddTarget = .chapter(course)
                }
            } else {
                ForEach(chapters) { chapter in
                    NavigationLink {
                        ChapterDetailView(chapter: chapter, quickAddTarget: $quickAddTarget)
                    } label: {
                        ChapterRow(chapter: chapter)
                    }
                    .swipeActions {
                        Button("Archive") {
                            chapter.isArchived = true
                            chapter.updatedAt = .now
                        }
                        .tint(.orange)
                        Button("Delete", role: .destructive) {
                            deleteChapter = chapter
                            showsDeleteConfirmation = true
                        }
                    }
                    .contextMenu {
                        Button("Edit") { editingChapter = chapter }
                        Button("Advance Status") {
                            chapter.status = chapter.status.advanced()
                            chapter.updatedAt = .now
                        }
                        Button("Archive") {
                            chapter.isArchived = true
                            chapter.updatedAt = .now
                        }
                    }
                }
                .onMove(perform: move)
            }
        }
        .toolbar {
            ToolbarItem {
                Button("New Chapter", systemImage: "plus") { quickAddTarget = .chapter(course) }
            }
        }
        .sheet(item: $editingChapter) { chapter in
            ChapterFormView(course: course, chapter: chapter)
        }
        .confirmationDialog("Delete chapter?", isPresented: $showsDeleteConfirmation) {
            Button("Delete Chapter", role: .destructive) {
                if let deleteChapter {
                    modelContext.delete(deleteChapter)
                    self.deleteChapter = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteChapter.map { AcademicValidationService.shouldPreferArchive(chapter: $0) } == true ? "This chapter has linked sessions. Archive is safer unless you are certain." : "This cannot be undone.")
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var reordered = chapters
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, chapter) in reordered.enumerated() {
            chapter.order = index + 1
            chapter.number = index + 1
            chapter.updatedAt = .now
        }
    }
}

struct ChapterRow: View {
    let chapter: Chapter

    var body: some View {
        HStack {
            Text("\(chapter.number)")
                .font(.headline.monospacedDigit())
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading) {
                Text(chapter.title).font(.headline)
                Text(chapter.status.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(chapter.status.progressWeight, format: .percent.precision(.fractionLength(0)))
                .foregroundStyle(.secondary)
        }
    }
}

struct ChapterDetailView: View {
    @Bindable var chapter: Chapter
    @Binding var quickAddTarget: QuickAddTarget?

    var body: some View {
        Form {
            Section("Chapter") {
                Text(chapter.title)
                Text(chapter.chapterDescription.isEmpty ? "No description." : chapter.chapterDescription)
                Picker("Status", selection: $chapter.status) {
                    ForEach(AcademicItemStatus.allCases) { status in
                        Text(status.title).tag(status)
                    }
                }
            }
            Section("Sessions") {
                ForEach(chapter.sessions.sorted { $0.startTime < $1.startTime }) { session in
                    SessionRow(session: session)
                }
                Button("Add session", systemImage: "calendar.badge.plus") {
                    quickAddTarget = .session(chapter.course, chapter)
                }
            }
        }
        .navigationTitle(chapter.title)
    }
}
