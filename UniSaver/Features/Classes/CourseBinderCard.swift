import SwiftUI

struct CourseBinderCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let course: Course
    var isSelected: Bool = false
    var isCompact = false
    @State private var isPressed = false

    private var color: Color { CourseColor.color(for: course.colorIdentifier) }
    private var progress: Double { AcademicValidationService.courseStructuralProgress(course) }
    private var nextSession: ClassSession? {
        course.sessions.filter { $0.startTime >= .now }.sorted { $0.startTime < $1.startTime }.first
    }
    private var hasResourceSignals: Bool {
        !course.courseDescription.isEmpty || course.evaluationMethod != nil
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(StudyDeskTheme.surfacePrimary)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(StudyDeskTheme.borderSubtle, lineWidth: 1)
                }
                .offset(x: 5, y: -5)
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .opacity(0.9)

            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color)
                    .frame(width: isCompact ? 9 : 12)
                    .padding(.vertical, isCompact ? 10 : 12)

                VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
                    HStack(spacing: 8) {
                        Image(systemName: CourseIconCatalog.sanitizedSymbolName(course.symbolName))
                            .font((isCompact ? Font.body : Font.title3).weight(.semibold))
                            .foregroundStyle(color)
                            .frame(width: isCompact ? 28 : 30, height: isCompact ? 28 : 30)
                            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.code.isEmpty ? "Course" : course.code)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color)
                            Text(course.name)
                                .font((isCompact ? Font.callout : Font.headline).weight(.bold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.9)
                        }
                        Spacer()
                    }

                    if !course.professorName.isEmpty {
                        Text(course.professorName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ProgressBar(value: progress, color: color)

                    HStack {
                        Label("\(course.chapters.filter { !$0.isArchived }.count)", systemImage: "list.number")
                        Label("\(course.sessions.count)", systemImage: "calendar")
                        Spacer()
                        if let nextSession {
                            Text(UniDateFormatters.dayMonth.string(from: nextSession.date))
                        } else {
                            Text("No session")
                        }
                        Image(systemName: hasResourceSignals ? "doc.text.fill" : "doc.text")
                            .foregroundStyle(hasResourceSignals ? color : .secondary)
                            .accessibilityLabel(hasResourceSignals ? "Course information available" : "No resources yet")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(isCompact ? 14 : 16)
            }
            .background(StudyDeskTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    ForEach(course.chapters.filter { !$0.isArchived }.prefix(3)) { chapter in
                        Capsule()
                            .fill(color.opacity(chapter.status == .needsReview ? 0.5 : 0.28))
                            .frame(width: 28, height: 7)
                            .accessibilityLabel(chapter.title)
                    }
                }
                .padding(12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? color.opacity(0.65) : StudyDeskTheme.borderSubtle, lineWidth: isSelected ? 1.5 : 1)
            }
            .shadow(color: isSelected ? color.opacity(0.16) : StudyDeskTheme.shadow, radius: isSelected ? 14 : 8, y: isSelected ? 7 : 3)
        }
        .frame(height: isCompact ? 136 : 150)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : (isPressed ? 0 : -1.5)), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
        .background(isSelected ? color.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 11))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                isPressed.toggle()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(course.name), \(course.chapters.count) chapters, \(course.sessions.count) sessions")
    }
}

struct CourseListRow: View {
    let course: Course

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(CourseColor.color(for: course.colorIdentifier))
                .frame(width: 8, height: 48)
            VStack(alignment: .leading) {
                Text(course.name).font(.headline)
                Text([course.code, course.professorName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(AcademicValidationService.courseStructuralProgress(course), format: .percent.precision(.fractionLength(0)))
                .foregroundStyle(.secondary)
        }
        .padding()
        .deskCard()
    }
}

struct CoursePreviewPane: View {
    let course: Course
    @Binding var quickAddTarget: QuickAddTarget?

    private var nextSession: ClassSession? {
        course.sessions.filter { $0.startTime >= .now }.sorted { $0.startTime < $1.startTime }.first
    }

    private var recentChapters: [Chapter] {
        course.chapters.filter { !$0.isArchived }.sorted { $0.order < $1.order }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                CourseColorBadge(colorIdentifier: course.colorIdentifier, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.name)
                        .font(.title3.weight(.bold))
                    Text([course.code, course.professorName].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ProgressMeter(value: AcademicValidationService.courseStructuralProgress(course))

            if course.chapters.isEmpty && course.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your course is ready")
                        .font(.headline)
                    Text("Add the first chapter, then schedule a class session or attach a resource.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                if let nextSession {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Next session")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(nextSession.title)
                        Text("\(UniDateFormatters.dayMonth.string(from: nextSession.date)) · \(UniDateFormatters.interval(nextSession.startTime, nextSession.endTime))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent chapters")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(recentChapters.prefix(4)) { chapter in
                        HStack {
                            Text("\(chapter.number). \(chapter.title)")
                                .lineLimit(1)
                            Spacer()
                            Text(chapter.status.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            HStack {
                NavigationLink("Open Course") {
                    CourseWorkspaceView(course: course, quickAddTarget: $quickAddTarget)
                }
                .buttonStyle(.borderedProminent)
                Button("Add Chapter") { quickAddTarget = .chapter(course) }
                    .buttonStyle(.bordered)
                Button("Add Session") { quickAddTarget = .session(course, nil) }
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding()
    }
}
