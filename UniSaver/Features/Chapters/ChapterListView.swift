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
                            try? modelContext.save()
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
                            try? modelContext.save()
                        }
                        Button("Archive") {
                            chapter.isArchived = true
                            chapter.updatedAt = .now
                            try? modelContext.save()
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
                    try? modelContext.save()
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
        try? modelContext.save()
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
    @Environment(\.modelContext) private var modelContext
    @Bindable var chapter: Chapter
    @Binding var quickAddTarget: QuickAddTarget?
    @State private var editingChapter = false
    @State private var deleteConfirmation = false

    private var sortedSessions: [ClassSession] {
        chapter.sessions.sorted { $0.startTime < $1.startTime }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Chapter \(chapter.number)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(chapter.status.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(StudyDeskTheme.surfaceTinted, in: Capsule())
                    }
                    Text(chapter.title)
                        .font(.title2.weight(.bold))
                    Text(chapter.chapterDescription.isEmpty ? "No description yet." : chapter.chapterDescription)
                        .foregroundStyle(.secondary)
                    ProgressMeter(value: chapter.status.progressWeight)
                }
                .padding()
                .deskCard()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Sessions")
                        .font(.headline)
                    if sortedSessions.isEmpty {
                        Text("No sessions linked to this chapter yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedSessions) { session in
                            SessionRow(session: session)
                            if session.id != sortedSessions.last?.id {
                                Divider()
                            }
                        }
                    }
                    Button("Add session", systemImage: "calendar.badge.plus") {
                        quickAddTarget = .session(chapter.course, chapter)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .deskCard()
            }
            .padding()
        }
        .navigationTitle(chapter.title)
        .toolbar {
            ToolbarItemGroup {
                Button("Edit", systemImage: "pencil") { editingChapter = true }
                Button("Delete", systemImage: "trash", role: .destructive) { deleteConfirmation = true }
            }
        }
        .sheet(isPresented: $editingChapter) {
            if let course = chapter.course {
                ChapterFormView(course: course, chapter: chapter)
            }
        }
        .confirmationDialog("Delete chapter?", isPresented: $deleteConfirmation) {
            Button("Delete Chapter", role: .destructive) {
                modelContext.delete(chapter)
                try? modelContext.save()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(AcademicValidationService.shouldPreferArchive(chapter: chapter) ? "This chapter has linked sessions. Archive is safer unless you are certain." : "This cannot be undone.")
        }
        .onChange(of: chapter.status) { _, _ in
            chapter.updatedAt = .now
            try? modelContext.save()
        }
    }
}
