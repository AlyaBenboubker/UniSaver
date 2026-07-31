import SwiftUI

struct CourseBinderCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let course: Course
    var isSelected: Bool = false
    @State private var isPressed = false

    private var color: Color { CourseColor.color(for: course.colorIdentifier) }
    private var progress: Double { AcademicValidationService.courseStructuralProgress(course) }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.32))
                .frame(width: 24)
                .offset(x: -8, y: 8)
                .shadow(color: color.opacity(0.28), radius: 8, x: -4, y: 6)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.gradient)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(.black.opacity(0.14))
                        .frame(width: 18)
                        .padding(.leading, 12)
                }
                .overlay(alignment: .topTrailing) {
                    VStack(spacing: 4) {
                        Capsule().fill(.white.opacity(0.72)).frame(width: 54, height: 8)
                        Capsule().fill(.white.opacity(0.55)).frame(width: 42, height: 8)
                    }
                    .padding(14)
                }
                .overlay {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: course.symbolName ?? "book.closed")
                            Text(course.code.isEmpty ? "Course" : course.code)
                            Spacer()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))

                        Spacer()

                        Text(course.name)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)

                        Text(course.professorName.isEmpty ? "No professor set" : course.professorName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.82))

                        ProgressView(value: progress)
                            .tint(.white)

                        HStack {
                            Label("\(course.chapters.filter { !$0.isArchived }.count)", systemImage: "list.number")
                            Label("\(course.sessions.count)", systemImage: "calendar")
                            Spacer()
                            Text(progress, format: .percent.precision(.fractionLength(0)))
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.88))
                    }
                    .padding(18)
                }
                .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 10)
        }
        .frame(height: 220)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : (isPressed ? 0 : -5)), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CourseBinderCard(course: course, isSelected: true)
                .frame(height: 190)
            Text(course.name)
                .font(.title2.weight(.bold))
            Text(course.courseDescription.isEmpty ? "No description yet." : course.courseDescription)
                .foregroundStyle(.secondary)
            ProgressMeter(value: AcademicValidationService.courseStructuralProgress(course))
            Label("\(course.chapters.filter { !$0.isArchived }.count) chapters", systemImage: "list.number")
            Label("\(course.sessions.count) sessions", systemImage: "calendar")
            Spacer()
        }
        .padding()
    }
}
