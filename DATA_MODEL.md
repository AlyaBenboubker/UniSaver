# Data Model

## AcademicYear

- `id: UUID`
- `name: String`
- `startDate: Date`
- `endDate: Date`
- `isActive: Bool`
- `createdAt: Date`
- `updatedAt: Date`
- `semesters: [Semester]`

Rule: end date must be after start date.

## Semester

- `id: UUID`
- `name: String`
- `order: Int`
- `startDate: Date`
- `endDate: Date`
- `status: SemesterStatus`
- `academicYear: AcademicYear?`
- `courses: [Course]`
- timestamps

Rule: dates must be coherent and fit inside the academic year when linked.

## Course

- `id: UUID`
- `name`, `code`, `courseDescription`
- professor fields, room, color, symbol, credits, evaluation method
- `status: AcademicItemStatus`
- `isArchived: Bool`
- `semester: Semester?`
- `chapters: [Chapter]`
- `sessions: [ClassSession]`
- timestamps

## Chapter

- `id: UUID`
- `number`, `title`, `chapterDescription`
- `learningObjectives: [String]`
- `order: Int`
- `status: AcademicItemStatus`
- `isArchived: Bool`
- `course: Course?`
- `sessions: [ClassSession]`
- timestamps

Numbers and orders are preserved and updated explicitly when reordered.

## ClassSession

- `id: UUID`
- `number`, `title`, `sessionDescription`
- `date`, `startTime`, `endTime`
- room, professor, attendance
- learning objectives, important concepts, review tasks
- `progressStatus: SessionProgressStatus`
- `course: Course?`
- `chapter: Chapter?`
- timestamps

Rules: end time must be after start time. A linked chapter must belong to the same course.

## Progress

Session workflow progress:

- captured: 20%
- organized: 40%
- reviewed: 60%
- practiced: 80%
- mastered: 100%

This is structural workflow progress, not academic mastery.
